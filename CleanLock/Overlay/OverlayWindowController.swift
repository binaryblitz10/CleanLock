import AppKit
import CoreGraphics

/// Fullscreen black overlay shown on the built-in display while cleaning mode
/// is active. AppKit, not SwiftUI — we want predictable lifecycle.
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
        w.backgroundColor = .black
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.acceptsMouseMovedEvents = false
        w.hidesOnDeactivate = false

        let view = OverlayContentView(frame: screen.frame)
        w.contentView = view

        // Documented constraints:
        //   .disableForceQuit          requires .hideMenuBar
        //   .disableSessionTermination requires .disableForceQuit
        // The subset below is the kiosk-safe combination that validates
        // cleanly on every macOS 13+ build we've tested.
        previousPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableAppleMenu,
        ]

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

    // MARK: - Built-in display detection

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

/// Renders centered "Cleaning Mode" + subtitle, white on black.
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
        layer?.backgroundColor = NSColor.black.cgColor

        titleField.font = NSFont.systemFont(ofSize: 48, weight: .medium)
        titleField.alphaValue = 1.0
        titleField.stringValue = "Cleaning Mode"
        titleField.alignment = .center

        let subtitleStyle = NSMutableParagraphStyle()
        subtitleStyle.alignment = .center
        subtitleStyle.lineSpacing = 6

        let subtitleString = "Your keyboard and mouse are disabled.\nPress the Command (⌘) key 6 times to exit."
        subtitleField.attributedStringValue = NSAttributedString(
            string: subtitleString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.75),
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
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -28),
            subtitleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 18),
            subtitleField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
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
