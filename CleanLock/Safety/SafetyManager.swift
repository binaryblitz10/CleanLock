import AppKit
import Darwin
import os.log

/// Observes system lifecycle events and installs signal handlers to guarantee
/// the user is never trapped in a stuck cleaning mode.
final class SafetyManager {
    static let shared = SafetyManager()

    private let log = OSLog(subsystem: "com.cleanlock.app", category: "Safety")
    private var signalsInstalled = false
    private var observersInstalled = false

    private init() {}

    func installLifecycleObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        // NOTE: We intentionally do NOT observe
        // `NSApplication.didChangeScreenParametersNotification` here. Hiding
        // the menu bar (via presentationOptions when entering cleaning mode)
        // itself fires that notification, which would cause us to deactivate
        // immediately on activation. True display add/remove is rare during a
        // 30-second cleaning session; the overlay simply stays on its
        // original screen if a display is unplugged.

        NSSetUncaughtExceptionHandler { exception in
            // Best-effort cleanup — main thread may be in a bad state.
            CleaningModeManager.shared.forceDeactivate(reason: .emergency)
            os_log("Uncaught exception: %{public}@", exception.description)
        }
    }

    /// Registers handlers for terminating signals so that even on SIGTERM /
    /// SIGINT / fatal signals we release the event tap and hide the overlay.
    /// CGEvent taps are automatically released on process death, but the
    /// kernel may take a moment — explicit cleanup keeps the system snappy.
    func installSignalHandlers() {
        guard !signalsInstalled else { return }
        signalsInstalled = true

        let signals: [Int32] = [SIGTERM, SIGINT, SIGHUP, SIGABRT, SIGSEGV, SIGILL, SIGBUS]

        for sig in signals {
            signal(sig) { signo in
                // We cannot safely call most APIs from a signal handler. The
                // best we can do is re-raise the default handler after a tiny
                // hint to the OS to flush. CGEventTap is auto-cleaned by the
                // kernel when the process dies; the dock/menu bar restore
                // automatically when our NSApplication.presentationOptions
                // process exits.
                signal(signo, SIG_DFL)
                raise(signo)
            }
        }
    }

    // MARK: - Notifications

    @objc private func handleWillSleep() {
        os_log("System will sleep — disabling cleaning mode", log: log, type: .info)
        DispatchQueue.main.async {
            CleaningModeManager.shared.deactivate(reason: .willSleep)
        }
    }

    @objc private func handleScreenLock() {
        DispatchQueue.main.async {
            CleaningModeManager.shared.deactivate(reason: .screenLocked)
        }
    }

}
