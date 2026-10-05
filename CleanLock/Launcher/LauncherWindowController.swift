import AppKit
import SwiftUI

/// Minimal launcher window — compact, balanced, with Liquid Glass aesthetics.
final class LauncherWindowController: NSWindowController {
    var onStartCleaning: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSettings: (() -> Void)?

    private let hostingView: NSHostingView<LauncherView>

    init() {
        let view = LauncherView()
        hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 220)
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

        if #available(macOS 26, *) {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = hostingView
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor

            let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentRect.size))
            visualEffect.material = .sidebar
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.autoresizingMask = [.width, .height]
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 12
            visualEffect.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            window.contentView!.addSubview(visualEffect, positioned: .below, relativeTo: nil)

            window.contentView!.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            ])
        }

        super.init(window: window)

        hostingView.rootView = LauncherView(
            onStartCleaning: { [weak self] in self?.onStartCleaning?() },
            onQuit: { [weak self] in self?.onQuit?() },
            onSettings: { [weak self] in self?.onSettings?() }
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

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
        if #available(macOS 26, *) {
            glassContent
        } else {
            fallbackContent
        }
    }

    // MARK: - macOS 26+ Liquid Glass

    @available(macOS 26, *)
    private var glassContent: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 0) {
                mainContentArea
                glassBottomBar
            }
        }
        .frame(width: 380, height: 220)
    }

    @available(macOS 26, *)
    private var glassBottomBar: some View {
        HStack(spacing: 0) {
            Button("Settings") { onSettings?() }
                .buttonStyle(.glass)
                .controlSize(.small)

            Spacer()

            Button("Quit") { onQuit?() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .glassEffect(.clear, in: .rect(cornerRadius: 8))
    }

    // MARK: - macOS 15 Fallback

    private var fallbackContent: some View {
        VStack(spacing: 0) {
            mainContentArea

            // ── Separator ──
            Rectangle()
                .fill(.separator)
                .frame(height: 1)

            // ── Bottom action row ──
            HStack(spacing: 0) {
                Button("Settings") { onSettings?() }
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

    // MARK: - Shared Content

    @ViewBuilder
    private var mainContentArea: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .glassIconStyle()

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

        primaryButton

        Spacer(minLength: 10)
    }

    private var primaryButton: some View {
        Group {
            if #available(macOS 26, *) {
                Button("Start Cleaning") { onStartCleaning?() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                    .font(.system(size: 13, weight: .medium))
            } else {
                Button(action: { onStartCleaning?() }) {
                    Text("Start Cleaning")
                        .font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }
}

// MARK: - Icon styling helper

private extension View {
    @ViewBuilder
    func glassIconStyle() -> some View {
        if #available(macOS 26, *) {
            self
                .padding(12)
                .glassEffect(.clear.interactive(false), in: .circle)
        } else {
            self
        }
    }
}
