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
    private var launcherWindowController: LauncherWindowController?
    private let cleaningManager = CleaningModeManager.shared
    private let safetyManager = SafetyManager.shared
    private let hotkeyManager = HotkeyManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        safetyManager.installSignalHandlers()
        safetyManager.installLifecycleObservers()

        if Preferences.shared.launchMode == .launcher {
            setupLauncherMode()
        } else {
            setupPersistentMode()
        }
    }

    // MARK: - Persistent mode

    private func setupPersistentMode() {
        menuBarController = MenuBarController()

        hotkeyManager.onTrigger = { [weak self] in
            self?.cleaningManager.toggle()
        }
        hotkeyManager.registerStoredHotkey()

        cleaningManager.onDeactivated = { [weak self] in
            // Return to idle — menu bar remains active.
            self?.menuBarController?.refreshToggleTitle()
        }
    }

    // MARK: - Launcher mode

    private func setupLauncherMode() {
        let launcher = LauncherWindowController()

        launcher.onStartCleaning = { [weak self] in
            self?.launcherWindowController?.hideLauncher()
            self?.cleaningManager.activate()
        }

        launcher.onQuit = { [weak self] in
            self?.cleaningManager.forceDeactivate(reason: .appTermination)
            self?.hotkeyManager.unregister()
            NSApp.terminate(nil)
        }

        launcher.onSettings = { [weak self] in
            self?.openSettings()
        }

        launcher.showLauncher()
        launcherWindowController = launcher

        cleaningManager.onDeactivated = { [weak self] in
            // Return to launcher window after cleaning.
            self?.launcherWindowController?.showLauncher()
        }
    }

    // MARK: - Settings

    private func openSettings() {
        // Use the same settings path as the menu bar controller.
        if let mbc = menuBarController {
            mbc.openSettings()
        } else {
            // Launcher mode — create an ad-hoc settings controller.
            let settingsWC = SettingsWindowController()
            settingsWC.showWindow(nil)
            // Keep alive by associating with the launcher.
            objc_setAssociatedObject(
                launcherWindowController as Any,
                &settingsKey,
                settingsWC,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var settingsKey: UInt8 = 0

    // MARK: - Termination

    func applicationWillTerminate(_ notification: Notification) {
        cleaningManager.forceDeactivate(reason: .appTermination)
        hotkeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Preferences.shared.launchMode == .launcher {
            launcherWindowController?.showLauncher()
            return true
        }
        return false
    }
}
