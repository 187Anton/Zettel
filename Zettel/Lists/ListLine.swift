import Foundation

/// One line of a note, split into list structure and content.
///
/// A note exists in two forms:
/// - **Markdown** (stored): `- [ ] Milch`, `- [x] Brot`, `- Punkt`, `1. Schritt`
/// - **Display** (editor): `☐ Milch`, `☑ Brot`, `• Punkt`, `1. Schritt`
///
/// Indentation of list items is one tab per level in both forms.
/// Lines without a list marker are kept verbatim.
struct ListLine: Equatable, Sendable {
    enum Marker: Equatable, Sendable {
        case bullet
        case checkbox(checked: Bool)
        case numbered(Int)
    }

    static let maxIndent = 8

    /// Nesting level. Always 0 for plain lines (their whitespace is part of `content`).
    var indent: Int
    var marker: Marker?
    var content: String

    init(indent: Int = 0, marker: Marker?, content: String) {
        self.indent = marker == nil ? 0 : min(max(indent, 0), Self.maxIndent)
        self.marker = marker
        self.content = content
    }

    static func plain(_ content: String) -> ListLine {
        ListLine(marker: nil, content: content)
    }

    var isListItem: Bool { marker != nil }

    var isCheckbox: Bool {
        if case .checkbox = marker { return true }
        return false
    }

    var isChecked: Bool { marker == .checkbox(checked: true) }

    var isContentBlank: Bool { content.allSatisfy(\.isWhitespace) }

    // MARK: Display form

    static let uncheckedSymbol: Character = "☐"
    static let checkedSymbol: Character = "☑"
    static let bulletSymbol: Character = "•"

    init(display line: String) {
        let (tabs, rest) = Self.splitLeadingTabs(line)
        if rest.hasPrefix("\(Self.uncheckedSymbol) ") {
            self.init(indent: tabs, marker: .checkbox(checked: false), content: String(rest.dropFirst(2)))
        } else if rest.hasPrefix("\(Self.checkedSymbol) ") {
            self.init(indent: tabs, marker: .checkbox(checked: true), content: String(rest.dropFirst(2)))
        } else if rest.hasPrefix("\(Self.bulletSymbol) ") {
            self.init(indent: tabs, marker: .bullet, content: String(rest.dropFirst(2)))
        } else if let (number, content) = Self.splitNumber(rest) {
            self.init(indent: tabs, marker: .numbered(number), content: content)
        } else {
            self = .plain(line)
        }
    }

    var display: String {
        guard let marker else { return content }
        return String(repeating: "\t", count: indent) + Self.displayText(for: marker) + content
    }

    /// UTF-16 length of indentation plus marker in the display form.
    var displayMarkerLength: Int {
        guard let marker else { return 0 }
        return indent + Self.displayText(for: marker).utf16.count
    }

    static func displayText(for marker: Marker) -> String {
        switch marker {
        case .bullet: "\(bulletSymbol) "
        case .checkbox(let checked): "\(checked ? checkedSymbol : uncheckedSymbol) "
        case .numbered(let number): "\(number). "
        }
    }

    // MARK: Markdown form

    init(markdown line: String) {
        var level = 0
        var spaces = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "\t" || line[index] == " " {
            if line[index] == "\t" { level += 1 } else { spaces += 1 }
            index = line.index(after: index)
        }
        level += spaces / 2
        let rest = line[index...]

        for (prefix, marker) in Self.markdownPrefixes where rest.hasPrefix(prefix) {
            self.init(indent: level, marker: marker, content: String(rest.dropFirst(prefix.count)))
            return
        }
        if let (number, content) = Self.splitNumber(rest) {
            self.init(indent: level, marker: .numbered(number), content: content)
            return
        }
        self = .plain(line)
    }

    var markdown: String {
        guard let marker else { return content }
        let prefix: String = switch marker {
        case .bullet: "- "
        case .checkbox(let checked): checked ? "- [x] " : "- [ ] "
        case .numbered(let number): "\(number). "
        }
        return String(repeating: "\t", count: indent) + prefix + content
    }

    /// Checked before the plain bullets, longest first.
    private static let markdownPrefixes: [(String, Marker)] = [
        ("- [ ] ", .checkbox(checked: false)), ("* [ ] ", .checkbox(checked: false)),
        ("- [x] ", .checkbox(checked: true)), ("- [X] ", .checkbox(checked: true)),
        ("* [x] ", .checkbox(checked: true)), ("* [X] ", .checkbox(checked: true)),
        ("- ", .bullet), ("* ", .bullet),
    ]

    /// Fast check used during layout: is the character at `index` the ☐/☑ symbol
    /// of a checklist item (preceded only by tabs on its line, followed by a space)?
    static func isCheckboxMarker(in text: NSString, at index: Int) -> Bool {
        guard index < text.length else { return false }
        let character = text.character(at: index)
        guard character == 0x2610 || character == 0x2611,
              index + 1 < text.length, text.character(at: index + 1) == 0x20
        else { return false }
        var position = index - 1
        while position >= 0 {
            switch text.character(at: position) {
            case 0x09: position -= 1
            case 0x0A: return true
            default: return false
            }
        }
        return true
    }

    // MARK: Helpers

    static func splitLeadingTabs<S: StringProtocol>(_ line: S) -> (Int, S.SubSequence) {
        let tabs = line.prefix { $0 == "\t" }.count
        return (tabs, line.dropFirst(tabs))
    }

    /// `"12. Text"` → `(12, "Text")`. Up to 9 digits.
    static func splitNumber<S: StringProtocol>(_ text: S) -> (Int, String)? {
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard (1...9).contains(digits.count),
              text.dropFirst(digits.count).hasPrefix(". "),
              let number = Int(digits)
        else { return nil }
        return (number, String(text.dropFirst(digits.count + 2)))
    }
}

/// Converts whole notes between the stored Markdown form and the editor form.
/// `code` notes are shown and stored exactly as typed.
enum NoteFormat {
    static func display(fromMarkdown text: String) -> String {
        guard KeywordHeader(text: text)?.keyword != .code else { return text }
        return text.components(separatedBy: "\n").map { ListLine(markdown: $0).display }.joined(separator: "\n")
    }

    static func markdown(fromDisplay text: String) -> String {
        guard KeywordHeader(text: text)?.keyword != .code else { return text }
        return text.components(separatedBy: "\n").map { ListLine(display: $0).markdown }.joined(separator: "\n")
    }
}
