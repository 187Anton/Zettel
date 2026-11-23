import Foundation
import GRDB

/// A single note. Content is plain text with light Markdown markers.
struct Note: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var createdAt: Date
    /// Last change of the text. Used later for auto-expiry of untouched notes.
    var updatedAt: Date
    /// Position in the stack: set on creation, on every edit and by "bring to front".
    var touchedAt: Date
    /// Set when the note was moved to the trash; `nil` while it is in the stack.
    var trashedAt: Date?

    init(id: String = UUID().uuidString, text: String = "", date: Date) {
        self.id = id
        self.text = text
        self.createdAt = date
        self.updatedAt = date
        self.touchedAt = date
        self.trashedAt = nil
    }

    /// Empty or whitespace only. Blank notes are discarded instead of kept.
    var isBlank: Bool {
        text.allSatisfy(\.isWhitespace)
    }
}

extension Note: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let text = Column(CodingKeys.text)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let touchedAt = Column(CodingKeys.touchedAt)
        static let trashedAt = Column(CodingKeys.trashedAt)
    }
}
