import Foundation
import GRDB
import Testing
@testable import Zettel

struct NoteStorePhase7Tests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func note(_ text: String, updated offset: TimeInterval = 0, slot: Int? = nil) -> Note {
        var note = Note(text: text, date: base.addingTimeInterval(offset), slot: slot)
        note.touchedAt = base.addingTimeInterval(offset)
        return note
    }

    @Test func slotAndArchivedNotesAreNotInTheStack() throws {
        let store = try NoteStore.inMemory()
        try store.insert(note("Stapel"))
        try store.insert(note("Platz", slot: 3))
        let archived = note("Archiv")
        try store.insert(archived)
        try store.archive(archived, at: base)

        #expect(try store.stack().map(\.text) == ["Stapel"])
        #expect(try store.note(inSlot: 3)?.text == "Platz")
        #expect(try store.note(inSlot: 4) == nil)
        #expect(try store.archived().map(\.text) == ["Archiv"])
        #expect(try store.allNotes().count == 3)
    }

    @Test func archivingLeavesTheSlot() throws {
        let store = try NoteStore.inMemory()
        let slotted = note("x", slot: 2)
        try store.insert(slotted)
        try store.archive(slotted, at: base)
        #expect(try store.note(inSlot: 2) == nil)
        try store.unarchive(id: slotted.id, at: base.addingTimeInterval(10))
        #expect(try store.stack().map(\.text) == ["x"])
    }

    @Test func restoreFromTrashReturnsToFreeSlot() throws {
        let store = try NoteStore.inMemory()
        let slotted = note("alt", slot: 5)
        try store.insert(slotted)
        try store.trash(slotted, at: base)
        #expect(try store.note(inSlot: 5) == nil)

        try store.restoreFromTrash(id: slotted.id, at: base)
        #expect(try store.note(inSlot: 5)?.text == "alt")
    }

    @Test func restoreFromTrashGoesToStackIfSlotIsTaken() throws {
        let store = try NoteStore.inMemory()
        let old = note("alt", slot: 5)
        try store.insert(old)
        try store.trash(old, at: base)
        try store.insert(note("neu", slot: 5))

        try store.restoreFromTrash(id: old.id, at: base)
        #expect(try store.note(inSlot: 5)?.text == "neu")
        #expect(try store.stack().map(\.text) == ["alt"])
    }

    @Test func expiryOnlyAffectsUnchangedStackNotes() throws {
        let store = try NoteStore.inMemory()
        try store.insert(note("alt", updated: 0))
        try store.insert(note("neu", updated: 100))
        try store.insert(note("Platz alt", updated: 0, slot: 1))
        let archived = note("Archiv alt", updated: 0)
        try store.insert(archived)
        try store.archive(archived, at: base)

        let expired = try store.expireUnchangedNotes(before: base.addingTimeInterval(50), at: base.addingTimeInterval(200))

        #expect(expired == 1)
        #expect(try store.stack().map(\.text) == ["neu"])
        #expect(try store.trashed().map(\.text) == ["alt"])
        #expect(try store.note(inSlot: 1) != nil)
        #expect(try store.archived().count == 1)
    }

    @Test func purgeDeletesOnlyOldTrash() throws {
        let store = try NoteStore.inMemory()
        let old = note("alt")
        let recent = note("frisch")
        try store.insert(old)
        try store.insert(recent)
        try store.trash(old, at: base)
        try store.trash(recent, at: base.addingTimeInterval(1000))

        #expect(try store.purgeTrash(trashedBefore: base.addingTimeInterval(500)) == 1)
        #expect(try store.trashed().map(\.text) == ["frisch"])
    }

    @Test func migratesExistingVersionOneDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("v1.sqlite")

        // A database as written by Phase 2–6.
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1_createNote');
                CREATE TABLE note (id TEXT PRIMARY KEY, text TEXT NOT NULL DEFAULT '',
                    createdAt DATETIME NOT NULL, updatedAt DATETIME NOT NULL,
                    touchedAt DATETIME NOT NULL, trashedAt DATETIME);
                INSERT INTO note VALUES ('a', 'Alte Notiz', '2026-11-20 10:00:00.000', '2026-11-20 10:00:00.000', '2026-11-20 10:00:00.000', NULL);
                """)
        }
        try queue.close()

        let store = try NoteStore.open(at: url)
        let notes = try store.stack()
        #expect(notes.map(\.text) == ["Alte Notiz"])
        #expect(notes.first?.slot == nil)
        #expect(notes.first?.archivedAt == nil)
    }
}

@MainActor
struct SlotModeTests {
    private let clock = TestClock()

    private func model(_ store: NoteStore? = nil) throws -> (NoteStackModel, NoteStore) {
        let store = try store ?? NoteStore.inMemory()
        return (try makeModel(store: store, clock: clock), store)
    }

    @Test func toggleSwitchesBetweenStackAndLastSlot() throws {
        let (model, _) = try model()
        model.updateCurrentText("Stapel")
        try model.toggleMode()
        #expect(model.mode == .slot(1))
        #expect(model.current.isBlank)
        #expect(model.positionDescription == "Platz 1")

        try model.selectSlot(4)
        try model.toggleMode()
        #expect(model.mode == .stack)
        #expect(model.current.text == "Stapel")
        try model.toggleMode()
        #expect(model.mode == .slot(4))
    }

    @Test func slotContentIsSavedAndReloaded() throws {
        let (model, store) = try model()
        try model.selectSlot(3)
        model.updateCurrentText("Passwortliste? Nein: Einkaufsliste")
        try model.selectSlot(4)

        #expect(try store.note(inSlot: 3)?.text == "Passwortliste? Nein: Einkaufsliste")
        let restarted = try makeModel(store: store, clock: clock)
        try restarted.selectSlot(3)
        #expect(restarted.current.text == "Passwortliste? Nein: Einkaufsliste")
        #expect(restarted.count == 1) // slot note is not in the stack
    }

    @Test func emptySlotLeavesNoNoteBehind() throws {
        let (model, store) = try model()
        try model.selectSlot(2)
        try model.selectSlot(3)
        #expect(try store.note(inSlot: 2) == nil)
    }

    @Test func bracketsMoveBetweenSlots() throws {
        let (model, _) = try model()
        try model.selectSlot(1)
        try model.showNewer()
        #expect(model.mode == .slot(1))
        try model.showOlder()
        #expect(model.mode == .slot(2))
        try model.selectSlot(9)
        try model.showOlder()
        #expect(model.mode == .slot(9))
    }

    @Test func newNoteFromSlotGoesToStack() throws {
        let (model, _) = try model()
        model.updateCurrentText("A")
        try model.selectSlot(1)
        model.updateCurrentText("Platz")
        try model.createNote()
        #expect(model.mode == .stack)
        #expect(model.current.isBlank)
        #expect(model.count == 2)
    }

    @Test func trashInSlotEmptiesSlot() throws {
        let (model, store) = try model()
        try model.selectSlot(5)
        model.updateCurrentText("weg")
        try model.trashCurrent()
        #expect(model.mode == .slot(5))
        #expect(model.current.isBlank)
        #expect(try store.trashed().map(\.text) == ["weg"])
    }

    @Test func archiveInStackShowsNextNote() throws {
        let (model, store) = try model()
        model.updateCurrentText("A")
        try model.save()
        clock.advance()
        try model.createNote()
        model.updateCurrentText("B")

        try model.archiveCurrent()

        #expect(model.current.text == "A")
        #expect(try store.archived().map(\.text) == ["B"])
    }

    @Test func openFindsStackAndSlotNotes() throws {
        let (model, store) = try model()
        model.updateCurrentText("A")
        try model.save()
        clock.advance()
        try model.createNote()
        model.updateCurrentText("B")
        try model.save()
        let slotted = Note(text: "Platz 7", date: clock.now, slot: 7)
        try store.insert(slotted)

        let firstID = try #require(try store.stack().last?.id)
        #expect(try model.open(noteID: firstID))
        #expect(model.current.text == "A")

        #expect(try model.open(noteID: slotted.id))
        #expect(model.mode == .slot(7))
    }

    @Test func restoreAndOpenBringsBackTrashedNote() throws {
        let (model, store) = try model()
        model.updateCurrentText("Wichtig")
        let id = try model.trashCurrent()
        #expect(try model.open(noteID: id) == false)

        try model.restoreAndOpen(noteID: id)

        #expect(model.current.text == "Wichtig")
        #expect(try store.trashed().isEmpty)
    }
}

struct NoteSearchTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func note(_ text: String, _ offset: TimeInterval, slot: Int? = nil, archived: Bool = false, trashed: Bool = false) -> Note {
        var note = Note(text: text, date: base.addingTimeInterval(offset), slot: slot)
        if archived { note.archivedAt = base }
        if trashed { note.trashedAt = base }
        return note
    }

    private var notes: [Note] {
        [
            note("Einkauf\n- [ ] Äpfel\n- [ ] Brot", 10),
            note("math: Budget\nmiete : 800", 20, slot: 1),
            note("Alte Idee mit apfel", 5, archived: true),
            note("Gelöscht: Apfelkuchen", 30, trashed: true),
            note("   ", 40),
        ]
    }

    @Test func allExcludesTrashAndBlankNotes() {
        #expect(NoteSearch.search(notes, query: "", filter: .all).map(\.title) == ["Budget", "Einkauf", "Alte Idee mit apfel"])
    }

    @Test func matchesCaseAndDiacriticInsensitive() {
        #expect(NoteSearch.search(notes, query: "APFEL", filter: .all).map(\.title) == ["Einkauf", "Alte Idee mit apfel"])
    }

    @Test func allWordsMustMatch() {
        #expect(NoteSearch.search(notes, query: "miete budget", filter: .all).map(\.title) == ["Budget"])
        #expect(NoteSearch.search(notes, query: "miete brot", filter: .all).isEmpty)
    }

    @Test(arguments: [
        (NoteSearch.Filter.stack, ["Einkauf"]),
        (.slots, ["Budget"]),
        (.archive, ["Alte Idee mit apfel"]),
        (.trash, ["Gelöscht: Apfelkuchen"]),
    ])
    func filters(filter: NoteSearch.Filter, titles: [String]) {
        #expect(NoteSearch.search(notes, query: "", filter: filter).map(\.title) == titles)
    }

    @Test func snippetShowsMatchInContext() {
        let result = NoteSearch.search(notes, query: "brot", filter: .all).first
        #expect(result?.snippet == "Einkauf · Äpfel · Brot")
    }

    @Test func snippetWithoutQueryIsSecondLine() {
        #expect(NoteSearch.snippet(of: "Titel\n\n- [ ] Erster Punkt\nmehr", matching: nil) == "Erster Punkt")
    }
}

struct RetentionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    @Test func cutoffs() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 15))!
        #expect(NoteRetention.Expiry.today.cutoff(now: now, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 11, day: 23)))
        #expect(NoteRetention.Expiry.week.cutoff(now: now, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 15)))
        #expect(NoteRetention.Expiry.never.cutoff(now: now, calendar: calendar) == nil)
        #expect(NoteRetention.TrashPeriod.days30.cutoff(now: now, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15)))
        #expect(NoteRetention.TrashPeriod.never.cutoff(now: now, calendar: calendar) == nil)
    }

    @Test func applyExpiresAndPurges() throws {
        let store = try NoteStore.inMemory()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try store.insert(Note(text: "vor zwei Wochen", date: now.addingTimeInterval(-14 * 86400)))
        let trashed = Note(text: "lange im Papierkorb", date: now)
        try store.insert(trashed)
        try store.trash(trashed, at: now.addingTimeInterval(-40 * 86400))

        let result = try NoteRetention.apply(expiry: .week, trash: .days30, to: store, now: now, calendar: calendar)

        #expect(result.expired == 1)
        #expect(result.purged == 1)
        #expect(try store.trashed().map(\.text) == ["vor zwei Wochen"])
    }

    @Test func neverChangesNothing() throws {
        let store = try NoteStore.inMemory()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try store.insert(Note(text: "uralt", date: now.addingTimeInterval(-1000 * 86400)))
        let result = try NoteRetention.apply(expiry: .never, trash: .never, to: store, now: now)
        #expect(result.expired == 0 && result.purged == 0)
    }
}

struct BackupManagerTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func backupAndRestore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try NoteStore.open(at: directory.appendingPathComponent("main.sqlite"))
        let manager = BackupManager(store: store, directory: directory.appendingPathComponent("Backups"))
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

        try store.insert(Note(text: "Version 1", date: date))
        let backup = try manager.createBackup(at: date)
        try store.insert(Note(text: "Version 2", date: date.addingTimeInterval(10)))
        #expect(try store.stack().count == 2)

        try manager.restore(backup, now: date.addingTimeInterval(20))

        #expect(try store.stack().map(\.text) == ["Version 1"])
        // The state before the restore was saved as well.
        #expect(manager.backups().count == 2)
    }

    @Test func backupIfDueRespectsInterval() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = BackupManager(store: try NoteStore.inMemory(), directory: directory)
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

        #expect(try manager.backupIfDue(interval: .daily, now: date) != nil)
        #expect(try manager.backupIfDue(interval: .daily, now: date.addingTimeInterval(3600)) == nil)
        #expect(try manager.backupIfDue(interval: .daily, now: date.addingTimeInterval(86400)) != nil)
        #expect(try manager.backupIfDue(interval: .never, now: date.addingTimeInterval(9_999_999)) == nil)
        #expect(manager.backups().count == 2)
    }

    @Test func keepsOnlyNewestBackups() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = BackupManager(store: try NoteStore.inMemory(), directory: directory, keep: 3)
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for hour in 0..<5 {
            try manager.createBackup(at: date.addingTimeInterval(Double(hour) * 3600))
        }
        let backups = manager.backups()
        #expect(backups.count == 3)
        #expect(backups.first?.date == date.addingTimeInterval(4 * 3600))
    }

    @Test func ignoresForeignFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("notiz.txt"))
        try Data().write(to: directory.appendingPathComponent("Zettel-kaputt.sqlite"))
        #expect(BackupManager(store: try NoteStore.inMemory(), directory: directory).backups().isEmpty)
    }
}
