import AppKit
import SwiftUI

/// Minimal launcher window — compact, balanced, native utility feel.
final class LauncherWindowController: NSWindowController {

    var onStartCleaning: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSettings: (() -> Void)?

    private let hostingView: NSHostingView<LauncherView>

    init() {
        let view = LauncherView()
        hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 210)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CleanLock"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .normal

        let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentRect.size))
        visualEffect.material = .windowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(visualEffect, positioned: .below, relativeTo: nil)

        window.contentView!.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])

        super.init(window: window)

        hostingView.rootView = LauncherView(
            onStartCleaning: { [weak self] in self?.onStartCleaning?() },
            onQuit: { [weak self] in self?.onQuit?() },
            onSettings: { [weak self] in self?.onSettings?() }
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    func showLauncher() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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

    var body: some View {
        VStack(spacing: 0) {
            // ── Content area ──
            VStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(.secondary)

                Text("CleanLock")
                    .font(.system(size: 14, weight: .semibold))

                Text("Temporarily disable your keyboard and\n" +
                     "trackpad so you can safely clean them.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.top, 20)

            Spacer(minLength: 12)

            // ── Primary action ──
            Button(action: { onStartCleaning?() }) {
                Text("Start Cleaning")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer(minLength: 10)

            // ── Separator ──
            Rectangle()
                .fill(.separator)
                .frame(height: 1)

            // ── Bottom action row ──
            HStack(spacing: 0) {
                Button("Settings…") { onSettings?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") { onQuit?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 380, height: 210)
    }
}
