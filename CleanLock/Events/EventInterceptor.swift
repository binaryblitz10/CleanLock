import AppKit
import CoreGraphics
import os.log

/// Quartz event tap that consumes keyboard, mouse, trackpad, and system-defined
/// (media key) events while cleaning mode is active. Counts discrete Command
/// presses for the unlock sequence.
final class EventInterceptor {
    /// Called on main when the user completes the 6× Command unlock.
    var onUnlockRequested: (() -> Void)?

    /// Called on main if the event tap is invalidated (timeout, user input
    /// monitoring revoked, etc.). Cleaning mode must exit immediately.
    var onTapDisabled: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var commandPressCount: Int = 0
    private var lastCommandPressTime: TimeInterval = 0
    private var commandCurrentlyDown: Bool = false

    private let unlockRequiredCount: Int = 6
    private let unlockResetInterval: TimeInterval = 3.0

    private let log = OSLog(subsystem: "com.cleanlock.app", category: "EventTap")

    deinit { uninstall() }

    // MARK: - Install / Uninstall

    func install() -> Bool {
        precondition(Thread.isMainThread)
        if tap != nil { return true }

        resetUnlockCounter()

        // Capture every event type; we make per-event filtering decisions in
        // the callback. Using all-events is simpler and well-supported, and
        // avoids the maintenance burden of an explicit mask that may miss
        // future event types.
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
        return true
    }

    func uninstall() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        // Invalidate the mach port so the kernel side releases it promptly.
        CFMachPortInvalidate(port)
        tap = nil
        runLoopSource = nil
        resetUnlockCounter()
    }

    // MARK: - Callback (C-style)

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<EventInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
        return interceptor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // System told us the tap is disabled — recover by signaling deactivate.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            os_log("Event tap disabled (%{public}d) — bailing out",
                   log: log, type: .error, type.rawValue)
            DispatchQueue.main.async { [weak self] in
                self?.onTapDisabled?()
            }
            // Don't return the event; system will route normally after we're gone.
            return nil
        }

        // Detect a fresh Command-key press (transition into Cmd-down).
        if type == .flagsChanged {
            handleFlagsChanged(event: event)
            return nil
        }

        switch type {
        case .keyDown, .keyUp:
            return nil
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .mouseMoved,
             .scrollWheel:
            return nil
        default:
            // Includes systemDefined (media keys), tabletPointer, tabletProximity, etc.
            // Swallow everything. The kCGHIDEventTap level intercepts before
            // most system shortcuts can be acted upon.
            return nil
        }
    }

    // MARK: - Command-key unlock detection

    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        let cmdDown = flags.contains(.maskCommand)

        // Only react on a fresh down-transition (filters key-repeat / hold).
        let wasDown = commandCurrentlyDown
        commandCurrentlyDown = cmdDown

        guard cmdDown && !wasDown else { return }

        let now = Date().timeIntervalSinceReferenceDate
        if now - lastCommandPressTime > unlockResetInterval {
            commandPressCount = 0
        }
        lastCommandPressTime = now
        commandPressCount += 1

        if commandPressCount >= unlockRequiredCount {
            commandPressCount = 0
            DispatchQueue.main.async { [weak self] in
                self?.onUnlockRequested?()
            }
        }
    }

    private func resetUnlockCounter() {
        commandPressCount = 0
        commandCurrentlyDown = false
        lastCommandPressTime = 0
    }
}
