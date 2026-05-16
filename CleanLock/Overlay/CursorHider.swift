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
/// Crash safety: cursor visibility is owned by the WindowServer per-process
/// connection. When this process dies — for any reason — the WindowServer
/// drops our hide reference and the cursor reappears automatically. There is
/// no persistent system state to leak.
final class CursorHider {
    private var isHidden = false

    func hide() {
        precondition(Thread.isMainThread)
        guard !isHidden else { return }

        // Hide across all displays (the API is global despite the "Display" name).
        CGDisplayHideCursor(CGMainDisplayID())

        // Belt-and-braces: NSCursor.hide() works through the AppKit cursor
        // stack and complements the Quartz call. Each call is ref-counted, so
        // pair every hide with exactly one show.
        NSCursor.hide()

        // Decouple cursor movement from physical mouse movement. Without this,
        // the cursor can reappear momentarily when another process briefly
        // becomes frontmost (e.g. system UI on Space transitions).
        CGAssociateMouseAndMouseCursorPosition(0)

        isHidden = true
    }

    func show() {
        precondition(Thread.isMainThread)
        guard isHidden else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        CGDisplayShowCursor(CGMainDisplayID())
        isHidden = false
    }

    deinit {
        // Best-effort cleanup if this object is dropped without an explicit
        // show(). AppKit's WindowServer client is thread-safe enough for a
        // single trailing show().
        if isHidden {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            isHidden = false
        }
    }
}
