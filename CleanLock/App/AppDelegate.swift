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

        // Always create the menu bar controller so the icon is visible
        // regardless of startup mode. In launcher mode, the launcher window
        // appears on top of the menu bar icon.
        menuBarController = MenuBarController()

        applyLaunchMode(Preferences.shared.launchMode, fromSettings: false)

        // Observe launch mode changes so they apply immediately.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(launchModeDidChange),
            name: .launchModeDidChange,
            object: nil
        )
    }

    @objc private func launchModeDidChange() {
        applyLaunchMode(Preferences.shared.launchMode, fromSettings: true)
    }

    private func applyLaunchMode(_ mode: Preferences.LaunchMode, fromSettings: Bool = false) {
        // Tear down launcher if it was active.
        if mode != .launcher {
            launcherWindowController?.hideLauncher()
            launcherWindowController = nil
        }

        switch mode {
        case .launcher:
            setupLauncherMode(showImmediately: !fromSettings)
        case .persistent:
            setupPersistentMode()
        }
    }

    // MARK: - Persistent mode

    private func setupPersistentMode() {
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

    private func setupLauncherMode(showImmediately: Bool = true) {
        if launcherWindowController != nil { return }

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

        launcherWindowController = launcher

        cleaningManager.onDeactivated = { [weak self] in
            self?.launcherWindowController?.showLauncher()
        }

        if showImmediately {
            cleaningManager.activate()
        }
    }

    // MARK: - Settings

    private func openSettings() {
        menuBarController?.openSettings()
    }

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
