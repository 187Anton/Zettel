import Foundation

/// Light Markdown inside a line: `**fett**`, `_kursiv_` / `*kursiv*`, `<u>unterstrichen</u>`,
/// `~~durchgestrichen~~`, `` `Code` `` and headings `# … ######`.
/// The markers stay in the text (it is stored as Markdown); the editor mutes them.
enum InlineMarkup {
    enum Kind: Equatable, Sendable {
        case bold, italic, underline, strikethrough, code
        case heading(Int)
    }

    struct Span: Equatable, Sendable {
        var kind: Kind
        /// The formatted text (without markers), UTF-16 offsets in the line.
        var content: NSRange
        var markers: [NSRange]
    }

    private static let patterns: [(Kind, NSRegularExpression, open: Int, close: Int)] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern) // constant patterns
        }
        return [
            (.code, regex("`([^`]+)`"), 1, 1),
            (.bold, regex("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*"), 2, 2),
            (.italic, regex("(?<![\\w*])\\*(?=[^\\s*])(.+?)(?<=[^\\s*])\\*(?![\\w*])"), 1, 1),
            (.italic, regex("(?<![\\w])_(?=\\S)(.+?)(?<=\\S)_(?![\\w])"), 1, 1),
            (.strikethrough, regex("~~(?=\\S)(.+?)(?<=\\S)~~"), 2, 2),
            (.underline, regex("<u>(.+?)</u>"), 3, 4),
        ]
    }()

    static func spans(in line: String) -> [Span] {
        let text = line as NSString
        var spans: [Span] = []

        if let level = headingLevel(line) {
            let marker = NSRange(location: 0, length: level + 1)
            spans.append(Span(kind: .heading(level), content: NSRange(location: level + 1, length: text.length - level - 1), markers: [marker]))
        }

        var codeRanges: [NSRange] = []
        for (kind, regex, open, close) in patterns {
            for match in regex.matches(in: line, range: NSRange(location: 0, length: text.length)) {
                let whole = match.range
                // Nothing is formatted inside inline code.
                if kind != .code, codeRanges.contains(where: { NSIntersectionRange($0, whole).length > 0 }) { continue }
                let span = Span(
                    kind: kind,
                    content: match.range(at: 1),
                    markers: [
                        NSRange(location: whole.location, length: open),
                        NSRange(location: NSMaxRange(whole) - close, length: close),
                    ]
                )
                if kind == .code { codeRanges.append(whole) }
                spans.append(span)
            }
        }
        return spans
    }

    /// `# Titel` → 1 … `###### x` → 6.
    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }
}

/// Editing commands for formatting (⌘B, ⌘I, ⌘U, ⌘⇧X, ⌘/). Pure functions returning one edit.
enum InlineFormatting {
    enum Style: Equatable, Sendable {
        case bold, italic, underline, strikethrough

        var markers: (open: String, close: String) {
            switch self {
            case .bold: ("**", "**")
            case .italic: ("_", "_")
            case .underline: ("<u>", "</u>")
            case .strikethrough: ("~~", "~~")
            }
        }
    }

    /// Wraps the selection in markers, or removes them if it is already wrapped.
    /// Without a selection an empty pair is inserted with the cursor in between.
    static func toggle(_ style: Style, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let (open, close) = style.markers
        let openLength = (open as NSString).length
        let closeLength = (close as NSString).length

        let before = ns.substring(to: selection.location)
        let after = ns.substring(from: NSMaxRange(selection))
        let selected = ns.substring(with: selection)

        // Markers directly around the selection (or an empty pair around the cursor).
        if before.hasSuffix(open), after.hasPrefix(close) {
            let range = NSRange(location: selection.location - openLength, length: selection.length + openLength + closeLength)
            return TextEdit(range: range, replacement: selected, selection: NSRange(location: range.location, length: selection.length))
        }
        // Markers inside the selection.
        if selection.length >= openLength + closeLength, selected.hasPrefix(open), selected.hasSuffix(close) {
            let inner = (selected as NSString).substring(with: NSRange(location: openLength, length: selection.length - openLength - closeLength))
            return TextEdit(range: selection, replacement: inner, selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }
        return TextEdit(
            range: selection,
            replacement: open + selected + close,
            selection: NSRange(location: selection.location + openLength, length: selection.length)
        )
    }

    /// ⌘/: comments or uncomments the selected lines with `prefix` (`//`, or `#` in code).
    /// List markers stay in front of the comment.
    static func toggleComment(in text: String, selection: NSRange, prefix: String = "//") -> TextEdit? {
        var document = LineDocument(text)
        let range = document.lineIndexes(for: selection)
        var start = document.anchor(forOffset: selection.location)
        var end = document.anchor(forOffset: selection.upperBound)
        let marker = prefix + " "

        let candidates = range.filter { !document.lines[$0].item.isContentBlank || range.count == 1 }
        let allCommented = candidates.allSatisfy { index in
            document.lines[index].item.content.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }

        for index in candidates {
            var item = document.lines[index].item
            let lineID = document.lines[index].id
            if allCommented {
                let leading = item.content.prefix { $0 == " " || $0 == "\t" }
                var rest = item.content.dropFirst(leading.count)
                rest = rest.dropFirst(prefix.count)
                var removed = leading.count + prefix.count
                if rest.first == " " {
                    rest = rest.dropFirst()
                    removed += 1
                }
                item.content = String(leading) + rest
                shift(&start, &end, lineID: lineID, by: -removed, after: leading.count)
            } else {
                item.content = marker + item.content
                shift(&start, &end, lineID: lineID, by: (marker as NSString).length, after: 0)
            }
            document.lines[index].item = item
        }
        return document.edit(selecting: start, end)
    }

    private static func shift(_ start: inout LineDocument.Anchor, _ end: inout LineDocument.Anchor, lineID: Int, by delta: Int, after position: Int) {
        if start.lineID == lineID, start.contentOffset >= position { start.contentOffset = max(position, start.contentOffset + delta) }
        if end.lineID == lineID, end.contentOffset >= position { end.contentOffset = max(position, end.contentOffset + delta) }
    }
}
