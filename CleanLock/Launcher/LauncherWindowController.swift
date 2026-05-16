import AppKit
import SwiftUI

/// Minimal launcher window hosting a SwiftUI view.
/// Shown on app launch (launcher mode) and after cleaning mode exits.
final class LauncherWindowController: NSWindowController {

    var onStartCleaning: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSettings: (() -> Void)?

    private let hostingView: NSHostingView<LauncherView>

    init() {
        let launcherView = LauncherView()
        self.hostingView = NSHostingView(rootView: launcherView)
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CleanLock"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal

        // Apply window background material for Liquid Glass aesthetic.
        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.material = .windowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        window.contentView!.addSubview(visualEffect, positioned: .below, relativeTo: nil)

        window.contentView!.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])

        super.init(window: window)

        // Wire callbacks after self is available.
        hostingView.rootView = LauncherView(
            onStartCleaning: { [weak self] in
                self?.onStartCleaning?()
            },
            onQuit: { [weak self] in
                self?.onQuit?()
            },
            onSettings: { [weak self] in
                self?.onSettings?()
            }
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Center on screen and bring forward.
    func showLauncher() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideLauncher() {
        window?.orderOut(nil)
    }
}

// MARK: - SwiftUI Launcher View

private struct LauncherView: View {
    var onStartCleaning: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSettings: (() -> Void)?

    init(
        onStartCleaning: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        onSettings: (() -> Void)? = nil
    ) {
        self.onStartCleaning = onStartCleaning
        self.onQuit = onQuit
        self.onSettings = onSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Settings gear — top trailing corner.
            HStack {
                Spacer()
                Button(action: { onSettings?() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .padding(.trailing, 16)
                .padding(.top, 8)
            }

            Spacer()

            // Primary CTA — centered.
            Button(action: { onStartCleaning?() }) {
                Text("Start Cleaning")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(minWidth: 148)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])

            Spacer()

            // Quit — bottom trailing.
            HStack {
                Spacer()
                Button("Quit App") {
                    onQuit?()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 420, height: 280)
    }
}
