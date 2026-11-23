import Foundation

/// What happens to a checklist item when it gets checked.
enum CheckedItemBehavior: String, CaseIterable, Sendable {
    /// Stays where it is (crossed out).
    case keep
    /// Moves to the end of its list (with its sub-items).
    case moveToBottom
    /// Is removed (undo brings it back).
    case delete
}

/// List operations on the editor's display text. Pure functions: each returns the
/// edit to apply, or `nil` when the editor's default behavior should run.
enum ListEditing {
    // MARK: Markdown shortcuts

    /// Called right after a space was typed. Turns `[] `, `[x] `, `- [ ] `, `- `, … at
    /// the start of a line into the list marker.
    static func markdownShortcut(in text: String, cursor: Int) -> TextEdit? {
        var document = LineDocument(text)
        let (index, column) = document.location(ofOffset: cursor)
        let line = document.originalLines[index] as NSString
        guard column <= line.length,
              let (indent, marker) = shortcutMarker(forTypedPrefix: line.substring(to: column))
        else { return nil }

        let item = ListLine(indent: indent, marker: marker, content: line.substring(from: column))
        guard item.display != line as String else { return nil } // e.g. "1. " is already final
        document.lines[index].item = item
        document.renumberLists(around: index...index)
        return document.edit(selecting: document.anchor(lineID: document.lines[index].id))
    }

    static func shortcutMarker(forTypedPrefix prefix: String) -> (indent: Int, marker: ListLine.Marker)? {
        let (tabs, rest) = ListLine.splitLeadingTabs(prefix)
        switch rest {
        // "• …", "☐ …", "☑ …": the line already got a marker from an earlier
        // shortcut or from Return continuing a list.
        case "[] ", "[ ] ", "- [ ] ", "- [] ", "* [ ] ", "• [] ", "• [ ] ", "☑ [] ", "☑ [ ] ":
            return (tabs, .checkbox(checked: false))
        case "[x] ", "[X] ", "- [x] ", "- [X] ", "* [x] ", "• [x] ", "• [X] ", "☐ [x] ", "☐ [X] ":
            return (tabs, .checkbox(checked: true))
        case "- ", "* ":
            return (tabs, .bullet)
        default:
            if let (number, content) = ListLine.splitNumber(rest), content.isEmpty {
                return (tabs, .numbered(number))
            }
            return nil
        }
    }

    // MARK: Return, Backspace, Tab

    /// Return inside a list item continues the list. On an empty item it ends the
    /// list (or outdents a nested item). In a `list` note, Return on the header or
    /// on a plain line with text also starts a checkbox.
    static func newline(in text: String, selection: NSRange, listMode: Bool = false) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        var document = LineDocument(text)
        let (index, column) = document.location(ofOffset: selection.location)
        let item = document.lines[index].item
        let lineID = document.lines[index].id

        if listMode, !item.isListItem, index == 0 || !(item.isContentBlank || item.content.hasPrefix("//")) {
            let content = item.content as NSString
            let split = min(column, content.length)
            document.lines[index].item = .plain(content.substring(to: split))
            let newID = document.insert(
                ListLine(marker: .checkbox(checked: false), content: content.substring(from: split)),
                at: index + 1
            )
            return document.edit(selecting: document.anchor(lineID: newID))
        }

        guard let marker = item.marker, column >= item.displayMarkerLength else { return nil }

        if item.isContentBlank {
            document.lines[index].item = item.indent > 0
                ? ListLine(indent: item.indent - 1, marker: marker, content: item.content)
                : .plain("")
            document.renumberLists(around: index...index)
            return document.edit(selecting: document.anchor(lineID: lineID))
        }

        let content = item.content as NSString
        let split = min(column - item.displayMarkerLength, content.length)
        document.lines[index].item.content = content.substring(to: split)
        let nextMarker: ListLine.Marker = switch marker {
        case .bullet: .bullet
        case .checkbox: .checkbox(checked: false)
        case .numbered(let number): .numbered(number + 1)
        }
        let newID = document.insert(
            ListLine(indent: item.indent, marker: nextMarker, content: content.substring(from: split)),
            at: index + 1
        )
        document.renumberLists(around: index...(index + 1))
        return document.edit(selecting: document.anchor(lineID: newID))
    }

    // MARK: list mode

    /// In a `list` note, typing the first character into an empty line (below the
    /// header) makes it a checkbox. Called *instead of* inserting the character.
    static func listModeInsertion(in text: String, selection: NSRange, inserted: String) -> TextEdit? {
        guard selection.length == 0, inserted.count == 1,
              let character = inserted.first, !character.isWhitespace, !character.isNewline, character != "/"
        else { return nil }
        var document = LineDocument(text)
        let (index, _) = document.location(ofOffset: selection.location)
        guard index > 0, document.originalLines[index].isEmpty else { return nil }

        let lineID = document.lines[index].id
        document.lines[index].item = ListLine(marker: .checkbox(checked: false), content: inserted)
        return document.edit(selecting: document.anchor(lineID: lineID, contentOffset: inserted.utf16.count))
    }

    /// In a `list` note, `/x` typed at the end of a checkbox line checks it
    /// (and `/x` on a checked line unchecks it). Called after the `x` was inserted.
    static func slashToggle(in text: String, cursor: Int, behavior: CheckedItemBehavior) -> TextEdit? {
        var document = LineDocument(text)
        let (index, column) = document.location(ofOffset: cursor)
        let item = document.lines[index].item
        guard item.isCheckbox, column == document.originalLines[index].utf16.count,
              item.content.lowercased().hasSuffix("/x")
        else { return nil }

        var content = item.content
        content.removeLast(2)
        while content.last?.isWhitespace == true { content.removeLast() }
        document.lines[index].item.content = content
        let selection = NSRange(location: cursor, length: 0)
        return toggleCheck(document, lines: index...index, selection: selection, behavior: behavior)
    }

    /// Backspace directly after a list marker removes the marker.
    static func deleteBackward(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        var document = LineDocument(text)
        let (index, column) = document.location(ofOffset: selection.location)
        let item = document.lines[index].item
        guard item.isListItem, column > 0, column == item.displayMarkerLength else { return nil }

        let lineID = document.lines[index].id
        document.lines[index].item = .plain(item.content)
        document.renumberLists(around: index...index)
        return document.edit(selecting: document.anchor(lineID: lineID))
    }

    /// Tab / ⇧Tab. Changes the level of list items; for several selected lines
    /// also indents plain lines. Returns `nil` for a plain single line with Tab
    /// (a normal tab character is inserted then).
    static func indent(in text: String, selection: NSRange, outdent: Bool) -> TextEdit? {
        var document = LineDocument(text)
        let range = document.lineIndexes(for: selection)
        if range.count == 1, !document.lines[range.lowerBound].item.isListItem, !outdent {
            return nil
        }

        var start = document.anchor(forOffset: selection.location)
        var end = document.anchor(forOffset: selection.upperBound)
        for index in range {
            var item = document.lines[index].item
            if item.isListItem {
                item.indent = min(max(item.indent + (outdent ? -1 : 1), 0), ListLine.maxIndent)
            } else if outdent {
                guard item.content.hasPrefix("\t") else { continue }
                item.content.removeFirst()
                shift(&start, &end, lineID: document.lines[index].id, by: -1)
            } else {
                item.content = "\t" + item.content
                shift(&start, &end, lineID: document.lines[index].id, by: 1)
            }
            document.lines[index].item = item
        }
        document.renumberLists(around: range)
        return document.edit(selecting: start, end)
    }

    // MARK: Checkboxes

    /// ⌘⇧K. If all selected lines are checkboxes, toggles them (state of the first
    /// line decides). Otherwise turns the selected lines into open checkboxes.
    static func toggleCheck(in text: String, selection: NSRange, behavior: CheckedItemBehavior) -> TextEdit? {
        let document = LineDocument(text)
        return toggleCheck(document, lines: document.lineIndexes(for: selection), selection: selection, behavior: behavior)
    }

    /// Click on a checkbox: toggles that line and keeps the selection.
    static func toggleCheck(in text: String, lineContaining offset: Int, selection: NSRange, behavior: CheckedItemBehavior) -> TextEdit? {
        let document = LineDocument(text)
        let line = document.location(ofOffset: offset).line
        return toggleCheck(document, lines: line...line, selection: selection, behavior: behavior)
    }

    /// `true` if `offset` points at the ☐/☑ symbol of a checklist item.
    static func isCheckboxSymbol(in text: String, at offset: Int) -> Bool {
        let document = LineDocument(text)
        let (index, column) = document.location(ofOffset: offset)
        let item = document.lines[index].item
        return item.isCheckbox && column == item.indent
            && column < document.originalLines[index].utf16.count
    }

    private static func toggleCheck(
        _ document: LineDocument,
        lines range: ClosedRange<Int>,
        selection: NSRange,
        behavior: CheckedItemBehavior
    ) -> TextEdit? {
        var document = document
        var start = document.anchor(forOffset: selection.location)
        var end = document.anchor(forOffset: selection.upperBound)
        let items = range.map { document.lines[$0].item }
        var newlyChecked: [Int] = []

        if items.allSatisfy(\.isCheckbox) {
            let target = !items[0].isChecked
            for index in range {
                document.lines[index].item.marker = .checkbox(checked: target)
                if target { newlyChecked.append(document.lines[index].id) }
            }
        } else {
            for index in range {
                let item = document.lines[index].item
                guard !item.isCheckbox, range.count == 1 || !item.isContentBlank else { continue }
                let (converted, shiftBy) = convert(item, to: .checkbox(checked: false))
                document.lines[index].item = converted
                shift(&start, &end, lineID: document.lines[index].id, by: shiftBy)
            }
        }

        switch behavior {
        case .keep:
            break
        case .delete:
            document.lines.removeAll { newlyChecked.contains($0.id) }
            if document.lines.isEmpty { document.insert(.plain(""), at: 0) }
        case .moveToBottom:
            for id in newlyChecked.reversed() {
                moveSubtreeToEndOfList(&document, lineID: id)
            }
        }

        let lower = min(range.lowerBound, document.lines.count - 1)
        document.renumberLists(around: lower...max(lower, min(range.upperBound, document.lines.count - 1)))
        return document.edit(selecting: start, end)
    }

    /// Moves an item and its deeper-indented children behind the last sibling.
    private static func moveSubtreeToEndOfList(_ document: inout LineDocument, lineID: Int) {
        guard let first = document.index(ofLineID: lineID) else { return }
        let level = document.lines[first].item.indent
        let lines = document.lines

        var last = first
        while last + 1 < lines.count, lines[last + 1].item.isListItem, lines[last + 1].item.indent > level {
            last += 1
        }
        var end = last
        while end + 1 < lines.count, lines[end + 1].item.isListItem, lines[end + 1].item.indent >= level {
            end += 1
        }
        guard end > last else { return }

        let subtree = Array(lines[first...last])
        document.lines.removeSubrange(first...last)
        document.lines.insert(contentsOf: subtree, at: end - subtree.count + 1)
    }

    // MARK: List type

    /// ⌘⇧M. Cycles the selected lines: text → • → ☐ → 1. → text.
    static func cycleListType(in text: String, selection: NSRange) -> TextEdit? {
        var document = LineDocument(text)
        let range = document.lineIndexes(for: selection)
        var start = document.anchor(forOffset: selection.location)
        var end = document.anchor(forOffset: selection.upperBound)

        let next: ListLine.Marker? = switch document.lines[range.lowerBound].item.marker {
        case nil: .bullet
        case .bullet: .checkbox(checked: false)
        case .checkbox: .numbered(1)
        case .numbered: nil
        }

        for index in range {
            let item = document.lines[index].item
            guard range.count == 1 || !item.isContentBlank else { continue }
            // Numbers are assigned by renumbering below.
            let (converted, shiftBy) = convert(item, to: next)
            document.lines[index].item = converted
            shift(&start, &end, lineID: document.lines[index].id, by: shiftBy)
        }
        document.renumberLists(around: range)
        return document.edit(selecting: start, end)
    }

    /// Changes a line's marker. Leading tabs of plain lines become the indent
    /// and vice versa, so cycling back and forth keeps the structure.
    /// Also returns how far content offsets move (tabs added to / taken from the content).
    private static func convert(_ item: ListLine, to marker: ListLine.Marker?) -> (ListLine, contentShift: Int) {
        if item.isListItem {
            guard let marker else {
                return (.plain(String(repeating: "\t", count: item.indent) + item.content), item.indent)
            }
            return (ListLine(indent: item.indent, marker: marker, content: item.content), 0)
        }
        guard let marker else { return (item, 0) }
        let (tabs, rest) = ListLine.splitLeadingTabs(item.content)
        return (ListLine(indent: tabs, marker: marker, content: String(rest)), -tabs)
    }

    // MARK: Moving lines

    /// ⌥↑ / ⌥↓. Moves the selected lines one line up or down.
    static func moveLines(in text: String, selection: NSRange, up: Bool) -> TextEdit? {
        var document = LineDocument(text)
        let range = document.lineIndexes(for: selection)
        let start = document.anchor(forOffset: selection.location)
        let end = document.anchor(forOffset: selection.upperBound)

        if up {
            guard range.lowerBound > 0 else { return nil }
            let line = document.lines.remove(at: range.lowerBound - 1)
            document.lines.insert(line, at: range.upperBound)
        } else {
            guard range.upperBound < document.lines.count - 1 else { return nil }
            let line = document.lines.remove(at: range.upperBound + 1)
            document.lines.insert(line, at: range.lowerBound)
        }
        let lower = max(0, range.lowerBound - 1)
        document.renumberLists(around: lower...min(document.lines.count - 1, range.upperBound + 1))
        return document.edit(selecting: start, end)
    }

    // MARK: Helpers

    /// Moves anchors on a line whose content gained or lost leading characters.
    /// Anchors at the very start of the line stay there.
    private static func shift(_ start: inout LineDocument.Anchor, _ end: inout LineDocument.Anchor, lineID: Int, by delta: Int) {
        if start.lineID == lineID, start.contentOffset != LineDocument.Anchor.lineStart {
            start.contentOffset = max(0, start.contentOffset + delta)
        }
        if end.lineID == lineID, end.contentOffset != LineDocument.Anchor.lineStart {
            end.contentOffset = max(0, end.contentOffset + delta)
        }
    }
}
