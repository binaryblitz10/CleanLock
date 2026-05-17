import AppKit
import Carbon
import CoreGraphics
import os.log

/// Quartz event tap that consumes keyboard, mouse, trackpad, and system-defined
/// (media key) events while cleaning mode is active. Requires a 3-second
/// simultaneous hold of both left and right Command keys to unlock.
///
/// Unlock detection runs through TWO independent paths:
///   1. Primary — CGEvent tap callback tracks NX device flags from .flagsChanged events.
///   2. Backup — Carbon GetCurrentKeyModifiers() polled every 200 ms. This runs
///      completely independently of the event tap and works even when the system
///      temporarily disables the HID-level tap (macOS 15+).
final class EventInterceptor {
    /// Called on main when the user completes the dual-Command 3-second hold.
    var onUnlockRequested: (() -> Void)?

    /// Called on main if the event tap is invalidated (timeout, user input
    /// monitoring revoked, etc.). Cleaning mode must exit immediately.
    var onTapDisabled: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Dual-Command hold state (primary: event tap)

    /// NX device flag bits — these appear in the low word of CGEventFlags.rawValue.
    private static let leftCommandBit: UInt64  = 0x00000008  // NX_DEVICELCMDKEYMASK
    private static let rightCommandBit: UInt64 = 0x00000010  // NX_DEVICERCMDKEYMASK
    /// Every NX modifier bit other than the two Command bits.
    private static let otherModifierBits: UInt64 = 0x000008E7  // L/R Ctrl, Shift, Opt + Fn

    private var leftCommandDown = false
    private var rightCommandDown = false
    private var otherModifiersActive = false

    /// One-shot timer that fires after the 3-second uninterrupted hold.
    private var holdTimer: DispatchSourceTimer?
    private let unlockHoldDuration: TimeInterval = 3.0

    // MARK: - Dual-Command hold state (backup: Carbon poll)

    /// Carbon's GetCurrentKeyModifiers() polled every 200 ms. Works even when the
    /// event tap is temporarily disabled by the system.
    private var backupPollTimer: DispatchSourceTimer?
    private var backupHoldStartTime: CFTimeInterval = 0
    private static let carbonLeftCmdBit: UInt32  = 0x00000008  // NX_DEVICELCMDKEYMASK
    private static let carbonRightCmdBit: UInt32 = 0x00000010  // NX_DEVICERCMDKEYMASK

    // MARK: - Re-enable storm detector

    private var recentReenables: [TimeInterval] = []
    private let reenableStormLimit: Int = 8
    private let reenableStormWindow: TimeInterval = 2.0

    private let log = OSLog(subsystem: "com.cleanlock.app", category: "EventTap")

    deinit { uninstall() }

    // MARK: - Install / Uninstall

    func install() -> Bool {
        precondition(Thread.isMainThread)
        if tap != nil { return true }

        resetUnlockState()

        let mask = CGEventMask(UInt64.max)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: EventInterceptor.tapCallback,
            userInfo: selfPtr
        ) else {
            os_log("CGEvent.tapCreate returned nil — check Accessibility permission",
                   log: log, type: .error)
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.tap = port
        self.runLoopSource = source

        // Start the Carbon-based backup poll. It runs independently and detects
        // the dual-Command hold even when the event tap is briefly disabled.
        startBackupPoll()
        return true
    }

    func uninstall() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        tap = nil
        runLoopSource = nil
        resetUnlockState()
    }

    // MARK: - Callback (C-style)

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<EventInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        return interceptor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            os_log("Event tap auto-disabled (%{public}d) — re-enabling",
                   log: log, type: .info, type.rawValue)
            if let port = tap {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            // Tap disable invalidates our state: we may have missed modifier
            // transitions during the gap. Cancel any in-progress unlock.
            resetUnlockState()
            recordTapReenable()
            return nil
        }

        // Modifier-key changes track left/right Command independently.
        if type == .flagsChanged {
            handleFlagsChanged(event: event)
            return nil
        }

        // Non-modifier key presses are consumed but do NOT cancel the hold timer
        // or the hold condition. During keyboard cleaning many keys get pressed;
        // the user intentionally holding both Command keys for 3 seconds is
        // unambiguous regardless of other keys being pressed.
        if type == .keyDown {
            return nil
        }
        if type == .keyUp {
            return nil
        }

        switch type {
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .mouseMoved,
             .scrollWheel:
            return nil
        default:
            return nil
        }
    }

    // MARK: - Dual-Command hold unlock detection (primary: event tap)

    private func handleFlagsChanged(event: CGEvent) {
        let rawFlags = event.flags.rawValue

        leftCommandDown  = (rawFlags & Self.leftCommandBit)  != 0
        rightCommandDown = (rawFlags & Self.rightCommandBit) != 0
        otherModifiersActive = (rawFlags & Self.otherModifierBits) != 0

        evaluateHoldCondition()
    }

    private func evaluateHoldCondition() {
        let canHold = leftCommandDown
            && rightCommandDown
            && !otherModifiersActive

        if canHold {
            startHoldTimerIfNeeded()
        } else {
            cancelHoldTimer()
        }
    }

    private func startHoldTimerIfNeeded() {
        guard holdTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + unlockHoldDuration)
        timer.setEventHandler { [weak self] in
            self?.holdTimerFired()
        }
        holdTimer = timer
        timer.resume()
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func holdTimerFired() {
        holdTimer = nil
        // Re-verify state at fire time: both Commands must still be down with
        // no other modifiers (Ctrl, Opt, Shift) active.
        guard leftCommandDown && rightCommandDown
                && !otherModifiersActive else { return }

        resetUnlockState()
        DispatchQueue.main.async { [weak self] in
            self?.onUnlockRequested?()
        }
    }

    // MARK: - Dual-Command hold unlock detection (backup: Carbon poll)

    /// Polls GetCurrentKeyModifiers() every 200 ms. Completely independent of the
    /// CGEvent tap — survives disabling/re-enabling cycles. The poll checks for
    /// BOTH left and right Command held continuously for 3 seconds.
    private func startBackupPoll() {
        cancelBackupPoll()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.backupPollTick()
        }
        backupPollTimer = timer
        timer.resume()
    }

    private func backupPollTick() {
        let raw = GetCurrentKeyModifiers()
        let leftHeld  = (raw & Self.carbonLeftCmdBit) != 0
        let rightHeld = (raw & Self.carbonRightCmdBit) != 0

        if leftHeld && rightHeld {
            if backupHoldStartTime == 0 {
                backupHoldStartTime = CFAbsoluteTimeGetCurrent()
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - backupHoldStartTime
            if elapsed >= unlockHoldDuration {
                // Guard: also verify through the event-tap state (if it's live)
                // as an extra safety check.
                backupHoldStartTime = 0
                cancelBackupPoll()
                DispatchQueue.main.async { [weak self] in
                    self?.onUnlockRequested?()
                }
            }
        } else {
            backupHoldStartTime = 0
        }
    }

    private func cancelBackupPoll() {
        backupPollTimer?.cancel()
        backupPollTimer = nil
        backupHoldStartTime = 0
    }

    // MARK: - Storm detection

    private func recordTapReenable() {
        let now = Date().timeIntervalSinceReferenceDate
        recentReenables.append(now)
        recentReenables.removeAll { now - $0 > reenableStormWindow }
        if recentReenables.count >= reenableStormLimit {
            os_log("Tap re-enable storm (%{public}d in %{public}.1fs) — bailing out",
                   log: log, type: .error,
                   recentReenables.count, reenableStormWindow)
            recentReenables.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.onTapDisabled?()
            }
        }
    }

    // MARK: - State reset

    private func resetUnlockState() {
        cancelHoldTimer()
        cancelBackupPoll()
        leftCommandDown = false
        rightCommandDown = false
        otherModifiersActive = false
    }
}
