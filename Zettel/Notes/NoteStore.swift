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
        return migrator
    }

    // MARK: Queries

    /// Notes not in the trash, most recently touched first.
    func stack() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Note.Columns.trashedAt == nil)
                .order(Note.Columns.touchedAt.desc, Note.Columns.createdAt.desc, Note.Columns.id)
                .fetchAll(db)
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
