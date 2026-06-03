import AppKit
import CoreGraphics

/// Fullscreen overlay shown while cleaning mode is active.
/// Uses a near-black warm gray for a refined, non-developer-dark-mode look.
final class OverlayWindowController {
    private var window: NSWindow?
    private var previousPresentationOptions: NSApplication.PresentationOptions?

    func show() {
        precondition(Thread.isMainThread)
        guard window == nil else { return }

        let screen = OverlayWindowController.builtInScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen else { return }

        let w = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        w.isOpaque = true
        w.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1.0)
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.acceptsMouseMovedEvents = false
        w.hidesOnDeactivate = false

        let view = OverlayContentView(frame: screen.frame)
        w.contentView = view

        previousPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableAppleMenu,
        ]

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        window = w
    }

    func hide() {
        precondition(Thread.isMainThread)
        if let opts = previousPresentationOptions {
            NSApp.presentationOptions = opts
            previousPresentationOptions = nil
        } else {
            NSApp.presentationOptions = []
        }
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }

    func updateAutoUnlockCountdown(seconds: Int) {
        (window?.contentView as? OverlayContentView)?.setCountdown(seconds)
    }

    private static func builtInScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            if CGDisplayIsBuiltin(displayID) != 0 {
                return screen
            }
        }
        return nil
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OverlayContentView: NSView {
    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let hintField: NSTextField
    private let countdownField: NSTextField

    override init(frame frameRect: NSRect) {
        titleField = OverlayContentView.makeLabel()
        subtitleField = OverlayContentView.makeLabel()
        hintField = OverlayContentView.makeLabel()
        countdownField = OverlayContentView.makeLabel()
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1.0).cgColor

        titleField.font = .systemFont(ofSize: 28, weight: .semibold)
        titleField.alphaValue = 0.9
        titleField.stringValue = "Cleaning Mode"
        titleField.alignment = .center

        let subtitleStyle = NSMutableParagraphStyle()
        subtitleStyle.alignment = .center
        subtitleStyle.lineSpacing = 6

        subtitleField.attributedStringValue = NSAttributedString(
            string: "Your keyboard and mouse are disabled.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.55),
                .paragraphStyle: subtitleStyle,
            ]
        )

        let hintStyle = NSMutableParagraphStyle()
        hintStyle.alignment = .center

        hintField.attributedStringValue = NSAttributedString(
            string: "Hold both \u{2318} keys for 3 seconds to exit",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.35),
                .paragraphStyle: hintStyle,
            ]
        )
        hintField.translatesAutoresizingMaskIntoConstraints = false

        let settingsHintField = OverlayContentView.makeLabel()
        settingsHintField.attributedStringValue = NSAttributedString(
            string: "Hold both \u{2325} keys for 3 seconds to open settings",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.35),
                .paragraphStyle: hintStyle,
            ]
        )
        settingsHintField.translatesAutoresizingMaskIntoConstraints = false

        countdownField.font = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        countdownField.alphaValue = 0.45
        countdownField.alignment = .center
        countdownField.isHidden = true
        countdownField.translatesAutoresizingMaskIntoConstraints = false

        titleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleField)
        addSubview(subtitleField)
        addSubview(hintField)
        addSubview(settingsHintField)
        addSubview(countdownField)

        NSLayoutConstraint.activate([
            titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30),

            subtitleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),

            hintField.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintField.topAnchor.constraint(equalTo: subtitleField.bottomAnchor, constant: 6),

            settingsHintField.centerXAnchor.constraint(equalTo: centerXAnchor),
            settingsHintField.topAnchor.constraint(equalTo: hintField.bottomAnchor, constant: 4),

            countdownField.centerXAnchor.constraint(equalTo: centerXAnchor),
            countdownField.topAnchor.constraint(equalTo: settingsHintField.bottomAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    fileprivate func setCountdown(_ seconds: Int) {
        if seconds > 0 {
            let minutes = seconds / 60
            let secs = seconds % 60
            countdownField.stringValue = String(format: "%02d:%02d", minutes, secs)
            countdownField.isHidden = false
        } else {
            countdownField.isHidden = true
        }
    }

    private static func makeLabel() -> NSTextField {
        let f = NSTextField(labelWithString: "")
        f.isBezeled = false
        f.isEditable = false
        f.isSelectable = false
        f.drawsBackground = false
        f.textColor = .white
        f.backgroundColor = .clear
        return f
    }
}
