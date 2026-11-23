import Testing
@testable import Zettel

@MainActor
struct DebouncerTests {
    @Test func runsOnceAfterInputPauses() async throws {
        var runs = 0
        let debouncer = Debouncer(delay: .milliseconds(50)) { runs += 1 }

        debouncer.schedule()
        try await Task.sleep(for: .milliseconds(20))
        debouncer.schedule()
        try await Task.sleep(for: .milliseconds(20))
        debouncer.schedule()
        #expect(runs == 0)

        try await Task.sleep(for: .milliseconds(150))
        #expect(runs == 1)
        #expect(!debouncer.isPending)
    }

    @Test func flushRunsPendingActionImmediately() {
        var runs = 0
        let debouncer = Debouncer(delay: .seconds(10)) { runs += 1 }

        debouncer.flush() // nothing pending
        #expect(runs == 0)

        debouncer.schedule()
        debouncer.flush()
        #expect(runs == 1)
        #expect(!debouncer.isPending)
    }

    @Test func cancelDropsPendingAction() async throws {
        var runs = 0
        let debouncer = Debouncer(delay: .milliseconds(30)) { runs += 1 }
        debouncer.schedule()
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(runs == 0)
    }
}

struct HorizontalSwipeTrackerTests {
    private typealias Tracker = HorizontalSwipeTracker

    /// Feeds a gesture of `steps` equal deltas and returns all fired directions.
    private func swipe(dx: Double, dy: Double, steps: Int = 10, inverted: Bool = true) -> [Tracker.Direction] {
        var tracker = Tracker()
        var fired: [Tracker.Direction] = []
        for step in 0..<steps {
            let phase: Tracker.Phase = step == 0 ? .began : .changed
            if let direction = tracker.handle(phase: phase, deltaX: dx, deltaY: dy, isDirectionInverted: inverted) {
                fired.append(direction)
            }
        }
        _ = tracker.handle(phase: .ended, deltaX: 0, deltaY: 0, isDirectionInverted: inverted)
        return fired
    }

    @Test func horizontalSwipeFiresOnce() {
        #expect(swipe(dx: 10, dy: 0) == [.right])
        #expect(swipe(dx: -10, dy: 1) == [.left])
    }

    @Test func respectsScrollDirectionSetting() {
        #expect(swipe(dx: 10, dy: 0, inverted: false) == [.left])
        #expect(swipe(dx: -10, dy: 0, inverted: false) == [.right])
    }

    @Test func verticalScrollingNeverFires() {
        #expect(swipe(dx: 3, dy: 10).isEmpty)
        #expect(swipe(dx: 0, dy: -20).isEmpty)
    }

    @Test func shortSwipeDoesNotFire() {
        #expect(swipe(dx: 4, dy: 0, steps: 5).isEmpty)
    }

    @Test func momentumAndMouseWheelAreIgnored() {
        var tracker = Tracker()
        #expect(tracker.handle(phase: .other, deltaX: 500, deltaY: 0, isDirectionInverted: true) == nil)
        #expect(!tracker.isTrackingHorizontalSwipe)
    }

    @Test func tracksHorizontalSwipeUntilEnded() {
        var tracker = Tracker()
        _ = tracker.handle(phase: .began, deltaX: 10, deltaY: 0, isDirectionInverted: true)
        #expect(tracker.isTrackingHorizontalSwipe)
        _ = tracker.handle(phase: .ended, deltaX: 0, deltaY: 0, isDirectionInverted: true)
        #expect(!tracker.isTrackingHorizontalSwipe)
    }
}
