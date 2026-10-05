import AppKit
import CoreGraphics

/// Fullscreen overlay shown while cleaning mode is active.
/// Uses a near-black warm gray for a refined, non-developer-dark-mode look.
final class OverlayWindowController {
    private var window: NSWindow?
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var gestureMonitor: Any?
    private var spaceChangeObserver: NSObjectProtocol?

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

        startGestureMonitoring()
        startSpaceChangeMonitoring()
    }

    func hide() {
        precondition(Thread.isMainThread)
        stopGestureMonitoring()
        stopSpaceChangeMonitoring()

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

    // MARK: - Gesture monitoring

    /// Registers a local NSEvent monitor that absorbs trackpad gesture events
    /// before they reach the NSView responder chain. This catches app-level
    /// gestures (3-finger swipe, pinch zoom, rotation, Force Touch) that may
    /// briefly arrive while the CGEvent tap is being re-enabled by the system.
    ///
    /// System-level gestures handled by the Dock (4-finger swipe for Spaces,
    /// 3-finger Mission Control) bypass this monitor entirely — see
    /// `startSpaceChangeMonitoring()` for the secondary defense against those.
    private func startGestureMonitoring() {
        stopGestureMonitoring()

        let mask: NSEvent.EventTypeMask = [
            .gesture, .magnify, .swipe, .rotate,
            .beginGesture, .endGesture,
            .pressure,
        ]

        let monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { _ in
            return nil
        }
        gestureMonitor = monitor
    }

    private func stopGestureMonitoring() {
        if let monitor = gestureMonitor {
            NSEvent.removeMonitor(monitor)
            gestureMonitor = nil
        }
    }

    // MARK: - Space change defense

    /// Observes `NSWorkspace.activeSpaceDidChangeNotification` and immediately
    /// re-asserts the overlay as the key, frontmost window. This mitigates
    /// system-level trackpad gestures (4-finger swipe for Spaces, 3-finger
    /// Mission Control) which the Dock handles through the MultitouchSupport
    /// framework at a level beneath the CGEvent HID event tap.
    ///
    /// When the Dock switches Spaces in response to a gesture, the overlay
    /// follows because of `.canJoinAllSpaces` in its collection behavior.
    /// Re-ordering it to front ensures it stays dominant and the user never
    /// sees content from the destination space.
    private func startSpaceChangeMonitoring() {
        stopSpaceChangeMonitoring()
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Re-assert overlay dominance after a space transition.
            // The overlay's canJoinAllSpaces means it's already on the new
            // space; ordering it front ensures nothing else layers above it.
            self?.window?.orderFrontRegardless()
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func stopSpaceChangeMonitoring() {
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            spaceChangeObserver = nil
        }
    }

    deinit {
        stopGestureMonitoring()
        stopSpaceChangeMonitoring()
    }

    func updateAutoUnlockCountdown(seconds: Int) {
        (window?.contentView as? OverlayContentView)?.setCountdown(seconds)
    }

    func updateHoldHint(isHolding: Bool, secondsRemaining: Int) {
        (window?.contentView as? OverlayContentView)?.setHoldHint(isHolding: isHolding, secondsRemaining: secondsRemaining)
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
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class OverlayContentView: NSView {
    override var isFlipped: Bool {
        false
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    private let titleField: NSTextField
    private let subtitleField: NSTextField
    private let hintField: NSTextField
    private let settingsHintField: NSTextField
    private let countdownField: NSTextField
    private let holdHintField: NSTextField

    override init(frame frameRect: NSRect) {
        titleField = OverlayContentView.makeLabel()
        subtitleField = OverlayContentView.makeLabel()
        hintField = OverlayContentView.makeLabel()
        settingsHintField = OverlayContentView.makeLabel()
        countdownField = OverlayContentView.makeLabel()
        holdHintField = OverlayContentView.makeLabel()
        super.init(frame: frameRect)

        wantsLayer = true
        allowedTouchTypes = [.indirect, .direct]

        // Gradient background with refined dark palette
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0).cgColor,
            NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0).cgColor,
            NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1.0).cgColor,
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        layer?.addSublayer(gradient)
        // Store gradient reference for frame updates
        gradientFrame = gradient

        // Title with refined weight and tracking
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center

        titleField.attributedStringValue = NSAttributedString(
            string: "Cleaning Mode",
            attributes: [
                .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.92),
                .kern: 1.5,
                .paragraphStyle: titleStyle,
            ]
        )
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let subtitleStyle = NSMutableParagraphStyle()
        subtitleStyle.alignment = .center
        subtitleStyle.lineSpacing = 7

        subtitleField.attributedStringValue = NSAttributedString(
            string: "Your keyboard and mouse are disabled.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.55),
                .paragraphStyle: subtitleStyle,
            ]
        )
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        let hintStyle = NSMutableParagraphStyle()
        hintStyle.alignment = .center
        hintStyle.lineSpacing = 5

        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.30),
            .paragraphStyle: hintStyle,
        ]

        hintField.attributedStringValue = NSAttributedString(
            string: "Hold both \u{2318} keys for 3 seconds to exit",
            attributes: hintAttributes
        )
        hintField.translatesAutoresizingMaskIntoConstraints = false

        settingsHintField.attributedStringValue = NSAttributedString(
            string: "Hold both \u{2325} keys for 3 seconds to open settings",
            attributes: hintAttributes
        )
        settingsHintField.translatesAutoresizingMaskIntoConstraints = false

        // Countdown with refined styling
        let countdownStyle = NSMutableParagraphStyle()
        countdownStyle.alignment = .center

        countdownField.attributedStringValue = NSAttributedString(
            string: "00:00",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .ultraLight),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.06),
                .kern: 8.0,
                .paragraphStyle: countdownStyle,
            ]
        )
        countdownField.isHidden = true
        countdownField.translatesAutoresizingMaskIntoConstraints = false

        let holdAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.45),
            .paragraphStyle: hintStyle,
        ]
        holdHintField.attributedStringValue = NSAttributedString(
            string: "",
            attributes: holdAttributes
        )
        holdHintField.isHidden = true
        holdHintField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleField)
        addSubview(subtitleField)
        addSubview(hintField)
        addSubview(settingsHintField)
        addSubview(countdownField)
        addSubview(holdHintField)

        NSLayoutConstraint.activate([
            titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -36),

            subtitleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 14),

            hintField.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintField.topAnchor.constraint(equalTo: subtitleField.bottomAnchor, constant: 8),

            settingsHintField.centerXAnchor.constraint(equalTo: centerXAnchor),
            settingsHintField.topAnchor.constraint(equalTo: hintField.bottomAnchor, constant: 4),

            countdownField.centerXAnchor.constraint(equalTo: centerXAnchor),
            countdownField.topAnchor.constraint(equalTo: settingsHintField.bottomAnchor, constant: 16),

            holdHintField.centerXAnchor.constraint(equalTo: centerXAnchor),
            holdHintField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -70),
        ])
    }

    /// Track gradient layer for layout updates
    private var gradientFrame: CAGradientLayer?

    override func layout() {
        super.layout()
        gradientFrame?.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    fileprivate func setCountdown(_ seconds: Int) {
        if seconds > 0 {
            let minutes = seconds / 60
            let secs = seconds % 60
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            countdownField.attributedStringValue = NSAttributedString(
                string: String(format: "%02d:%02d", minutes, secs),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .ultraLight),
                    .foregroundColor: NSColor(white: 1.0, alpha: 0.06),
                    .kern: 8.0,
                    .paragraphStyle: style,
                ]
            )
            countdownField.isHidden = false
        } else {
            countdownField.isHidden = true
        }
    }

    fileprivate func setHoldHint(isHolding: Bool, secondsRemaining: Int) {
        if isHolding, secondsRemaining > 0 {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let suffix = secondsRemaining == 1 ? "" : "s"
            holdHintField.attributedStringValue = NSAttributedString(
                string: "Keep holding for \(secondsRemaining) second\(suffix)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: NSColor(white: 1.0, alpha: 0.45),
                    .paragraphStyle: style,
                ]
            )
            holdHintField.isHidden = false
        } else {
            holdHintField.isHidden = true
        }
    }

    // MARK: - Gesture absorption

    /// Override all gesture/touch responder methods so they are absorbed by the
    /// overlay view rather than propagating up the responder chain or being
    /// handled by the WindowServer/Dock default behavior.
    ///
    /// Multi-touch gestures (4-finger swipe for Spaces, 3-finger swipe for
    /// navigation, pinch for Launchpad, rotate) and force-click pressure
    /// changes are recognized by the WindowServer/Dock/multitouch driver at a
    /// layer that runs independently of our HID event tap. The only way to stop
    /// them from triggering system actions is to absorb them here.
    ///
    /// NOTE: The trackpad's haptic "click" feedback is generated by the Taptic
    /// Engine firmware when the force sensor detects pressure — this happens
    /// at the hardware/driver level below any software and cannot be suppressed
    /// programmatically. The CGEvent tap does consume the resulting mouse-down
    /// events so they never reach any application, but the haptic click itself
    /// is unavoidable.
    override func pressureChange(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func beginGesture(with event: NSEvent) {}
    override func endGesture(with event: NSEvent) {}
    override func touchesBegan(with event: NSEvent) {}
    override func touchesMoved(with event: NSEvent) {}
    override func touchesEnded(with event: NSEvent) {}
    override func touchesCancelled(with event: NSEvent) {}

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
