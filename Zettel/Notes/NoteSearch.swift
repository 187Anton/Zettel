import Foundation

/// Search over all notes: case- and diacritic-insensitive, every word must occur.
enum NoteSearch {
    enum Filter: String, CaseIterable, Sendable {
        case all, stack, slots, archive, trash

        var title: String {
            switch self {
            case .all: "Alle"
            case .stack: "Stapel"
            case .slots: "Plätze"
            case .archive: "Archiv"
            case .trash: "Papierkorb"
            }
        }

        func includes(_ location: Note.Location) -> Bool {
            switch (self, location) {
            case (.all, .trash): false
            case (.all, _): true
            case (.stack, .stack), (.archive, .archive), (.trash, .trash): true
            case (.slots, .slot): true
            default: false
            }
        }
    }

    struct Result: Identifiable, Equatable, Sendable {
        var id: String { note.id }
        var note: Note
        /// First non-empty line (the header's title for keyword notes).
        var title: String
        /// Text around the first match, or the second line without a query.
        var snippet: String
    }

    static let lockedTitle = "Gesperrte Notiz"

    /// Locked notes are listed (without a query) but their text is never searched or shown.
    static func search(_ notes: [Note], query: String, filter: Filter) -> [Result] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return notes
            .filter { filter.includes($0.location) && !$0.isBlank }
            .filter { note in
                if note.isLocked { return words.isEmpty }
                return words.allSatisfy { note.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { note in
                note.isLocked
                    ? Result(note: note, title: lockedTitle, snippet: "")
                    : Result(note: note, title: title(of: note.text), snippet: snippet(of: note.text, matching: words.first))
            }
    }

    static func title(of text: String) -> String {
        let firstLine = text.split(separator: "\n").first { !$0.allSatisfy(\.isWhitespace) }.map(String.init) ?? ""
        if let header = KeywordHeader(line: firstLine) {
            return header.title ?? header.keyword.rawValue
        }
        return ListLine(markdown: firstLine).content.trimmingCharacters(in: .whitespaces)
    }

    static func snippet(of text: String, matching word: String?, radius: Int = 40) -> String {
        let flat = text.split(separator: "\n").map { ListLine(markdown: String($0)).content }.joined(separator: " · ")
        guard let word, let range = flat.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) else {
            let lines = text.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }
            return lines.dropFirst().first.map { ListLine(markdown: String($0)).content } ?? ""
        }
        let start = flat.index(range.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}

/// How long unchanged notes stay in the stack, and how long the trash keeps notes.
enum NoteRetention {
    enum Expiry: String, CaseIterable, Sendable {
        case today, week, month, year, never

        var title: String {
            switch self {
            case .today: "Ende des Tages"
            case .week: "1 Woche"
            case .month: "1 Monat"
            case .year: "1 Jahr"
            case .never: "Nie"
            }
        }

        /// Notes last changed before this date expire.
        func cutoff(now: Date, calendar: Calendar = .current) -> Date? {
            switch self {
            case .today: calendar.startOfDay(for: now)
            case .week: calendar.date(byAdding: .day, value: -7, to: now)
            case .month: calendar.date(byAdding: .month, value: -1, to: now)
            case .year: calendar.date(byAdding: .year, value: -1, to: now)
            case .never: nil
            }
        }
    }

    enum TrashPeriod: Int, CaseIterable, Sendable {
        case days7 = 7, days30 = 30, days90 = 90, never = 0

        var title: String {
            self == .never ? "Nie" : "Nach \(rawValue) Tagen"
        }

        func cutoff(now: Date, calendar: Calendar = .current) -> Date? {
            self == .never ? nil : calendar.date(byAdding: .day, value: -rawValue, to: now)
        }
    }

    /// Runs expiry and trash cleanup. Cheap; called at launch and when the window opens.
    @discardableResult
    static func apply(expiry: Expiry, trash: TrashPeriod, to store: NoteStore, now: Date, calendar: Calendar = .current) throws -> (expired: Int, purged: Int) {
        let expired = try expiry.cutoff(now: now, calendar: calendar).map { try store.expireUnchangedNotes(before: $0, at: now) } ?? 0
        let purged = try trash.cutoff(now: now, calendar: calendar).map { try store.purgeTrash(trashedBefore: $0) } ?? 0
        return (expired, purged)
    }
}
