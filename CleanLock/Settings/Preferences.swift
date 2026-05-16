import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Persistent user preferences. Backed by UserDefaults.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let autoUnlockSeconds = "autoUnlockSeconds"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
    }

    private init() {
        defaults.register(defaults: [
            Key.autoUnlockSeconds: 300, // 5 minutes
            Key.hotkeyKeyCode: kVK_ANSI_K,
            // Carbon modifiers: Ctrl + Shift + Cmd
            Key.hotkeyModifiers: Int(controlKey | shiftKey | cmdKey),
            Key.launchAtLogin: false,
        ])
    }

    // MARK: - Auto-unlock timeout

    /// Seconds before cleaning mode auto-exits. 0 = disabled.
    var autoUnlockSeconds: Int {
        get { defaults.integer(forKey: Key.autoUnlockSeconds) }
        set { defaults.set(newValue, forKey: Key.autoUnlockSeconds) }
    }

    // MARK: - Hotkey

    struct Hotkey {
        var keyCode: UInt32
        /// Carbon-style modifier mask (controlKey | shiftKey | cmdKey | optionKey).
        var carbonModifiers: UInt32
    }

    var hotkey: Hotkey {
        get {
            Hotkey(
                keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotkeyModifiers)
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin)
            applyLaunchAtLogin(newValue)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("CleanLock: failed to set launch-at-login: \(error)")
            }
        }
    }
}
