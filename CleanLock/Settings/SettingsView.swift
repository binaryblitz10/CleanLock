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

    private var cancellables = Set<AnyCancellable>()

    init() {
        let prefs = Preferences.shared
        self.launchMode = prefs.launchMode
        self.autoUnlockSeconds = prefs.autoUnlockSeconds
        self.hotkeyKeyCode = prefs.hotkey.keyCode
        self.hotkeyModifiers = prefs.hotkey.carbonModifiers
        self.launchAtLogin = prefs.launchAtLogin
        self.hasAccessibility = PermissionsManager.shared.hasAccessibility()

        $launchMode
            .dropFirst()
            .sink { mode in
                Preferences.shared.launchMode = mode
                if mode == .launcher {
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

    private let timeoutOptions: [(label: String, seconds: Int)] = [
        ("Disabled", 0), ("1 minute", 60), ("3 minutes", 180),
        ("5 minutes", 300), ("10 minutes", 600), ("30 minutes", 1800),
    ]

    var body: some View {
        VStack(spacing: 14) {
            // ── General section ──
            sectionHeader("General")

            GroupBox {
                VStack(spacing: 10) {
                    // Startup Behavior
                    settingRow(leading: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Startup Behavior")
                                .font(.system(size: 12, weight: .medium))
                            Text(modeSubtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }, trailing: {
                        Picker("", selection: $model.launchMode) {
                            Text("Menu Bar").tag(Preferences.LaunchMode.persistent)
                            Text("Launcher").tag(Preferences.LaunchMode.launcher)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    })
                    .padding(.bottom, 2)

                    Divider()

                    // Activation Shortcut
                    settingRow(leading: {
                        Text("Activation Shortcut")
                            .font(.system(size: 12))
                    }, trailing: {
                        HotkeyRecorderView(
                            keyCode: $model.hotkeyKeyCode,
                            modifiers: $model.hotkeyModifiers
                        )
                    })

                    Divider()

                    // Auto Unlock
                    settingRow(leading: {
                        Text("Auto Unlock")
                            .font(.system(size: 12))
                    }, trailing: {
                        Picker("", selection: $model.autoUnlockSeconds) {
                            ForEach(timeoutOptions, id: \.seconds) { opt in
                                Text(opt.label).tag(opt.seconds)
                            }
                        }
                        .frame(width: 120)
                    })

                    Divider()

                    // Launch at Login
                    settingRow(leading: {
                        Text("Launch at Login")
                            .font(.system(size: 12))
                    }, trailing: {
                        Toggle("", isOn: $model.launchAtLogin)
                            .disabled(model.launchMode == .launcher)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    })
                }
                .padding(12)
            }
            .groupBoxStyle(CardGroupBoxStyle())

            // ── Permissions section ──
            sectionHeader("Permissions")

            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.system(size: 12, weight: .medium))
                        Text("Required for keyboard and mouse control")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if model.hasAccessibility {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") {
                            PermissionsManager.shared.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }
            .groupBoxStyle(CardGroupBoxStyle())
        }
        .padding(16)
        .frame(width: 400)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    private func settingRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            leading()
            Spacer()
            trailing()
        }
        .padding(.vertical, 1)
    }

    private var modeSubtitle: String {
        switch model.launchMode {
        case .persistent:
            return "Runs in the menu bar. Activate anytime with the shortcut."
        case .launcher:
            return "Shows a launcher window on startup and after cleaning."
        }
    }
}

// MARK: - Card GroupBox Style

private struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator, lineWidth: 0.5)
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
        CGSize(width: 150, height: 22)
    }
}

// MARK: - AppKit Hotkey Recorder Field

final class HotkeyRecorderField: NSTextField {
    var onChange: ((UInt32, UInt32) -> Void)?
    private var keyCode: UInt32 = 0
    private var modifiers: UInt32 = 0
    private var recording = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 22))
        isEditable = false
        isSelectable = false
        alignment = .center
        font = .monospacedSystemFont(ofSize: 12, weight: .regular)
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

        if kc == UInt32(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        let carbonMods = HotkeyRecorderField.carbonModifiers(from: event.modifierFlags)
        guard carbonMods != 0 else { return }

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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
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
