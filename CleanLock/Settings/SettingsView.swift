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
        launchMode = prefs.launchMode
        autoUnlockSeconds = prefs.autoUnlockSeconds
        hotkeyKeyCode = prefs.hotkey.keyCode
        hotkeyModifiers = prefs.hotkey.carbonModifiers
        launchAtLogin = prefs.launchAtLogin
        hasAccessibility = PermissionsManager.shared.hasAccessibility()

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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // ── Startup Behavior ──
                sectionHeader(
                    title: "Startup Behavior",
                    subtitle: "Choose how CleanLock starts when you log in."
                )

                HStack(spacing: 12) {
                    ModeCard(
                        title: "Menu Bar",
                        description: "Runs in the menu bar. Activate anytime with the shortcut.",
                        iconName: "menubar.rectangle",
                        isSelected: model.launchMode == .persistent,
                        action: { model.launchMode = .persistent }
                    )
                    ModeCard(
                        title: "Launcher",
                        description: "Opens the app window at login. You can close it while it runs in the background.",
                        iconName: "macwindow",
                        isSelected: model.launchMode == .launcher,
                        action: { model.launchMode = .launcher }
                    )
                }
                .padding(.horizontal, 4)

                // ── Rows ──
                VStack(spacing: 0) {
                    rowItem(label: "Activation Shortcut") {
                        HotkeyRecorderView(
                            keyCode: $model.hotkeyKeyCode,
                            modifiers: $model.hotkeyModifiers
                        )
                        .frame(width: 140, height: 30)
                    }

                    Divider().padding(.vertical, 10)

                    rowItem(label: "Auto Unlock") {
                        Picker("", selection: $model.autoUnlockSeconds) {
                            ForEach(timeoutOptions, id: \.seconds) { opt in
                                Text(opt.label).tag(opt.seconds)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    Divider().padding(.vertical, 10)

                    rowItem(label: "Launch at Login") {
                        Toggle("", isOn: $model.launchAtLogin)
                            .labelsHidden()
                            .disabled(model.launchMode == .launcher)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }

                // ── Permissions ──
                sectionHeader(title: "Permissions", subtitle: nil)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accessibility")
                            .font(.system(size: 13, weight: .regular))
                        Text("Required for keyboard and mouse control.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if model.hasAccessibility {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access\u{2026}") {
                            PermissionsManager.shared.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 480)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rowItem<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular))
            Spacer()
            trailing()
        }
    }
}

// MARK: - Mode Selection Card

private struct ModeCard: View {
    let title: String
    let description: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon area
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconBackgroundColor)
                        .frame(height: 108)

                    Image(systemName: iconName)
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
                .overlay(alignment: .topTrailing) {
                    selectionIndicator
                        .padding(10)
                }

                // Title + description
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 13)
                .padding(.top, 11)
                .padding(.bottom, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardBackgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: isSelected ? 1.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Color.clear : Color.secondary.opacity(0.5),
                    lineWidth: 1.5
                )
                .background(
                    Circle().fill(isSelected ? Color.accentColor : Color.clear)
                )
                .frame(width: 20, height: 20)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var iconBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.85)
        }
        return Color(nsColor: .quaternaryLabelColor).opacity(isHovering ? 0.18 : 0.12)
    }

    private var cardBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return Color(nsColor: .quaternaryLabelColor).opacity(isHovering ? 0.12 : 0.06)
    }

    private var cardBorderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.6)
        }
        return Color(nsColor: .separatorColor).opacity(0.6)
    }
}

// MARK: - Hotkey Recorder (SwiftUI bridge)

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context _: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.onChange = { kc, mods in
            keyCode = kc
            modifiers = mods
        }
        return field
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context _: Context) {
        nsView.set(keyCode: keyCode, modifiers: modifiers)
    }

    func sizeThatFits(_: ProposedViewSize, nsView _: HotkeyRecorderField, context _: Context) -> CGSize {
        CGSize(width: 140, height: 30)
    }
}

// MARK: - AppKit Hotkey Recorder Field

final class HotkeyRecorderField: NSView {
    var onChange: ((UInt32, UInt32) -> Void)?

    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0
    private var recording = false
    private var hasShortcut: Bool {
        currentKeyCode != 0
    }

    // Subviews
    private let backgroundView = NSView()
    private let textField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.alignment = .center
        field.textColor = .labelColor
        field.backgroundColor = .clear
        field.isBezeled = false
        field.drawsBackground = false
        field.lineBreakMode = .byClipping
        return field
    }()

    private let clearButton: NSButton = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.wantsLayer = true
        button.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Clear shortcut")
        button.image?.isTemplate = true
        button.alphaValue = 0
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        return button
    }()

    // Tracking
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    // Constants
    private let cornerRadius: CGFloat = 8
    private let clearButtonSize: CGFloat = 20
    private let clearButtonTrailingMargin: CGFloat = 10
    private let horizontalTextPadding: CGFloat = 14

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 30))

        // Background
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = cornerRadius
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.backgroundColor = recorderBackgroundColor
        backgroundView.layer?.borderColor = NSColor.separatorColor.cgColor
        backgroundView.layer?.borderWidth = 0.5
        addSubview(backgroundView)

        // Text field
        textField.alignment = .center
        addSubview(textField)

        // Clear button
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        addSubview(clearButton)

        refreshDisplay()
        updateTrackingAreas()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        if let area = trackingArea {
            removeTrackingArea(area)
        }
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with _: NSEvent) {
        isHovering = true
        updateHoverState()
    }

    override func mouseExited(with _: NSEvent) {
        isHovering = false
        updateHoverState()
    }

    // MARK: - Responder

    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hasShortcut, clearButton.frame.contains(point) {
            return // Let the button handle it
        }
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        recording = true
        textField.attributedStringValue = Self.placeholderString("Press shortcut\u{2026}")
        updateBackgroundStyle(isActive: true)
        needsLayout = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refreshDisplay()
        updateBackgroundStyle(isActive: false)
        return super.resignFirstResponder()
    }

    // MARK: - Public API

    func set(keyCode: UInt32, modifiers: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        refreshDisplay()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let kc = UInt32(event.keyCode)

        if kc == UInt32(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        let carbonMods = Self.carbonModifiers(from: event.modifierFlags)
        guard carbonMods != 0 else { return }

        currentKeyCode = kc
        currentModifiers = carbonMods
        refreshDisplay()
        onChange?(currentKeyCode, currentModifiers)
        window?.makeFirstResponder(nil)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let rect = bounds

        backgroundView.frame = rect

        // Clear button — centered vertically
        let cbY = (rect.height - clearButtonSize) / 2
        clearButton.frame = NSRect(
            x: rect.maxX - clearButtonSize - clearButtonTrailingMargin,
            y: cbY,
            width: clearButtonSize,
            height: clearButtonSize
        )

        // Text field — horizontally padded, vertically centered
        let textRight = hasShortcut ? clearButton.frame.minX - 6 : rect.maxX - horizontalTextPadding
        let textWidth = max(0, textRight - (rect.minX + horizontalTextPadding))
        let intrinsicH = textField.intrinsicContentSize.height
        let textY = (rect.height - intrinsicH) / 2
        textField.frame = NSRect(
            x: rect.minX + horizontalTextPadding,
            y: textY,
            width: textWidth,
            height: intrinsicH
        )

        updateTrackingAreas()
    }

    // MARK: - Private

    @objc private func clearShortcut() {
        currentKeyCode = 0
        currentModifiers = 0
        refreshDisplay()
        onChange?(0, 0)
    }

    private func refreshDisplay() {
        if hasShortcut {
            let shortcutText = Self.describe(keyCode: currentKeyCode, modifiers: currentModifiers)
            textField.attributedStringValue = Self.shortcutString(shortcutText)
            clearButton.alphaValue = isHovering ? 0.8 : 0.5
        } else {
            textField.attributedStringValue = Self.placeholderString("Click to set")
            clearButton.alphaValue = 0
        }
        needsLayout = true
    }

    private static func shortcutString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .kern: 2.0,
            .foregroundColor: NSColor.labelColor,
        ])
    }

    private static func placeholderString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private func updateHoverState() {
        if hasShortcut {
            clearButton.alphaValue = isHovering ? 0.8 : 0.5
        }
        if !recording {
            backgroundView.layer?.backgroundColor = isHovering ? recorderHoverBackgroundColor : recorderBackgroundColor
        }
    }

    private func updateBackgroundStyle(isActive: Bool) {
        backgroundView.layer?.backgroundColor = isActive ? recorderActiveBackgroundColor : recorderBackgroundColor
    }

    // MARK: - Colors (appearance-aware)

    private var recorderBackgroundColor: CGColor {
        if effectiveAppearance.isDarkMode {
            return NSColor(white: 0.15, alpha: 1.0).cgColor
        }
        return NSColor(white: 0.98, alpha: 1.0).cgColor
    }

    private var recorderHoverBackgroundColor: CGColor {
        if effectiveAppearance.isDarkMode {
            return NSColor(white: 0.18, alpha: 1.0).cgColor
        }
        return NSColor(white: 0.95, alpha: 1.0).cgColor
    }

    private var recorderActiveBackgroundColor: CGColor {
        if effectiveAppearance.isDarkMode {
            return NSColor(white: 0.20, alpha: 1.0).cgColor
        }
        return NSColor(white: 0.93, alpha: 1.0).cgColor
    }

    // MARK: - Static Helpers

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(keyCodeName(keyCode))
        return parts.joined(separator: "")
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

// MARK: - Dark mode helper

private extension NSAppearance {
    var isDarkMode: Bool {
        if #available(macOS 10.14, *) {
            return name == .darkAqua || name == .vibrantDark
        }
        return false
    }
}

// MARK: - Settings Window Controller

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var model: SettingsViewModel?

    convenience init() {
        let model = SettingsViewModel()
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        // Calculate ideal height from content
        let contentHeight: CGFloat = 540

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: contentHeight),
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

    func windowWillClose(_: Notification) {
        model?.refreshAccessibility()
    }
}
