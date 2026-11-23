import Foundation
import Testing
@testable import Zettel

/// Notation: `|` is the cursor, `«…»` a selection.
private func parse(_ marked: String) -> (String, NSRange) {
    var text = marked
    if let caret = text.range(of: "|") {
        let location = text.utf16.distance(from: text.startIndex, to: caret.lowerBound)
        text.removeSubrange(caret)
        return (text, NSRange(location: location, length: 0))
    }
    let open = text.range(of: "«")!
    let start = text.utf16.distance(from: text.startIndex, to: open.lowerBound)
    text.removeSubrange(open)
    let close = text.range(of: "»")!
    let end = text.utf16.distance(from: text.startIndex, to: close.lowerBound)
    text.removeSubrange(close)
    return (text, NSRange(location: start, length: end - start))
}

private func render(_ text: String, _ selection: NSRange) -> String {
    let ns = NSMutableString(string: text)
    if selection.length == 0 {
        ns.insert("|", at: selection.location)
    } else {
        ns.insert("»", at: selection.upperBound)
        ns.insert("«", at: selection.location)
    }
    return ns as String
}

/// Applies an operation and returns the marked result, or `nil` if it declined.
private func run(_ marked: String, _ operation: (String, NSRange) -> TextEdit?) -> String? {
    let (text, selection) = parse(marked)
    guard let edit = operation(text, selection) else { return nil }
    return render(edit.applied(to: text), edit.selection)
}

struct MarkdownShortcutTests {
    private func typeSpace(_ marked: String) -> String? {
        run(marked) { text, selection in ListEditing.markdownShortcut(in: text, cursor: selection.location) }
    }

    @Test(arguments: [
        ("[] |", "☐ |"),
        ("[ ] |", "☐ |"),
        ("- [ ] |", "☐ |"),
        ("[x] |", "☑ |"),
        ("- [x] |", "☑ |"),
        ("- |", "• |"),
        ("* |", "• |"),
        ("• [ ] |", "☐ |"),   // "- " became a bullet before "[ ] " was typed
        ("• [x] |", "☑ |"),
        ("☐ [x] |", "☑ |"),   // after Return continued a checklist
        ("\t- |", "\t• |"),
        ("Zeile\n[] |", "Zeile\n☐ |"),
        ("[] |Text dahinter", "☐ |Text dahinter"),
    ])
    func convertsAtLineStart(input: String, expected: String) {
        #expect(typeSpace(input) == expected)
    }

    @Test(arguments: ["Text - |", "a[] |", "1. |", "☐ - |", "-- |"])
    func ignoresOtherInput(input: String) {
        #expect(typeSpace(input) == nil)
    }
}

struct NewlineTests {
    private func enter(_ marked: String) -> String? {
        run(marked) { ListEditing.newline(in: $0, selection: $1) }
    }

    @Test(arguments: [
        ("☐ Milch|", "☐ Milch\n☐ |"),
        ("☑ Brot|", "☑ Brot\n☐ |"),           // new items start unchecked
        ("• Punkt|", "• Punkt\n• |"),
        ("1. Eins|", "1. Eins\n2. |"),
        ("\t☐ tief|", "\t☐ tief\n\t☐ |"),
        ("☐ Mil|ch", "☐ Mil\n☐ |ch"),
    ])
    func continuesList(input: String, expected: String) {
        #expect(enter(input) == expected)
    }

    @Test func emptyItemEndsList() {
        #expect(enter("☐ Milch\n☐ |") == "☐ Milch\n|")
    }

    @Test func emptyNestedItemOutdents() {
        #expect(enter("☐ Milch\n\t☐ |") == "☐ Milch\n☐ |")
    }

    @Test func renumbersFollowingItems() {
        #expect(enter("1. Eins|\n2. Zwei\n3. Drei") == "1. Eins\n2. |\n3. Zwei\n4. Drei")
    }

    @Test(arguments: ["Text|", "|☐ Milch", "☐ «Mil»ch"])
    func defaultBehaviorElsewhere(input: String) {
        #expect(enter(input) == nil)
    }
}

struct DeleteBackwardTests {
    @Test func removesMarkerDirectlyAfterIt() {
        #expect(run("☐ |Milch") { ListEditing.deleteBackward(in: $0, selection: $1) } == "|Milch")
        #expect(run("\t• |x") { ListEditing.deleteBackward(in: $0, selection: $1) } == "|x")
    }

    @Test func renumbersAfterRemovingNumber() {
        #expect(run("1. a\n2. |b\n3. c") { ListEditing.deleteBackward(in: $0, selection: $1) } == "1. a\n|b\n3. c")
    }

    @Test(arguments: ["☐ M|ilch", "Text|", "|☐ x"])
    func defaultBehaviorElsewhere(input: String) {
        #expect(run(input) { ListEditing.deleteBackward(in: $0, selection: $1) } == nil)
    }
}

struct IndentTests {
    private func tab(_ marked: String, outdent: Bool = false) -> String? {
        run(marked) { ListEditing.indent(in: $0, selection: $1, outdent: outdent) }
    }

    @Test func indentsListItemKeepingCursor() {
        #expect(tab("☐ Mil|ch") == "\t☐ Mil|ch")
        #expect(tab("\t☐ Mil|ch", outdent: true) == "☐ Mil|ch")
    }

    @Test func outdentAtLevelZeroDoesNothing() {
        #expect(tab("☐ x|", outdent: true) == nil)
    }

    @Test func plainLineWithTabInsertsNormalTab() {
        #expect(tab("Text|") == nil)
    }

    @Test func plainLineOutdentRemovesLeadingTab() {
        #expect(tab("\tText|", outdent: true) == "Text|")
    }

    @Test func indentsAllSelectedLines() {
        #expect(tab("«☐ a\n☐ b»") == "«\t☐ a\n\t☐ b»")
        #expect(tab("«Text\n☐ b»") == "«\tText\n\t☐ b»")
    }

    @Test func renumbersNestedNumbers() {
        #expect(tab("1. a\n2. |b\n3. c") == "1. a\n\t2. |b\n2. c")
    }
}

struct ToggleCheckTests {
    private func toggle(_ marked: String, _ behavior: CheckedItemBehavior = .keep) -> String? {
        run(marked) { ListEditing.toggleCheck(in: $0, selection: $1, behavior: behavior) }
    }

    @Test func togglesCheckbox() {
        #expect(toggle("☐ Mil|ch") == "☑ Mil|ch")
        #expect(toggle("☑ Mil|ch") == "☐ Mil|ch")
    }

    @Test func turnsOtherLinesIntoCheckboxes() {
        #expect(toggle("Mil|ch") == "☐ Mil|ch")
        #expect(toggle("• Mil|ch") == "☐ Mil|ch")
        #expect(toggle("\tMil|ch") == "\t☐ Mil|ch")
    }

    @Test func multipleLinesFollowFirstLine() {
        #expect(toggle("«☐ a\n☑ b»") == "«☑ a\n☑ b»")
        #expect(toggle("«☑ a\n☐ b»") == "«☐ a\n☐ b»")
        #expect(toggle("«a\n\nb»") == "«☐ a\n\n☐ b»")
    }

    @Test func moveToBottomMovesItemBehindItsSiblings() {
        #expect(toggle("☐ a|\n☐ b\n☐ c\nText", .moveToBottom) == "☐ b\n☐ c\n☑ a|\nText")
    }

    @Test func moveToBottomTakesChildrenAlong() {
        #expect(toggle("☐ a|\n\t☐ a1\n☐ b", .moveToBottom) == "☐ b\n☑ a|\n\t☐ a1")
    }

    @Test func moveToBottomStaysWithinParent() {
        #expect(toggle("☐ p\n\t☐ x|\n\t☐ y\n☐ q", .moveToBottom) == "☐ p\n\t☐ y\n\t☑ x|\n☐ q")
    }

    @Test func moveToBottomOnLastItemOnlyChecks() {
        #expect(toggle("☐ a\n☐ b|", .moveToBottom) == "☐ a\n☑ b|")
    }

    @Test func deleteRemovesCheckedLine() {
        #expect(toggle("☐ a\n☐ b|\n☐ c", .delete) == "☐ a\n☐ |c")
        #expect(toggle("☐ a|", .delete) == "|")
    }

    @Test func uncheckingIgnoresBehavior() {
        #expect(toggle("☑ a|\n☐ b", .moveToBottom) == "☐ a|\n☐ b")
        #expect(toggle("☑ a|\n☐ b", .delete) == "☐ a|\n☐ b")
    }

    @Test func clickTogglesLineAndKeepsSelection() {
        let (text, selection) = parse("☐ a\n☐ b|")
        let edit = ListEditing.toggleCheck(in: text, lineContaining: 0, selection: selection, behavior: .keep)
        #expect(edit.map { render($0.applied(to: text), $0.selection) } == "☑ a\n☐ b|")
    }

    @Test func detectsCheckboxSymbol() {
        let text = "Text ☐\n\t☐ a\n☑ b"
        #expect(!ListEditing.isCheckboxSymbol(in: text, at: 5))  // not at line start
        #expect(!ListEditing.isCheckboxSymbol(in: text, at: 7))  // the tab
        #expect(ListEditing.isCheckboxSymbol(in: text, at: 8))
        #expect(ListEditing.isCheckboxSymbol(in: text, at: 12))
        #expect(!ListEditing.isCheckboxSymbol(in: text, at: 14))
    }
}

struct CycleListTypeTests {
    private func cycle(_ marked: String) -> String? {
        run(marked) { ListEditing.cycleListType(in: $0, selection: $1) }
    }

    @Test func cyclesThroughTypes() {
        #expect(cycle("Mil|ch") == "• Mil|ch")
        #expect(cycle("• Mil|ch") == "☐ Mil|ch")
        #expect(cycle("☑ Mil|ch") == "1. Mil|ch")
        #expect(cycle("1. Mil|ch") == "Mil|ch")
    }

    @Test func keepsIndentation() {
        #expect(cycle("\t1. x|") == "\tx|")
        #expect(cycle("\tx|") == "\t• x|")
    }

    @Test func numbersSelectedLinesAndSkipsBlankLines() {
        #expect(cycle("«☐ a\n\n☐ b\n☐ c»") == "«1. a\n\n1. b\n2. c»")
    }
}

struct MoveLinesTests {
    private func move(_ marked: String, up: Bool) -> String? {
        run(marked) { ListEditing.moveLines(in: $0, selection: $1, up: up) }
    }

    @Test func movesLineUpAndDown() {
        #expect(move("a\nb|\nc", up: true) == "b|\na\nc")
        #expect(move("a\nb|\nc", up: false) == "a\nc\nb|")
    }

    @Test func stopsAtEdges() {
        #expect(move("a|\nb", up: true) == nil)
        #expect(move("a\nb|", up: false) == nil)
    }

    @Test func movesSelectedBlock() {
        #expect(move("x\n«a\nb»\ny", up: true) == "«a\nb»\nx\ny")
        #expect(move("x\n«a\nb»\ny", up: false) == "x\ny\n«a\nb»")
    }

    @Test func keepsCustomStartNumber() {
        #expect(run("5. a|") { ListEditing.newline(in: $0, selection: $1) } == "5. a\n6. |")
    }

    @Test func renumbersMovedNumberedItems() {
        #expect(move("1. a\n2. b|", up: true) == "1. b|\n2. a")
    }

    @Test func keepsCursorWithinMovedLine() {
        #expect(move("☐ eins\n☐ zw|ei", up: true) == "☐ zw|ei\n☐ eins")
    }
}

struct LineDocumentTests {
    @Test func editReplacesOnlyChangedLines() throws {
        var document = LineDocument("a\nb\nc")
        document.lines[1].item = .plain("B")
        let edit = try #require(document.edit(selecting: document.anchor(lineID: 1)))
        #expect(edit.range == NSRange(location: 2, length: 1))
        #expect(edit.replacement == "B")
        #expect(edit.applied(to: "a\nb\nc") == "a\nB\nc")
    }

    @Test func unchangedDocumentHasNoEdit() {
        let document = LineDocument("a\nb")
        #expect(document.edit(selecting: document.anchor(lineID: 0)) == nil)
    }

    @Test func handlesLineInsertionAndRemoval() throws {
        var document = LineDocument("a\nc")
        document.insert(.plain("b"), at: 1)
        #expect(try #require(document.edit(selecting: document.anchor(lineID: 0))).applied(to: "a\nc") == "a\nb\nc")

        var removal = LineDocument("a\nb\nc")
        removal.lines.remove(at: 0)
        #expect(try #require(removal.edit(selecting: removal.anchor(lineID: 1))).applied(to: "a\nb\nc") == "b\nc")
    }

    @Test func lineIndexesIgnoreSelectionEndingAtLineStart() {
        let document = LineDocument("a\nb\nc")
        #expect(document.lineIndexes(for: NSRange(location: 0, length: 2)) == 0...0)
        #expect(document.lineIndexes(for: NSRange(location: 0, length: 3)) == 0...1)
    }

    @Test func handlesEmojiOffsets() {
        #expect(run("☐ 🎉 Par|ty") { ListEditing.newline(in: $0, selection: $1) } == "☐ 🎉 Par\n☐ |ty")
    }
}
