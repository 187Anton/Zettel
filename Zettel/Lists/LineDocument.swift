import Foundation

/// A text change for the editor: replace `range` with `replacement`, then select
/// `selection` (in coordinates of the resulting text). All offsets are UTF-16.
struct TextEdit: Equatable, Sendable {
    var range: NSRange
    var replacement: String
    var selection: NSRange

    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Mutable line-based view on a display text, used by the list operations.
///
/// Lines keep an identity while being moved, so cursor positions can follow them.
/// `edit(…)` turns the changes into one minimal `TextEdit` (one undo step).
struct LineDocument {
    struct Line {
        let id: Int
        var item: ListLine
    }

    /// A cursor position attached to a line's content, robust against marker changes.
    struct Anchor: Equatable {
        static let lineStart = -1

        var lineID: Int
        /// Offset into the line's content, or `lineStart` for the very start of the line.
        var contentOffset: Int
        /// Line index to use if the line was removed.
        var fallbackIndex: Int
    }

    let originalLines: [String]
    var lines: [Line]
    private var nextID: Int

    init(_ text: String) {
        originalLines = text.components(separatedBy: "\n")
        lines = originalLines.enumerated().map { Line(id: $0.offset, item: ListLine(display: $0.element)) }
        nextID = originalLines.count
    }

    // MARK: Positions in the original text

    func location(ofOffset offset: Int) -> (line: Int, column: Int) {
        var start = 0
        for (index, line) in originalLines.enumerated() {
            let length = line.utf16.count
            if offset <= start + length {
                return (index, max(0, offset - start))
            }
            start += length + 1
        }
        let last = originalLines.count - 1
        return (last, originalLines[last].utf16.count)
    }

    /// Lines touched by a selection. A selection ending at the very start of a
    /// line (after selecting whole lines) does not include that line.
    func lineIndexes(for selection: NSRange) -> ClosedRange<Int> {
        let first = location(ofOffset: selection.location).line
        guard selection.length > 0 else { return first...first }
        let end = location(ofOffset: selection.upperBound)
        let last = (end.line > first && end.column == 0) ? end.line - 1 : end.line
        return first...last
    }

    /// Must be called before the lines are changed.
    func anchor(forOffset offset: Int) -> Anchor {
        let (line, column) = location(ofOffset: offset)
        let item = lines[line].item
        return Anchor(
            lineID: lines[line].id,
            contentOffset: column == 0 ? Anchor.lineStart : max(0, column - item.displayMarkerLength),
            fallbackIndex: line
        )
    }

    func anchor(lineID: Int, contentOffset: Int = 0) -> Anchor {
        Anchor(lineID: lineID, contentOffset: contentOffset, fallbackIndex: index(ofLineID: lineID) ?? 0)
    }

    // MARK: Changes

    func index(ofLineID id: Int) -> Int? {
        lines.firstIndex { $0.id == id }
    }

    @discardableResult
    mutating func insert(_ item: ListLine, at index: Int) -> Int {
        let id = nextID
        nextID += 1
        lines.insert(Line(id: id, item: item), at: index)
        return id
    }

    /// Fixes the numbers of numbered items in all lists around the given lines.
    /// Each level counts on from its first item; other items break the sequence.
    mutating func renumberLists(around indexes: ClosedRange<Int>) {
        guard !lines.isEmpty else { return }
        let lower = max(0, indexes.lowerBound - 1)
        let upper = min(lines.count - 1, indexes.upperBound + 1)
        guard lower <= upper else { return }

        var index = 0
        while index < lines.count {
            guard lines[index].item.isListItem else {
                index += 1
                continue
            }
            var end = index
            while end + 1 < lines.count, lines[end + 1].item.isListItem { end += 1 }
            if index <= upper, end >= lower {
                renumberRun(index...end)
            }
            index = end + 1
        }
    }

    /// Numbered items on the same level form a sequence until a shallower item
    /// or a different marker interrupts it. Each sequence counts up from its
    /// smallest number, so moving items keeps a custom start (e.g. `5.`).
    private mutating func renumberRun(_ run: ClosedRange<Int>) {
        var sequences: [[Int]] = []
        var active: [Int: Int] = [:] // level → index in `sequences`
        for index in run {
            let level = lines[index].item.indent
            active = active.filter { $0.key <= level }
            if case .numbered = lines[index].item.marker {
                if let sequence = active[level] {
                    sequences[sequence].append(index)
                } else {
                    active[level] = sequences.count
                    sequences.append([index])
                }
            } else {
                active[level] = nil
            }
        }
        for sequence in sequences {
            let numbers = sequence.compactMap { index -> Int? in
                if case .numbered(let number) = lines[index].item.marker { return number }
                return nil
            }
            let start = numbers.min() ?? 1
            for (offset, index) in sequence.enumerated() {
                lines[index].item.marker = .numbered(start + offset)
            }
        }
    }

    // MARK: Result

    func offset(for anchor: Anchor) -> Int {
        let existing = index(ofLineID: anchor.lineID)
        let index = existing ?? min(anchor.fallbackIndex, lines.count - 1)
        var offset = 0
        for i in 0..<index {
            offset += lines[i].item.display.utf16.count + 1
        }
        let item = lines[index].item
        if existing != nil, anchor.contentOffset == Anchor.lineStart {
            return offset
        }
        let contentOffset = existing == nil ? 0 : anchor.contentOffset
        return offset + item.displayMarkerLength + min(contentOffset, item.content.utf16.count)
    }

    /// The change as a single replacement of the changed lines, or `nil` if the
    /// text is unchanged.
    func edit(selecting start: Anchor, _ end: Anchor? = nil) -> TextEdit? {
        let new = lines.map(\.item.display)
        let old = originalLines
        guard new != old, !new.isEmpty else { return nil }

        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        // Replace at least one whole line on both sides so newlines stay balanced.
        if prefix + suffix == old.count || prefix + suffix == new.count {
            if prefix > 0 { prefix -= 1 } else { suffix -= 1 }
        }

        let oldChanged = old[prefix..<(old.count - suffix)]
        let newChanged = new[prefix..<(new.count - suffix)]
        let location = old[..<prefix].reduce(0) { $0 + $1.utf16.count + 1 }
        let length = oldChanged.reduce(0) { $0 + $1.utf16.count } + oldChanged.count - 1

        let a = offset(for: start)
        let b = end.map(offset(for:)) ?? a
        return TextEdit(
            range: NSRange(location: location, length: length),
            replacement: newChanged.joined(separator: "\n"),
            selection: NSRange(location: min(a, b), length: abs(b - a))
        )
    }
}
