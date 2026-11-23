import Foundation
import Testing
@testable import Zettel

@MainActor
struct NoteStackModelTests {
    private let clock = TestClock()

    /// Creates a model with notes "A" (oldest) … last (newest), current = newest.
    private func modelWithNotes(_ texts: [String], store: NoteStore? = nil) throws -> (NoteStackModel, NoteStore) {
        let store = try store ?? NoteStore.inMemory()
        let model = try makeModel(store: store, clock: clock)
        for (index, text) in texts.enumerated() {
            if index > 0 {
                clock.advance()
                try model.createNote()
            }
            clock.advance()
            model.updateCurrentText(text)
            try model.save()
        }
        return (model, store)
    }

    private func texts(_ model: NoteStackModel) -> [String] {
        model.notes.map(\.text)
    }

    // MARK: Start

    @Test func startsWithOneBlankNoteWhenEmpty() throws {
        let model = try makeModel(clock: clock)
        #expect(model.count == 1)
        #expect(model.current.isBlank)
        #expect(model.positionDescription == "1/1")
    }

    @Test func startsWithNewestNoteAndRemovesLeftoverBlankNotes() throws {
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: "alt", date: clock.now))
        clock.advance()
        try store.insert(Note(text: "", date: clock.now))
        clock.advance()

        let model = try makeModel(store: store, clock: clock)

        #expect(texts(model) == ["alt"])
        #expect(model.current.text == "alt")
    }

    // MARK: Editing & saving

    @Test func editsAreSavedOnlyOnSave() throws {
        let store = try NoteStore.inMemory()
        let model = try makeModel(store: store, clock: clock)
        model.updateCurrentText("Hallo")

        #expect(model.hasUnsavedChanges)
        #expect(try store.note(id: model.current.id)?.text == "")

        try model.save()
        #expect(!model.hasUnsavedChanges)
        #expect(try store.note(id: model.current.id)?.text == "Hallo")
    }

    @Test func editUpdatesTimestamps() throws {
        let model = try makeModel(clock: clock)
        let created = model.current.createdAt
        clock.advance(seconds: 30)
        model.updateCurrentText("x")
        #expect(model.current.createdAt == created)
        #expect(model.current.updatedAt == clock.now)
        #expect(model.current.touchedAt == clock.now)
    }

    @Test func identicalTextIsNoChange() throws {
        let (model, _) = try modelWithNotes(["A"])
        model.updateCurrentText("A")
        #expect(!model.hasUnsavedChanges)
    }

    // MARK: New note

    @Test func newNoteGoesOnTopAndSavesPrevious() throws {
        let (model, store) = try modelWithNotes(["A"])
        model.updateCurrentText("A bearbeitet")

        try model.createNote()

        #expect(model.currentIndex == 0)
        #expect(model.current.isBlank)
        #expect(texts(model) == ["", "A bearbeitet"])
        #expect(try store.stack().map(\.text).contains("A bearbeitet"))
    }

    @Test func newNoteReusesBlankCurrentNote() throws {
        let model = try makeModel(clock: clock)
        let id = model.current.id
        try model.createNote()
        #expect(model.count == 1)
        #expect(model.current.id == id)
    }

    // MARK: Navigation

    @Test func navigateOlderAndNewer() throws {
        let (model, _) = try modelWithNotes(["A", "B", "C"])
        #expect(texts(model) == ["C", "B", "A"])
        #expect(model.current.text == "C")

        try model.showOlder()
        #expect(model.current.text == "B")
        try model.showOlder()
        #expect(model.current.text == "A")
        try model.showOlder() // already oldest
        #expect(model.current.text == "A")
        #expect(model.positionDescription == "3/3")

        try model.showNewer()
        #expect(model.current.text == "B")
        try model.showNewer()
        try model.showNewer() // already newest
        #expect(model.current.text == "C")
    }

    @Test func editingDoesNotReorderWhileNavigating() throws {
        let (model, _) = try modelWithNotes(["A", "B", "C"])
        try model.showOlder()
        try model.showOlder()
        clock.advance()
        model.updateCurrentText("A neu")

        try model.showNewer()

        #expect(model.current.text == "B")
        #expect(texts(model) == ["C", "B", "A neu"])
    }

    @Test func leavingBlankNoteDeletesIt() throws {
        let (model, store) = try modelWithNotes(["A", "B"])
        try model.createNote() // blank on top

        try model.showOlder()

        #expect(model.current.text == "B")
        #expect(texts(model) == ["B", "A"])
        #expect(try store.stack().count == 2)
    }

    @Test func leavingBlankNoteTowardsNewerDeletesIt() throws {
        let (model, _) = try modelWithNotes(["A", "B"])
        try model.showOlder()
        model.updateCurrentText("   ")

        try model.showNewer()

        #expect(model.current.text == "B")
        #expect(texts(model) == ["B"])
    }

    @Test func newestResortsByLastChange() throws {
        let (model, _) = try modelWithNotes(["A", "B", "C"])
        try model.showOlder()
        try model.showOlder()
        clock.advance()
        model.updateCurrentText("A neu") // now the most recently changed note
        try model.showNewer()             // on "B"

        try model.showNewest()

        #expect(model.current.text == "A neu")
        #expect(model.currentIndex == 0)
        #expect(texts(model) == ["A neu", "C", "B"])
    }

    @Test func bringToFrontMovesCurrentNoteToTop() throws {
        let (model, store) = try modelWithNotes(["A", "B", "C"])
        try model.showOlder()
        try model.showOlder()
        clock.advance()

        try model.bringCurrentToFront()

        #expect(model.currentIndex == 0)
        #expect(texts(model) == ["A", "C", "B"])
        #expect(try store.stack().map(\.text) == ["A", "C", "B"])
        // Bringing to front is no content change.
        #expect(model.current.updatedAt < model.current.touchedAt)
    }

    // MARK: Trash

    @Test func trashMovesNoteToTrashAndShowsNextOlder() throws {
        let (model, store) = try modelWithNotes(["A", "B", "C"])
        try model.showOlder() // B

        try model.trashCurrent()

        #expect(model.current.text == "A")
        #expect(texts(model) == ["C", "A"])
        #expect(try store.trashed().map(\.text) == ["B"])
    }

    @Test func trashingOldestNoteShowsNewerOne() throws {
        let (model, _) = try modelWithNotes(["A", "B"])
        try model.showOlder()

        try model.trashCurrent()

        #expect(model.current.text == "B")
    }

    @Test func trashingLastNoteLeavesFreshBlankNote() throws {
        let (model, store) = try modelWithNotes(["A"])

        try model.trashCurrent()

        #expect(model.count == 1)
        #expect(model.current.isBlank)
        #expect(try store.trashed().map(\.text) == ["A"])
    }

    @Test func trashKeepsUnsavedText() throws {
        let (model, store) = try modelWithNotes(["A"])
        model.updateCurrentText("A, ungespeichert")

        try model.trashCurrent()

        #expect(try store.trashed().first?.text == "A, ungespeichert")
    }

    @Test func blankNoteIsDeletedInsteadOfTrashed() throws {
        let (model, store) = try modelWithNotes(["A"])
        try model.createNote()

        try model.trashCurrent()

        #expect(try store.trashed().isEmpty)
        #expect(model.current.text == "A")
    }

    // MARK: Show

    @Test func prepareForShowKeepsCurrentNote() throws {
        let (model, _) = try modelWithNotes(["A", "B"])
        try model.showOlder()
        try model.prepareForShow(startFresh: false)
        #expect(model.current.text == "A")
    }

    @Test func prepareForShowCanStartFresh() throws {
        let (model, _) = try modelWithNotes(["A", "B"])
        try model.showOlder()
        try model.prepareForShow(startFresh: true)
        #expect(model.currentIndex == 0)
        #expect(model.current.isBlank)
        #expect(model.count == 3)
    }

    @Test func notesSurviveRestart() throws {
        let store = try NoteStore.inMemory()
        let (model, _) = try modelWithNotes(["A", "B"], store: store)
        model.updateCurrentText("B final")
        try model.save()

        let restarted = try makeModel(store: store, clock: clock)
        #expect(texts(restarted) == ["B final", "A"])
    }
}

struct FreshNotePolicyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func offNeverStartsFresh() {
        #expect(!FreshNotePolicy.shouldStartFresh(lastFocusLoss: start, now: start.addingTimeInterval(99_999), idleMinutes: 0))
    }

    @Test func withoutFocusLossNeverStartsFresh() {
        #expect(!FreshNotePolicy.shouldStartFresh(lastFocusLoss: nil, now: start, idleMinutes: 5))
    }

    @Test func startsFreshAfterIdleTime() {
        #expect(!FreshNotePolicy.shouldStartFresh(lastFocusLoss: start, now: start.addingTimeInterval(299), idleMinutes: 5))
        #expect(FreshNotePolicy.shouldStartFresh(lastFocusLoss: start, now: start.addingTimeInterval(300), idleMinutes: 5))
    }
}
