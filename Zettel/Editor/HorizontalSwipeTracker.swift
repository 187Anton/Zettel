import CoreGraphics

/// Detects a two-finger horizontal swipe from trackpad scroll events. AppKit-free.
///
/// A gesture is locked to one axis after a few points of movement, so vertical
/// scrolling never triggers navigation. Each gesture fires at most once.
struct HorizontalSwipeTracker {
    enum Phase {
        case began, changed, ended, cancelled
        /// Momentum events after lifting the fingers, or a classic mouse wheel.
        case other
    }

    /// Physical direction the fingers moved.
    enum Direction: Equatable {
        case left, right
    }

    private enum Axis { case horizontal, vertical }

    var threshold: CGFloat = 50
    var lockDistance: CGFloat = 8

    private var deltaX: CGFloat = 0
    private var deltaY: CGFloat = 0
    private var axis: Axis?
    private var hasFired = false
    private var isActive = false

    /// `true` while the current gesture is a horizontal swipe; scroll events
    /// should then not be forwarded to the scroll view.
    var isTrackingHorizontalSwipe: Bool { isActive && axis == .horizontal }

    /// - Parameter isDirectionInverted: `NSEvent.isDirectionInvertedFromDevice`
    ///   ("natural scrolling"), needed to know which way the fingers moved.
    mutating func handle(phase: Phase, deltaX dx: CGFloat, deltaY dy: CGFloat, isDirectionInverted: Bool) -> Direction? {
        switch phase {
        case .began:
            reset()
            isActive = true
        case .changed:
            guard isActive else { return nil }
        case .ended, .cancelled:
            reset()
            return nil
        case .other:
            return nil
        }

        deltaX += dx
        deltaY += dy

        if axis == nil, abs(deltaX) + abs(deltaY) >= lockDistance {
            axis = abs(deltaX) > 2 * abs(deltaY) ? .horizontal : .vertical
        }

        guard axis == .horizontal, !hasFired, abs(deltaX) >= threshold else { return nil }
        hasFired = true
        let fingersMovedRight = isDirectionInverted ? deltaX > 0 : deltaX < 0
        return fingersMovedRight ? .right : .left
    }

    private mutating func reset() {
        deltaX = 0
        deltaY = 0
        axis = nil
        hasFired = false
        isActive = false
    }
}
