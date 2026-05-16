import AppKit
import CoreGraphics

/// Fullscreen overlay shown while cleaning mode is active.
/// Uses a dark translucent material for a refined macOS 26 aesthetic.
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
        w.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0)
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

/// Borderless window that refuses to give up first responder.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Renders centered status text on a near-black background.
private final class OverlayContentView: NSView {
    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    private let titleField: NSTextField
    private let subtitleField: NSTextField

    override init(frame frameRect: NSRect) {
        titleField = OverlayContentView.makeLabel()
        subtitleField = OverlayContentView.makeLabel()
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0).cgColor

        titleField.font = .systemFont(ofSize: 36, weight: .semibold)
        titleField.alphaValue = 0.95
        titleField.stringValue = "Cleaning Mode"
        titleField.alignment = .center

        let subtitleStyle = NSMutableParagraphStyle()
        subtitleStyle.alignment = .center
        subtitleStyle.lineSpacing = 8

        subtitleField.attributedStringValue = NSAttributedString(
            string: "Your keyboard and mouse are disabled.\nHold both \u{2318} keys for 3 seconds to exit.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.65),
                .paragraphStyle: subtitleStyle,
            ]
        )
        subtitleField.alignment = .center
        subtitleField.maximumNumberOfLines = 2

        titleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24),
            subtitleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 20),
            subtitleField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.75),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

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
