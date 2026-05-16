import AppKit

@main
final class AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let cleaningManager = CleaningModeManager.shared
    private let safetyManager = SafetyManager.shared
    private let hotkeyManager = HotkeyManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install signal handlers first — guarantee cleanup on crash/termination.
        safetyManager.installSignalHandlers()
        safetyManager.installLifecycleObservers()

        if Preferences.shared.launchMode == .ephemeral {
            setupEphemeralMode()
        } else {
            setupPersistentMode()
        }
    }

    private func setupPersistentMode() {
        // Full menu bar utility — current default behavior.
        menuBarController = MenuBarController()

        hotkeyManager.onTrigger = { [weak self] in
            self?.cleaningManager.toggle()
        }
        hotkeyManager.registerStoredHotkey()
    }

    private func setupEphemeralMode() {
        // Skip menu bar, hotkey, and idle listeners. Jump straight into
        // Cleaning Mode. After teardown, the app terminates completely.
        cleaningManager.onDeactivated = { [weak self] in
            self?.cleaningManager.forceDeactivate(reason: .appTermination)
            self?.hotkeyManager.unregister()
            NSApp.terminate(nil)
        }

        // Let the runloop settle then activate — ensures the app is fully
        // registered with the window server before we try to show the overlay.
        DispatchQueue.main.async { [weak self] in
            self?.cleaningManager.activate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Fail-safe: always tear down before exiting.
        cleaningManager.forceDeactivate(reason: .appTermination)
        hotkeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // In persistent mode we're a menu-bar agent — no window to reopen.
        // In ephemeral mode the app should already be in Cleaning Mode or
        // terminating, so returning false is correct either way.
        return false
    }
}
