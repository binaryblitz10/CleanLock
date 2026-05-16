import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// MARK: - Settings View Model

final class SettingsViewModel: ObservableObject {
    @Published var launchMode: Preferences.LaunchMode
    @Published var autoUnlockSeconds: Int
    @Published var hotkeyKeyCode: UInt32
    @Published var hotkeyModifiers: UInt32
    @Published var launchAtLogin: Bool
    @Published var hasAccessibility: Bool

    private let prefs = Preferences.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.launchMode = prefs.launchMode
        self.autoUnlockSeconds = prefs.autoUnlockSeconds
        self.hotkeyKeyCode = prefs.hotkey.keyCode
        self.hotkeyModifiers = prefs.hotkey.carbonModifiers
        self.launchAtLogin = prefs.launchAtLogin
        self.hasAccessibility = PermissionsManager.shared.hasAccessibility()

        // Write changes through to Preferences immediately.
        $launchMode
            .dropFirst()
            .sink { [weak self] mode in
                Preferences.shared.launchMode = mode
                if mode == .launcher {
                    self?.launchAtLogin = false
                    Preferences.shared.launchAtLogin = false
                }
            }
            .store(in: &cancellables)

        $autoUnlockSeconds
            .dropFirst()
            .sink { Preferences.shared.autoUnlockSeconds = $0 }
            .store(in: &cancellables)

        Publishers.CombineLatest($hotkeyKeyCode, $hotkeyModifiers)
            .dropFirst()
            .sink { keyCode, mods in
                Preferences.shared.hotkey = .init(keyCode: keyCode, carbonModifiers: mods)
                HotkeyManager.shared.registerStoredHotkey()
            }
            .store(in: &cancellables)

        $launchAtLogin
            .dropFirst()
            .sink { Preferences.shared.launchAtLogin = $0 }
            .store(in: &cancellables)
    }

    func refreshAccessibility() {
        hasAccessibility = PermissionsManager.shared.hasAccessibility()
    }
}

// MARK: - SwiftUI Settings View

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private static let timeoutOptions: [(label: String, seconds: Int)] = [
        ("Disabled", 0),
        ("1 minute", 60),
        ("3 minutes", 180),
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("30 minutes", 1800),
    ]

    var body: some View {
        Form {
            Section {
                Picker("", selection: $model.launchMode) {
                    Text(Preferences.LaunchMode.persistent.displayName)
                        .tag(Preferences.LaunchMode.persistent)
                    Text(Preferences.LaunchMode.launcher.displayName)
                        .tag(Preferences.LaunchMode.launcher)
                }
                .pickerStyle(.radioGroup)

                Text(launchModeSubtitle)
                    .font(.system(size: NSFont.smallSystemFontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Startup Behavior")
            }

            Section {
                Picker("Auto-unlock after", selection: $model.autoUnlockSeconds) {
                    ForEach(Self.timeoutOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Activation shortcut")
                    HotkeyRecorderView(keyCode: $model.hotkeyKeyCode, modifiers: $model.hotkeyModifiers)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Accessibility")
                    Spacer()
                    if model.hasAccessibility {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") {
                            PermissionsManager.shared.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .disabled(model.launchMode == .launcher)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440)
    }

    private var launchModeSubtitle: String {
        switch model.launchMode {
        case .persistent:
            return "CleanLock stays in the menu bar. Activate anytime with the shortcut."
        case .launcher:
            return "Show the launcher window on startup and after each cleaning session."
        }
    }
}

// MARK: - Hotkey Recorder (SwiftUI bridge)

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.onChange = { kc, mods in
            keyCode = kc
            modifiers = mods
        }
        return field
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.set(keyCode: keyCode, modifiers: modifiers)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HotkeyRecorderField, context: Context) -> CGSize {
        CGSize(width: 180, height: 22)
    }
}

// MARK: - AppKit Hotkey Recorder Field

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
        font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        focusRingType = .default
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

        if kc == UInt32(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        let carbonMods = HotkeyRecorderField.carbonModifiers(from: event.modifierFlags)
        guard carbonMods != 0 else {
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
        if modifiers & UInt32(controlKey) != 0 { s += "^" }
        if modifiers & UInt32(optionKey)  != 0 { s += "\u{2325}" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "\u{21E7}" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "\u{2318}" }
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

// MARK: - Settings Window Controller

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var model: SettingsViewModel?

    convenience init() {
        let model = SettingsViewModel()
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CleanLock Settings"
        window.isReleasedWhenClosed = false
        window.center()

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .windowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView = visualEffect

        visualEffect.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        self.init(window: window)
        self.model = model
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        model?.refreshAccessibility()
    }
}
