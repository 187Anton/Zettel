import Foundation
import Testing
@testable import Zettel

struct NoteStoreTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func note(_ text: String, touched offset: TimeInterval) -> Note {
        var note = Note(text: text, date: base)
        note.touchedAt = base.addingTimeInterval(offset)
        return note
    }

    @Test func emptyStoreHasEmptyStack() throws {
        #expect(try NoteStore.inMemory().stack().isEmpty)
    }

    @Test func insertAndReadBack() throws {
        let store = try NoteStore.inMemory()
        let note = note("Hallo", touched: 0)
        try store.insert(note)
        #expect(try store.note(id: note.id) == note)
    }

    @Test func stackIsSortedByTouchedAtNewestFirst() throws {
        let store = try NoteStore.inMemory()
        let old = note("alt", touched: 0)
        let new = note("neu", touched: 20)
        let middle = note("mitte", touched: 10)
        for n in [old, new, middle] { try store.insert(n) }

        #expect(try store.stack().map(\.text) == ["neu", "mitte", "alt"])
    }

    @Test func saveUpdatesExistingNote() throws {
        let store = try NoteStore.inMemory()
        var note = note("v1", touched: 0)
        try store.insert(note)
        note.text = "v2"
        try store.save(note)
        #expect(try store.note(id: note.id)?.text == "v2")
        #expect(try store.stack().count == 1)
    }

    @Test func trashKeepsNoteOutsideTheStack() throws {
        let store = try NoteStore.inMemory()
        var note = note("weg", touched: 0)
        try store.insert(note)
        note.text = "weg, aber gespeichert"

        try store.trash(note, at: base.addingTimeInterval(5))

        #expect(try store.stack().isEmpty)
        let trashed = try #require(try store.trashed().first)
        #expect(trashed.text == "weg, aber gespeichert")
        #expect(trashed.trashedAt == base.addingTimeInterval(5))
    }

    @Test func deleteBlankOnlyDeletesBlankNotes() throws {
        let store = try NoteStore.inMemory()
        let blank = note("  \n", touched: 0)
        let content = note("Inhalt", touched: 1)
        try store.insert(blank)
        try store.insert(content)

        try store.deleteBlank(id: blank.id)
        try store.deleteBlank(id: content.id)

        #expect(try store.note(id: blank.id) == nil)
        #expect(try store.note(id: content.id) != nil)
    }

    @Test func deleteBlankNotesCleansUpStackButNotTrash() throws {
        let store = try NoteStore.inMemory()
        try store.insert(note("", touched: 0))
        try store.insert(note("Text", touched: 1))
        let trashedBlank = note("", touched: 2)
        try store.insert(trashedBlank)
        try store.trash(trashedBlank, at: base)

        try store.deleteBlankNotes()

        #expect(try store.stack().map(\.text) == ["Text"])
        #expect(try store.trashed().count == 1)
    }

    @Test func dataSurvivesReopeningTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")

        let note = note("Bleibt erhalten", touched: 0)
        try NoteStore.open(at: url).insert(note)

        #expect(try NoteStore.open(at: url).note(id: note.id) == note)
    }

    @Test func blankDetection() {
        #expect(Note(text: "", date: base).isBlank)
        #expect(Note(text: " \n\t", date: base).isBlank)
        #expect(!Note(text: " x ", date: base).isBlank)
    }
}
