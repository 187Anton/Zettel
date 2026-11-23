import Foundation
import GRDB

/// SQLite persistence for notes (GRDB). All writes are small and synchronous.
final class NoteStore: Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// Database in Application Support (inside the sandbox container).
    static func openDefault() throws -> NoteStore {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Zettel", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try open(at: directory.appendingPathComponent("Zettel.sqlite"))
    }

    static func open(at url: URL) throws -> NoteStore {
        try NoteStore(dbQueue: DatabaseQueue(path: url.path))
    }

    /// Non-persistent store for tests and as fallback if the file cannot be opened.
    static func inMemory() throws -> NoteStore {
        try NoteStore(dbQueue: DatabaseQueue())
    }

    // MARK: Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_createNote") { db in
            try db.create(table: "note") { t in
                t.primaryKey("id", .text)
                t.column("text", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("touchedAt", .datetime).notNull()
                t.column("trashedAt", .datetime)
            }
            try db.create(index: "note_on_trashedAt_touchedAt", on: "note", columns: ["trashedAt", "touchedAt"])
        }
        migrator.registerMigration("v2_slotsAndArchive") { db in
            try db.alter(table: "note") { t in
                t.add(column: "slot", .integer)
                t.add(column: "archivedAt", .datetime)
            }
            try db.create(index: "note_on_slot", on: "note", columns: ["slot"])
        }
        return migrator
    }

    // MARK: Queries

    /// Notes in the stack (not in the trash, archive or a slot), most recently touched first.
    func stack() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Note.Columns.trashedAt == nil && Note.Columns.archivedAt == nil && Note.Columns.slot == nil)
                .order(Note.Columns.touchedAt.desc, Note.Columns.createdAt.desc, Note.Columns.id)
                .fetchAll(db)
        }
    }

    /// The note in a slot (1–9), if any.
    func note(inSlot slot: Int) throws -> Note? {
        try dbQueue.read { db in
            try Note
                .filter(Note.Columns.slot == slot && Note.Columns.trashedAt == nil && Note.Columns.archivedAt == nil)
                .fetchOne(db)
        }
    }

    func archived() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Note.Columns.archivedAt != nil && Note.Columns.trashedAt == nil)
                .order(Note.Columns.archivedAt.desc)
                .fetchAll(db)
        }
    }

    /// Every note, for the search.
    func allNotes() throws -> [Note] {
        try dbQueue.read { db in
            try Note.order(Note.Columns.updatedAt.desc).fetchAll(db)
        }
    }

    func note(id: String) throws -> Note? {
        try dbQueue.read { db in try Note.fetchOne(db, key: id) }
    }

    func trashed() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Note.Columns.trashedAt != nil)
                .order(Note.Columns.trashedAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: Changes

    func insert(_ note: Note) throws {
        try dbQueue.write { db in try note.insert(db) }
    }

    /// Inserts or updates the full record.
    func save(_ note: Note) throws {
        try dbQueue.write { db in try note.save(db) }
    }

    /// Moves a note to the trash (never deletes it). Stores the given text state too.
    func trash(_ note: Note, at date: Date) throws {
        var trashed = note
        trashed.trashedAt = date
        try save(trashed)
    }

    /// Moves a note to the archive. It leaves its slot.
    func archive(_ note: Note, at date: Date) throws {
        var archived = note
        archived.archivedAt = date
        archived.slot = nil
        try save(archived)
    }

    /// Back from the archive: on top of the stack.
    func unarchive(id: String, at date: Date) throws {
        try dbQueue.write { db in
            guard var note = try Note.fetchOne(db, key: id) else { return }
            note.archivedAt = nil
            note.touchedAt = date
            try note.save(db)
        }
    }

    /// Back from the trash: into its slot if that is still free, else on top of the stack.
    func restoreFromTrash(id: String, at date: Date) throws {
        try dbQueue.write { db in
            guard var note = try Note.fetchOne(db, key: id) else { return }
            if let slot = note.slot,
               try Note.filter(Note.Columns.slot == slot && Note.Columns.trashedAt == nil && Note.Columns.id != id).fetchCount(db) > 0 {
                note.slot = nil
            }
            note.trashedAt = nil
            note.touchedAt = date
            try note.save(db)
        }
    }

    /// Moves stack notes whose text was not changed since `cutoff` to the trash.
    /// Slots and the archive never expire. Returns the number of notes moved.
    @discardableResult
    func expireUnchangedNotes(before cutoff: Date, at date: Date) throws -> Int {
        try dbQueue.write { db in
            try Note
                .filter(Note.Columns.trashedAt == nil && Note.Columns.archivedAt == nil && Note.Columns.slot == nil)
                .filter(Note.Columns.updatedAt < cutoff)
                .updateAll(db, Note.Columns.trashedAt.set(to: date))
        }
    }

    /// Permanently deletes notes that have been in the trash since before `cutoff`.
    @discardableResult
    func purgeTrash(trashedBefore cutoff: Date) throws -> Int {
        try dbQueue.write { db in
            try Note.filter(Note.Columns.trashedAt != nil && Note.Columns.trashedAt < cutoff).deleteAll(db)
        }
    }

    // MARK: Backups

    /// Writes a consistent copy of the database to `url` (SQLite online backup).
    func backup(to url: URL) throws {
        let destination = try DatabaseQueue(path: url.path)
        try dbQueue.backup(to: destination)
    }

    /// Replaces all notes with the contents of the backup at `url`.
    func restore(from url: URL) throws {
        let source = try DatabaseQueue(path: url.path)
        try source.backup(to: dbQueue)
        try Self.migrator.migrate(dbQueue)
    }

    /// Permanently deletes a note. Only used for blank notes.
    func deleteBlank(id: String) throws {
        try dbQueue.write { db in
            guard let note = try Note.fetchOne(db, key: id), note.isBlank else { return }
            _ = try Note.deleteOne(db, key: id)
        }
    }

    /// Removes blank notes left in the stack (e.g. after a crash).
    func deleteBlankNotes() throws {
        try dbQueue.write { db in
            let blankIDs = try Note
                .filter(Note.Columns.trashedAt == nil)
                .fetchAll(db)
                .filter(\.isBlank)
                .map(\.id)
            _ = try Note.deleteAll(db, keys: blankIDs)
        }
    }
}
