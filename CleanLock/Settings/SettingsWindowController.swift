import AppKit
import Carbon.HIToolbox

/// Minimal AppKit settings window — no SwiftUI, no Interface Builder.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let timeoutPopup = NSPopUpButton()
    private let hotkeyField = HotkeyRecorderField()
    private let launchToggle = NSButton(checkboxWithTitle: "Launch at login",
                                        target: nil, action: nil)
    private let persistentRadio = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let ephemeralRadio = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let accessibilityStatusField = NSTextField(labelWithString: "")
    private let accessibilityGrantButton = NSButton(title: "Grant Access…", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 370),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CleanLock Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildLayout()
        loadValues()
    }

    private func buildLayout() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        // ── Startup Behavior section ──
        let sectionLabel = NSTextField(labelWithString: "Startup Behavior")
        sectionLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.alignment = .left

        let persistentRow = makeModeRow(
            radio: persistentRadio,
            title: Preferences.LaunchMode.persistent.displayName,
            subtitle: Preferences.LaunchMode.persistent.subtitle
        )
        persistentRadio.tag = 0
        persistentRadio.target = self
        persistentRadio.action = #selector(modeChanged)

        let ephemeralRow = makeModeRow(
            radio: ephemeralRadio,
            title: Preferences.LaunchMode.ephemeral.displayName,
            subtitle: Preferences.LaunchMode.ephemeral.subtitle
        )
        ephemeralRadio.tag = 1
        ephemeralRadio.target = self
        ephemeralRadio.action = #selector(modeChanged)

        // ── Settings section ──
        let separator = NSBox()
        separator.boxType = .separator

        // Timeout row
        timeoutPopup.addItems(withTitles: [
            "Disabled",
            "1 minute",
            "3 minutes",
            "5 minutes",
            "10 minutes",
            "30 minutes",
        ])
        timeoutPopup.target = self
        timeoutPopup.action = #selector(timeoutChanged)
        let timeoutRow = labeledRow(label: "Auto-unlock after:", control: timeoutPopup)

        // Hotkey row
        hotkeyField.onChange = { keyCode, mods in
            Preferences.shared.hotkey = .init(keyCode: keyCode, carbonModifiers: mods)
            HotkeyManager.shared.registerStoredHotkey()
        }
        let hotkeyRow = labeledRow(label: "Activation shortcut:", control: hotkeyField)

        // ── Accessibility permission row ──
        accessibilityGrantButton.target = self
        accessibilityGrantButton.action = #selector(grantAccessibilityTapped)
        accessibilityGrantButton.bezelStyle = .rounded

        let accessControl = NSStackView(views: [accessibilityStatusField, accessibilityGrantButton])
        accessControl.orientation = .horizontal
        accessControl.spacing = 8
        accessControl.alignment = .firstBaseline

        let accessibilityRow = labeledRow(label: "Accessibility:", control: accessControl)

        // Launch-at-login row
        launchToggle.target = self
        launchToggle.action = #selector(launchToggleChanged)

        stack.addArrangedSubview(sectionLabel)
        stack.addArrangedSubview(persistentRow)
        stack.addArrangedSubview(ephemeralRow)
        stack.addArrangedSubview(separator)
        stack.setCustomSpacing(4, after: sectionLabel)
        stack.setCustomSpacing(4, after: persistentRow)
        stack.setCustomSpacing(4, after: ephemeralRow)
        stack.addArrangedSubview(timeoutRow)
        stack.addArrangedSubview(hotkeyRow)
        stack.addArrangedSubview(accessibilityRow)
        stack.addArrangedSubview(launchToggle)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])
    }

    /// Creates a row with a radio button, a bold title, and a subtitle beneath it.
    private func makeModeRow(radio: NSButton, title: String, subtitle: String) -> NSStackView {
        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleField.textColor = .secondaryLabelColor

        let labelStack = NSStackView(views: [titleField, subtitleField])
        labelStack.orientation = .vertical
        labelStack.spacing = 0
        labelStack.alignment = .leading

        let row = NSStackView(views: [radio, labelStack])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .top
        return row
    }

    private func labeledRow(label: String, control: NSView) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [labelField, control])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .firstBaseline
        labelField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        return row
    }

    private func loadValues() {
        let prefs = Preferences.shared
        timeoutPopup.selectItem(at: timeoutIndex(for: prefs.autoUnlockSeconds))
        hotkeyField.set(keyCode: prefs.hotkey.keyCode, modifiers: prefs.hotkey.carbonModifiers)
        let isPersistent = Preferences.shared.launchMode == .persistent
        persistentRadio.state = isPersistent ? .on : .off
        ephemeralRadio.state = isPersistent ? .off : .on
        updateLaunchToggleEnabled()
        refreshAccessibilityStatus()
    }

    private func refreshAccessibilityStatus() {
        if PermissionsManager.shared.hasAccessibility() {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemGreen,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
            accessibilityStatusField.attributedStringValue = NSAttributedString(
                string: "Granted ✓", attributes: attrs
            )
            accessibilityGrantButton.isHidden = true
        } else {
            accessibilityStatusField.stringValue = "Not Granted"
            accessibilityStatusField.textColor = .secondaryLabelColor
            accessibilityGrantButton.isHidden = false
        }
    }

    private func timeoutIndex(for seconds: Int) -> Int {
        switch seconds {
        case 0: return 0
        case 60: return 1
        case 180: return 2
        case 300: return 3
        case 600: return 4
        case 1800: return 5
        default: return 3
        }
    }

    private func secondsForTimeoutIndex(_ idx: Int) -> Int {
        switch idx {
        case 0: return 0
        case 1: return 60
        case 2: return 180
        case 3: return 300
        case 4: return 600
        case 5: return 1800
        default: return 300
        }
    }

    private func updateLaunchToggleEnabled() {
        let isEphemeral = Preferences.shared.launchMode == .ephemeral
        launchToggle.isEnabled = !isEphemeral
        if isEphemeral {
            launchToggle.state = .off
            if Preferences.shared.launchAtLogin {
                Preferences.shared.launchAtLogin = false
            }
        } else {
            launchToggle.state = Preferences.shared.launchAtLogin ? .on : .off
        }
    }

    @objc private func modeChanged() {
        let newMode: Preferences.LaunchMode = ephemeralRadio.state == .on ? .ephemeral : .persistent
        persistentRadio.state = newMode == .persistent ? .on : .off
        ephemeralRadio.state = newMode == .ephemeral ? .on : .off
        Preferences.shared.launchMode = newMode
        updateLaunchToggleEnabled()
    }

    @objc private func timeoutChanged() {
        Preferences.shared.autoUnlockSeconds = secondsForTimeoutIndex(timeoutPopup.indexOfSelectedItem)
    }

    @objc private func launchToggleChanged() {
        Preferences.shared.launchAtLogin = launchToggle.state == .on
    }

    @objc private func grantAccessibilityTapped() {
        PermissionsManager.shared.openAccessibilitySettings()
    }
}

// MARK: - Hotkey recorder field

/// Click to focus, then press a shortcut. Stores the captured key + modifiers.
final class HotkeyRecorderField: NSTextField {
    var onChange: ((UInt32, UInt32) -> Void)?
    private var keyCode: UInt32 = 0
    private var modifiers: UInt32 = 0
    private var recording = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        isEditable = false
        isSelectable = false
        alignment = .center
        focusRingType = .default
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        recording = true
        stringValue = "Press shortcut…"
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    func set(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        refreshTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let kc = UInt32(event.keyCode)

        // Ignore plain Escape (treat as cancel) and lone modifier presses.
        if kc == UInt32(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        let carbonMods = HotkeyRecorderField.carbonModifiers(from: event.modifierFlags)
        guard carbonMods != 0 else {
            // Require at least one modifier to avoid trapping plain keys.
            return
        }

        keyCode = kc
        modifiers = carbonMods
        refreshTitle()
        onChange?(keyCode, modifiers)
        window?.makeFirstResponder(nil)
    }

    private func refreshTitle() {
        if keyCode == 0 {
            stringValue = "Click to set"
            return
        }
        stringValue = HotkeyRecorderField.describe(keyCode: keyCode, modifiers: modifiers)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyCodeName(keyCode)
        return s
    }

    private static func keyCodeName(_ kc: UInt32) -> String {
        switch Int(kc) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"; case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"; case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"; case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"; case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"; case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"; case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"
        case kVK_F3: return "F3"; case kVK_F4: return "F4"
        case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"
        case kVK_F9: return "F9"; case kVK_F10: return "F10"
        case kVK_F11: return "F11"; case kVK_F12: return "F12"
        default: return "Key \(kc)"
        }
    }
}
