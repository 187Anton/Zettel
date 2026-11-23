import AppKit

/// Plain-text editor for a note.
final class NoteTextView: NSTextView {
    /// Esc closes the window, unless an input method is composing text.
    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == 53, // kVK_Escape
           KeyModifiers(event.modifierFlags).isEmpty,
           !hasMarkedText() {
            window?.cancelOperation(nil)
            return
        }
        super.keyDown(with: event)
    }

    /// NSTextView maps Esc to completion by default; we use Esc for closing.
    override func complete(_ sender: Any?) {
        window?.cancelOperation(sender)
    }
}

/// Scroll view that turns two-finger horizontal swipes into navigation.
final class NoteScrollView: NSScrollView {
    var onSwipe: ((HorizontalSwipeTracker.Direction) -> Void)?
    private var tracker = HorizontalSwipeTracker()

    override func scrollWheel(with event: NSEvent) {
        let phase: HorizontalSwipeTracker.Phase
        if !event.momentumPhase.isEmpty {
            phase = .other
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else if event.phase.contains(.ended) {
            phase = .ended
        } else if event.phase.contains(.cancelled) {
            phase = .cancelled
        } else {
            phase = .other
        }

        if let direction = tracker.handle(
            phase: phase,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isDirectionInverted: event.isDirectionInvertedFromDevice
        ) {
            onSwipe?(direction)
        }

        if !tracker.isTrackingHorizontalSwipe {
            super.scrollWheel(with: event)
        }
    }
}
