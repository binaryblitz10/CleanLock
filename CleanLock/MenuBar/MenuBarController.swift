import AppKit
import os.log

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let manager = CleaningModeManager.shared
    private var settingsWindowController: SettingsWindowController?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "CleanLock") {
                image.isTemplate = true
                button.image = image
            } else {
                // Fallback: draw a simple text icon if the SF Symbol is unavailable.
                button.title = "⌨"
                os_log("SF Symbol 'keyboard' not available, using fallback text icon",
                       log: OSLog(subsystem: "com.cleanlock.app", category: "MenuBar"),
                       type: .default)
            }
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
            title: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        // Don't set image at all to avoid any icon or spacing
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "About CleanLock",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        // Ensure no icon
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit CleanLock",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        // Ensure no icon
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

    func refreshToggleTitle() {
        // Let the next menu open refresh the title naturally.
    }

    @objc private func toggleCleaningMode() {
        manager.toggle()
    }

    @objc func openSettings() {
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

        Hold both Command (\u{2318}) keys for 3 seconds to exit cleaning mode.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
