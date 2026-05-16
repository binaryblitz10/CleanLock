import AppKit
import os.log

/// State machine for cleaning mode. Single source of truth.
/// All transitions happen on the main thread.
final class CleaningModeManager {
    static let shared = CleaningModeManager()

    enum State {
        case idle
        case activating
        case active
        case deactivating
        case failed
    }

    enum DeactivateReason {
        case userUnlock
        case userToggle
        case willSleep
        case screenLocked
        case displayChange
        case eventTapDisabled
        case timeout
        case permissionLost
        case appTermination
        case emergency
    }

    private(set) var state: State = .idle

    /// Called after deactivation completes. The owner (AppDelegate) decides
    /// what happens next — show launcher, terminate, or return to idle.
    var onDeactivated: (() -> Void)?

    private let interceptor = EventInterceptor()
    private let overlay = OverlayWindowController()
    private let cursor = CursorHider()
    private var autoUnlockTimer: DispatchSourceTimer?
    private var permissionRetryTimer: DispatchSourceTimer?

    private let log = OSLog(subsystem: "com.cleanlock.app", category: "CleaningMode")

    private init() {
        interceptor.onUnlockRequested = { [weak self] in
            self?.deactivate(reason: .userUnlock)
        }
        interceptor.onTapDisabled = { [weak self] in
            self?.deactivate(reason: .eventTapDisabled)
        }
    }

    // MARK: - Public API

    func toggle() {
        switch state {
        case .idle, .failed:
            activate()
        case .active:
            deactivate(reason: .userToggle)
        case .activating, .deactivating:
            break
        }
    }

    func activate() {
        precondition(Thread.isMainThread)
        guard state == .idle || state == .failed else { return }

        guard PermissionsManager.shared.hasAccessibility() else {
            state = .failed
            PermissionsManager.shared.promptForAccessibility()
            if Preferences.shared.launchMode == .launcher {
                schedulePermissionRetry()
            }
            return
        }

        state = .activating
        os_log("Activating cleaning mode", log: log, type: .info)

        overlay.show()

        guard interceptor.install() else {
            os_log("Failed to install event tap", log: log, type: .error)
            overlay.hide()
            state = .failed
            showFailureAlert(message: "Could not install the system event tap. Check Accessibility permissions in System Settings.")
            return
        }

        cursor.hide()
        startAutoUnlockTimerIfNeeded()
        state = .active
        os_log("Cleaning mode active", log: log, type: .info)
    }

    func deactivate(reason: DeactivateReason) {
        precondition(Thread.isMainThread)
        guard state == .active || state == .activating || state == .failed else {
            performTeardown()
            return
        }

        state = .deactivating
        os_log("Deactivating: %{public}@", log: log, type: .info, String(describing: reason))

        performTeardown()
        state = .idle

        onDeactivated?()
    }

    /// Synchronous, no-checks teardown — used from termination / crash paths.
    func forceDeactivate(reason: DeactivateReason) {
        os_log("Force deactivate: %{public}@", log: log, type: .info, String(describing: reason))
        performTeardown()
        state = .idle
    }

    // MARK: - Private

    private func performTeardown() {
        cancelAutoUnlockTimer()
        cancelPermissionRetry()
        interceptor.uninstall()
        overlay.hide()
        cursor.show()
    }

    private func startAutoUnlockTimerIfNeeded() {
        cancelAutoUnlockTimer()
        let seconds = Preferences.shared.autoUnlockSeconds
        guard seconds > 0 else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(seconds))
        timer.setEventHandler { [weak self] in
            self?.deactivate(reason: .timeout)
        }
        autoUnlockTimer = timer
        timer.resume()
    }

    private func cancelAutoUnlockTimer() {
        autoUnlockTimer?.cancel()
        autoUnlockTimer = nil
    }

    private func showFailureAlert(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "CleanLock could not start"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func schedulePermissionRetry() {
        cancelPermissionRetry()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: .seconds(2), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard PermissionsManager.shared.hasAccessibility() else { return }
            self.cancelPermissionRetry()
            self.state = .idle
            self.activate()
        }
        permissionRetryTimer = timer
        timer.resume()
    }

    private func cancelPermissionRetry() {
        permissionRetryTimer?.cancel()
        permissionRetryTimer = nil
    }
}
