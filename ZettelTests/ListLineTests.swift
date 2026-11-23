import Foundation
import Testing
@testable import Zettel

struct ListLineTests {
    @Test(arguments: [
        ("☐ Milch", ListLine(marker: .checkbox(checked: false), content: "Milch")),
        ("☑ Brot", ListLine(marker: .checkbox(checked: true), content: "Brot")),
        ("• Punkt", ListLine(marker: .bullet, content: "Punkt")),
        ("12. Schritt", ListLine(marker: .numbered(12), content: "Schritt")),
        ("\t\t☐ tief", ListLine(indent: 2, marker: .checkbox(checked: false), content: "tief")),
        ("☐ ", ListLine(marker: .checkbox(checked: false), content: "")),
    ])
    func parsesDisplayForm(line: String, expected: ListLine) {
        #expect(ListLine(display: line) == expected)
        #expect(ListLine(display: line).display == line)
    }

    @Test(arguments: ["Text", "", "  eingerückt", "\tTab", "☐kein Leerzeichen", "-5 Grad", "1.5 kg", "Hallo • Welt"])
    func plainLinesStayVerbatim(line: String) {
        let item = ListLine(display: line)
        #expect(item.marker == nil)
        #expect(item.display == line)
        #expect(ListLine(markdown: line).markdown == line)
    }

    @Test(arguments: [
        ("- [ ] Milch", ListLine(marker: .checkbox(checked: false), content: "Milch")),
        ("- [x] Brot", ListLine(marker: .checkbox(checked: true), content: "Brot")),
        ("- [X] Brot", ListLine(marker: .checkbox(checked: true), content: "Brot")),
        ("* [ ] Stern", ListLine(marker: .checkbox(checked: false), content: "Stern")),
        ("- Punkt", ListLine(marker: .bullet, content: "Punkt")),
        ("* Punkt", ListLine(marker: .bullet, content: "Punkt")),
        ("3. Drei", ListLine(marker: .numbered(3), content: "Drei")),
        ("\t- [ ] Tab", ListLine(indent: 1, marker: .checkbox(checked: false), content: "Tab")),
        ("    - Vier Leerzeichen", ListLine(indent: 2, marker: .bullet, content: "Vier Leerzeichen")),
    ])
    func parsesMarkdown(line: String, expected: ListLine) {
        #expect(ListLine(markdown: line) == expected)
    }

    @Test func writesCanonicalMarkdown() {
        #expect(ListLine(indent: 1, marker: .checkbox(checked: true), content: "x").markdown == "\t- [x] x")
        #expect(ListLine(marker: .checkbox(checked: false), content: "").markdown == "- [ ] ")
        #expect(ListLine(marker: .bullet, content: "b").markdown == "- b")
        #expect(ListLine(marker: .numbered(7), content: "n").markdown == "7. n")
    }

    @Test func noteRoundTrip() {
        let markdown = "Einkauf\n- [ ] Milch\n\t- [x] Hafermilch\n- Notiz\n1. Eins\n2. Zwei\n\nEnde"
        let display = "Einkauf\n☐ Milch\n\t☑ Hafermilch\n• Notiz\n1. Eins\n2. Zwei\n\nEnde"
        #expect(NoteFormat.display(fromMarkdown: markdown) == display)
        #expect(NoteFormat.markdown(fromDisplay: display) == markdown)
    }

    @Test func plainIndentIsNeverAppliedToPlainLines() {
        #expect(ListLine(indent: 3, marker: nil, content: "x").display == "x")
    }

    @Test func indentIsClamped() {
        #expect(ListLine(indent: 99, marker: .bullet, content: "").indent == ListLine.maxIndent)
    }

    @Test func detectsCheckboxMarkerQuickly() {
        let text = "☐ a\n\t☑ b\nx ☐ c\n☐x" as NSString
        #expect(ListLine.isCheckboxMarker(in: text, at: 0))
        #expect(ListLine.isCheckboxMarker(in: text, at: 5))
        #expect(!ListLine.isCheckboxMarker(in: text, at: 11))  // not at line start
        #expect(!ListLine.isCheckboxMarker(in: text, at: 15))  // no space after
    }
}
