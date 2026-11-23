import Foundation
import Testing
@testable import Zettel

struct MathSheetTests {
    private func results(_ text: String, style: NumberStyle = .german) -> [Int: String] {
        MathSheet.evaluate(lines: text.components(separatedBy: "\n"), from: 1, style: style)
            .mapValues(\.text)
    }

    @Test func showsResultsOnlyForLinesEndingWithEquals() {
        #expect(results("math\n1 + 2 =\n3 * 3\nText\n10 / 4 =") == [1: "3", 4: "2,5"])
    }

    @Test func headerIsNotEvaluated() {
        #expect(results("math: Budget =\n2 =") == [1: "2"])
    }

    @Test func variables() {
        #expect(results("math\npreis : 25\npreis * 3 =") == [2: "75"])
        #expect(results("math\nPreis: 25\nmenge: 4\npreis * menge =") == [3: "100"])
    }

    @Test func variableCanBeRedefined() {
        #expect(results("math\na : 1\na =\na : 2\na =") == [2: "1", 4: "2"])
    }

    @Test func variablesOnlyFromLinesAbove() {
        #expect(results("math\nb * 2 =\nb : 3") == [1: "b?"])
    }

    @Test func assignmentWithEqualsShowsValue() {
        #expect(results("math\nmwst : 19% =\n100 + mwst =") == [1: "0,19", 2: "100,19"])
    }

    @Test func ansIsNearestResultAbove() {
        #expect(results("math\n10 =\nans * 2 =\nText\nans + 1 =") == [1: "10", 2: "20", 4: "21"])
        #expect(results("math\nans =") == [1: "ans?"])
    }

    @Test func totalSumsResultsExceptEarlierTotals() {
        let text = "math\n10 =\n20 =\ntotal =\n5 =\nTotal ="
        #expect(results(text) == [1: "10", 2: "20", 3: "30", 4: "5", 5: "35"])
    }

    @Test func totalWithoutResultsIsZero() {
        #expect(results("math\ntotal =") == [1: "0"])
    }

    @Test func ansAfterTotalIsTheTotal() {
        #expect(results("math\n2 =\n3 =\ntotal =\nans * 2 =") == [1: "2", 2: "3", 3: "5", 4: "10"])
    }

    @Test func commentsAndBlankLinesAreIgnored() {
        #expect(results("math\n// 1 + 1 =\n\n2 =") == [3: "2"])
    }

    @Test func listItemsAreEvaluated() {
        #expect(results("math\n• 1 + 1 =\n☐ ans * 3 =") == [1: "2", 2: "6"])
    }

    @Test func labelsBeforeCalculations() {
        #expect(results("math\nEssen pro Tag 35 * 7 =\nans + 10% =") == [1: "245", 2: "269,5"])
    }

    @Test func errorsAreShownShort() {
        let annotations = MathSheet.evaluate(lines: ["math", "1 / 0 =", "x =", "1 + =", "a : 1 +"], from: 1, style: .german)
        #expect(annotations[1] == LineAnnotation(text: "÷ 0", kind: .error))
        #expect(annotations[2] == LineAnnotation(text: "x?", kind: .error))
        #expect(annotations[3] == LineAnnotation(text: "?", kind: .error))
        #expect(annotations[4] == nil) // unfinished definition stays quiet
    }

    @Test func respectsNumberStyle() {
        let style = NumberStyle(decimalSeparator: ".", groupingSeparator: ",", decimals: 2)
        #expect(results("math\n1,000 * 1.5 =", style: style) == [1: "1,500.00"])
    }

    @Test(arguments: [
        ("preis : 25", "preis", " 25"), ("a:1", "a", "1"), ("größe : 2", "größe", " 2"),
    ])
    func splitsAssignments(text: String, name: String, expression: String) throws {
        let split = try #require(MathSheet.splitAssignment(text))
        #expect(split.name == name)
        #expect(split.expression == expression)
    }

    @Test(arguments: ["10 : 2", "zwei worte : 3", "ans : 3", "total : 1", ": 3", "1a : 2"])
    func rejectsNonAssignments(text: String) {
        #expect(MathSheet.splitAssignment(text) == nil)
    }
}

struct KeywordTests {
    @Test(arguments: [
        ("math", KeywordHeader(keyword: .math, title: nil)),
        ("Math", KeywordHeader(keyword: .math, title: nil)),
        ("math: Budget", KeywordHeader(keyword: .math, title: "Budget")),
        ("  list :  Einkauf ", KeywordHeader(keyword: .list, title: "Einkauf")),
        ("list:", KeywordHeader(keyword: .list, title: nil)),
    ])
    func parsesHeaders(line: String, expected: KeywordHeader) {
        #expect(KeywordHeader(line: line) == expected)
    }

    @Test(arguments: ["", "mathe", "Budget: math", "math stuff", "• math"])
    func rejectsOtherLines(line: String) {
        #expect(KeywordHeader(line: line) == nil)
    }

    @Test func headerOfText() {
        #expect(KeywordHeader(text: "list\n☐ a")?.keyword == .list)
        #expect(KeywordHeader(text: "Text\nmath") == nil)
    }

    @Test func formatsHeaderLine() {
        #expect(KeywordHeader(keyword: .math, title: "Budget").line == "math: Budget")
        #expect(KeywordHeader(keyword: .list, title: nil).line == "list")
    }
}

struct KeywordEditingTests {
    private func apply(_ keyword: Keyword, _ text: String) -> (String, Int)? {
        let slash = (text as NSString).range(of: "/").location
        guard let edit = KeywordEditing.apply(keyword, in: text, slashLocation: slash) else { return nil }
        return (edit.applied(to: text), edit.selection.location)
    }

    @Test func slashOnEmptyNoteBecomesHeader() throws {
        let (text, cursor) = try #require(apply(.math, "/"))
        #expect(text == "math")
        #expect(cursor == 4)
    }

    @Test func replacesExistingKeywordKeepingTitle() throws {
        let (text, _) = try #require(apply(.list, "math: Budget\n/"))
        #expect(text == "list: Budget\n")
    }

    @Test func insertsHeaderAboveContent() throws {
        let (text, cursor) = try #require(apply(.math, "Notiz\n1 + 1 =\n/"))
        #expect(text == "math\nNotiz\n1 + 1 =\n")
        #expect(cursor == (text as NSString).length)
    }

    @Test func listConvertsPlainLines() throws {
        let (text, _) = try #require(apply(.list, "/\nMilch\n\n// Kommentar\n☑ Brot\n• Butter"))
        #expect(text == "list\n☐ Milch\n\n// Kommentar\n☑ Brot\n• Butter")
    }

    @Test func sameKeywordStillRemovesSlash() throws {
        let (text, _) = try #require(apply(.math, "math\n/"))
        #expect(text == "math\n")
    }

    @Test func requiresSlashAtLocation() {
        #expect(KeywordEditing.apply(.math, in: "abc", slashLocation: 1) == nil)
    }
}

struct ListModeTests {
    @Test func returnOnHeaderStartsCheckbox() throws {
        let edit = try #require(ListEditing.newline(in: "list", selection: NSRange(location: 4, length: 0), listMode: true))
        #expect(edit.applied(to: "list") == "list\n☐ ")
        #expect(edit.selection.location == 7)
    }

    @Test func returnOnPlainLineWithTextStartsCheckbox() throws {
        let text = "list\nMilch"
        let edit = try #require(ListEditing.newline(in: text, selection: NSRange(location: 10, length: 0), listMode: true))
        #expect(edit.applied(to: text) == "list\nMilch\n☐ ")
    }

    @Test func returnOnBlankLineIsNormal() {
        #expect(ListEditing.newline(in: "list\n☐ a\n", selection: NSRange(location: 9, length: 0), listMode: true) == nil)
    }

    @Test func returnOutsideListModeIsUnchanged() {
        #expect(ListEditing.newline(in: "Text", selection: NSRange(location: 4, length: 0)) == nil)
    }

    @Test func typingIntoEmptyLineMakesCheckbox() throws {
        let text = "list\n☐ a\n"
        let edit = try #require(ListEditing.listModeInsertion(in: text, selection: NSRange(location: 9, length: 0), inserted: "M"))
        #expect(edit.applied(to: text) == "list\n☐ a\n☐ M")
        #expect(edit.selection.location == 12)
    }

    @Test(arguments: [" ", "/", "\n"])
    func someCharactersStayPlain(inserted: String) {
        #expect(ListEditing.listModeInsertion(in: "list\n", selection: NSRange(location: 5, length: 0), inserted: inserted) == nil)
    }

    @Test func headerLineIsNeverConverted() {
        #expect(ListEditing.listModeInsertion(in: "", selection: NSRange(location: 0, length: 0), inserted: "l") == nil)
    }

    @Test func slashXChecksItem() throws {
        let text = "list\n☐ Milch /x"
        let edit = try #require(ListEditing.slashToggle(in: text, cursor: (text as NSString).length, behavior: .keep))
        let result = edit.applied(to: text)
        #expect(result == "list\n☑ Milch")
        #expect(edit.selection.location == (result as NSString).length)
    }

    @Test func slashXRespectsBehavior() throws {
        let text = "list\n☐ a/x\n☐ b"
        let edit = try #require(ListEditing.slashToggle(in: text, cursor: 10, behavior: .moveToBottom))
        #expect(edit.applied(to: text) == "list\n☐ b\n☑ a")
    }

    @Test func slashXOnlyAtEndOfCheckbox() {
        #expect(ListEditing.slashToggle(in: "list\nText /x", cursor: 12, behavior: .keep) == nil)
        #expect(ListEditing.slashToggle(in: "list\n☐ a/x b", cursor: 10, behavior: .keep) == nil)
    }
}
