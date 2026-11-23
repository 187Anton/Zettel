import Foundation
@testable import Zettel

/// Controllable clock. Whole seconds keep dates exact through SQLite (ms precision).
@MainActor
final class TestClock {
    var now: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        now = start
    }

    func advance(seconds: TimeInterval = 1) {
        now = now.addingTimeInterval(seconds)
    }

    var closure: () -> Date { { [unowned self] in self.now } }
}

@MainActor
func makeModel(store: NoteStore? = nil, clock: TestClock) throws -> NoteStackModel {
    try NoteStackModel(store: store ?? NoteStore.inMemory(), now: clock.closure)
}
