import Foundation

/// Keywords that switch a note into a special mode. They stand in the first
/// line, optionally followed by a title: `math: Budget`.
enum Keyword: String, CaseIterable, Sendable {
    case list
    case math
    case sum
    case avg
    case count
    case code
    case paste

    /// Shown in the keyword picker.
    var summary: String {
        switch self {
        case .list: "Checkliste – jede Zeile wird eine Checkbox"
        case .math: "Rechnen – Zeilen mit = zeigen ihr Ergebnis"
        case .sum: "Summe aller Zahlen"
        case .avg: "Durchschnitt aller Zahlen"
        case .count: "Einträge, Zeilen, Wörter, Zeichen zählen"
        case .code: "Code mit Syntaxfarben (code: py, js, swift …)"
        case .paste: "Sammelt neu kopierten Text, Esc beendet"
        }
    }
}

/// The parsed first line of a note.
struct KeywordHeader: Equatable, Sendable {
    var keyword: Keyword
    var title: String?

    /// `"math"`, `"Math: Budget"`, `" list : Einkauf "` …; `nil` for any other line.
    init?(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let name: Substring
        var title: String?
        if let colon = trimmed.firstIndex(of: ":") {
            name = trimmed[..<colon]
            let rest = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            title = rest.isEmpty ? nil : rest
        } else {
            name = Substring(trimmed)
        }
        guard let keyword = Keyword(rawValue: name.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }
        self.keyword = keyword
        self.title = title
    }

    init(keyword: Keyword, title: String?) {
        self.keyword = keyword
        self.title = title
    }

    /// Header of a whole text (its first line).
    init?(text: String) {
        let firstLine = text.prefix { $0 != "\n" }
        self.init(line: String(firstLine))
    }

    var line: String {
        title.map { "\(keyword.rawValue): \($0)" } ?? keyword.rawValue
    }
}

/// Edits for choosing a keyword in the picker.
enum KeywordEditing {
    /// Removes the `/` typed at `slashLocation` and sets `keyword` in the first line:
    /// - an existing keyword is replaced (title kept),
    /// - an empty first line (or one holding just the `/`) becomes the keyword,
    /// - otherwise the keyword is inserted as a new first line.
    ///
    /// Choosing `list` also turns all non-empty plain lines into checkboxes.
    static func apply(_ keyword: Keyword, in text: String, slashLocation: Int) -> TextEdit? {
        let ns = text as NSString
        guard slashLocation < ns.length, ns.character(at: slashLocation) == 0x2F else { return nil }
        let withoutSlash = ns.replacingCharacters(in: NSRange(location: slashLocation, length: 1), with: "")

        var document = LineDocument(withoutSlash)
        // A slash typed in the first line: continue at the end of the header line.
        let cursor = document.location(ofOffset: slashLocation).line == 0
            ? document.anchor(lineID: document.lines[0].id, contentOffset: Int.max / 2)
            : document.anchor(forOffset: slashLocation)
        let firstLine = document.lines[0].item

        if let header = KeywordHeader(line: firstLine.display) {
            document.lines[0].item = .plain(KeywordHeader(keyword: keyword, title: header.title).line)
        } else if firstLine.display.trimmingCharacters(in: .whitespaces).isEmpty {
            document.lines[0].item = .plain(keyword.rawValue)
        } else {
            document.insert(.plain(keyword.rawValue), at: 0)
        }

        if keyword == .code {
            // Code is shown raw: turn displayed ☐/•/… back into their Markdown text.
            for index in document.lines.indices.dropFirst() where document.lines[index].item.isListItem {
                document.lines[index].item = .plain(document.lines[index].item.markdown)
            }
        }

        if keyword == .list {
            for index in document.lines.indices.dropFirst() {
                let item = document.lines[index].item
                guard !item.isListItem, !item.isContentBlank, !item.content.hasPrefix("//") else { continue }
                document.lines[index].item = ListLine(marker: .checkbox(checked: false), content: item.content)
            }
        }

        // Even if nothing else changes (same keyword chosen), the slash is removed.
        let result = document.edit(selecting: cursor)?.applied(to: withoutSlash) ?? withoutSlash
        let position = document.offset(for: cursor)
        return TextEdit(
            range: NSRange(location: 0, length: ns.length),
            replacement: result,
            selection: NSRange(location: position, length: 0)
        )
    }
}
