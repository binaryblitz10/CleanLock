import AppKit
import CoreGraphics

/// Hides the mouse cursor for the duration of cleaning mode.
///
/// Uses Quartz's `CGDisplayHideCursor` / `CGDisplayShowCursor`, which are
/// reference-counted — every hide must be paired with exactly one show. This
/// class enforces that invariant: `hide()` and `show()` are idempotent against
/// internal state, so callers can invoke them defensively from multiple
/// lifecycle paths without leaving the cursor stuck off.
///
/// A hardening timer periodically re-asserts the hide and disassociation calls
/// every 2 seconds while the cursor is hidden. macOS may override these
/// settings when a shielding-level window appears or when system UI activates;
/// the timer restores them.
///
/// IMPORTANT: `NSCursor.hide()` and `CGDisplayHideCursor()` are both
/// **ref-counted**. The hardening timer increments these ref counts every 2
/// seconds, so `show()` must drain them all by calling `unhide()`/
/// `CGDisplayShowCursor()` enough times to reach zero. The drain count of 30
/// covers up to ~60 seconds of cleaning mode — well beyond any practical
/// session and harmless to overshoot on macOS.
///
/// Crash safety: cursor visibility is owned by the WindowServer per-process
/// connection. When this process dies — for any reason — the WindowServer
/// drops our hide reference and the cursor reappears automatically. There is
/// no persistent system state to leak.
final class CursorHider {
    /// How many `unhide()` / `CGDisplayShowCursor()` calls to issue in `show()`
    /// to drain ref counts accumulated by the hardening timer. 30 covers up to
    /// ~60 s of cleaning mode with a 2-second timer interval.
    private static let drainCount = 30

    private var isHidden = false
    private var hardeningTimer: DispatchSourceTimer?

    func hide() {
        precondition(Thread.isMainThread)
        guard !isHidden else { return }

        applyHide()
        isHidden = true
        startHardening()
    }

    func show() {
        precondition(Thread.isMainThread)
        guard isHidden else { return }

        stopHardening()
        applyShow()
        isHidden = false
    }

    // MARK: - Private

    private func applyHide() {
        CGDisplayHideCursor(CGMainDisplayID())
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    private func applyShow() {
        CGAssociateMouseAndMouseCursorPosition(1)

        // Drain ref-counted hide calls accumulated by the hardening timer.
        for _ in 0..<Self.drainCount {
            NSCursor.unhide()
        }
        for _ in 0..<Self.drainCount {
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    /// Re-asserts the hide and disassociation every 2 seconds. macOS may
    /// override these when a shielding-level window activates or the cursor
    /// is handed to another process. A lightweight periodic restore prevents
    /// brief gaps from letting the cursor reappear.
    private func startHardening() {
        stopHardening()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: .seconds(2), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.applyHide()
        }
        hardeningTimer = timer
        timer.resume()
    }

    private func stopHardening() {
        hardeningTimer?.cancel()
        hardeningTimer = nil
    }

    deinit {
        if isHidden {
            stopHardening()
            applyShow()
            isHidden = false
        }
    }
}
