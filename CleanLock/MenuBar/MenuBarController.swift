import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let manager = CleaningModeManager.shared
    private var settingsWindowController: SettingsWindowController?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // SF Symbol "keyboard.badge.eye" exists on macOS 13+; fall back if missing.
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "CleanLock")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "CleanLock"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let toggleItem = NSMenuItem(
            title: "Start Cleaning Mode",
            action: #selector(toggleCleaningMode),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.tag = MenuTag.toggle.rawValue
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "About CleanLock",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit CleanLock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    enum MenuTag: Int {
        case toggle = 1001
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let toggle = menu.item(withTag: MenuTag.toggle.rawValue) else { return }
        toggle.title = manager.state == .active ? "Exit Cleaning Mode" : "Start Cleaning Mode"
        toggle.isEnabled = manager.state == .idle || manager.state == .active
    }

    @objc private func toggleCleaningMode() {
        manager.toggle()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "CleanLock"
        alert.informativeText = """
        Temporarily disables your keyboard and trackpad so you can clean them.

        Hold both Command (⌘) keys for 3 seconds to exit cleaning mode.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
