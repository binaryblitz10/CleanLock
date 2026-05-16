import AppKit
import ApplicationServices

final class PermissionsManager {
    static let shared = PermissionsManager()
    private init() {}

    /// Non-prompting check.
    func hasAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompts the system to show the standard "needs Accessibility" dialog,
    /// and offers to open System Settings.
    func promptForAccessibility() {
        // This shows the system's prompt the first time; subsequent calls are no-ops.
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true
        ]
        _ = AXIsProcessTrustedWithOptions(opts)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "CleanLock needs Accessibility access"
        alert.informativeText = """
        To intercept keyboard and trackpad input while you clean, CleanLock needs Accessibility permission.

        Open System Settings → Privacy & Security → Accessibility and enable CleanLock.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// Opens the Accessibility privacy pane in System Settings without showing
    /// the alert. Suitable for direct invocation from the Settings window.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
