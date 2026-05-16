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

        menuBarController = MenuBarController()

        hotkeyManager.onTrigger = { [weak self] in
            self?.cleaningManager.toggle()
        }
        hotkeyManager.registerStoredHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Fail-safe: always tear down before exiting.
        cleaningManager.forceDeactivate(reason: .appTermination)
        hotkeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
