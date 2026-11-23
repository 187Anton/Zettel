import Foundation
import Testing
@testable import Zettel

struct NumberExtractionTests {
    private func numbers(_ text: String, style: NumberStyle = .german) -> [Double] {
        NumberExtraction.numbers(in: text, style: style)
    }

    @Test(arguments: [
        ("Brot 2,50 €", [2.5]),
        ("Miete 800, Strom 60", [800, 60]),
        ("2 x Kaffee à 3,20", [2, 3.2]),
        ("Fernseher 1.299,00", [1299]),
        ("Rabatt -5", [-5]),
        ("(-2,5)", [-2.5]),
        ("19% MwSt", [19]),
        ("3kg Äpfel", [3]),
        ("Kein Betrag", []),
        ("", []),
        ("H2O und B12", []),
        ("Phase5 kostet 7", [7]),
        ("2-3 Stück", [2, 3]),
        (",5 Liter", [0.5]),
    ])
    func findsNumbers(text: String, expected: [Double]) {
        #expect(numbers(text) == expected)
    }

    @Test func englishStyle() {
        #expect(numbers("Total 1,299.50 and 3.5", style: .english) == [1299.5, 3.5])
    }
}

struct AggregateSheetTests {
    private func evaluate(_ keyword: Keyword, _ text: String, style: NumberStyle = .german) -> [Int: String] {
        AggregateSheet.evaluate(keyword, lines: text.components(separatedBy: "\n"), style: style).mapValues(\.text)
    }

    // MARK: sum

    @Test func sumAddsNumbersOfAllLines() {
        #expect(evaluate(.sum, "sum: Einkauf\nBrot 2,50\nMilch 1,20\nNotiz ohne Zahl") == [0: "3,7"])
    }

    @Test func sumAddsAllNumbersOfALine() {
        #expect(evaluate(.sum, "sum\nMiete 800 Strom 60\n40") == [0: "900"])
    }

    @Test func sumUsesResultOfEqualsLines() {
        #expect(evaluate(.sum, "sum\n3 * 2,50 =\nBrot 1") == [0: "8,5", 1: "7,5"])
    }

    @Test func sumIgnoresCommentsHeaderAndMarkers() {
        let text = "sum: 2025\n1. Brot 2\n☐ Milch 3\n• Käse 4\n// alt 100\n\t☑ Eier 1"
        #expect(evaluate(.sum, text) == [0: "10"])
    }

    @Test func sumWithLabelledCalculation() {
        #expect(evaluate(.sum, "sum\nKäse 3 * 1,99 =\nBrot 2") == [0: "7,97", 1: "5,97"])
    }

    @Test func sumWithErrorLine() {
        let annotations = AggregateSheet.evaluate(.sum, lines: ["sum", "1 / 0 =", "5"], style: .german)
        #expect(annotations[1] == LineAnnotation(text: "÷ 0", kind: .error))
        #expect(annotations[0] == LineAnnotation(text: "5", kind: .total))
    }

    @Test func emptySumIsZero() {
        #expect(evaluate(.sum, "sum") == [0: "0"])
    }

    // MARK: avg

    @Test func averageOfAllNumbers() {
        #expect(evaluate(.avg, "avg: Noten\n1\n2\n3, 6") == [0: "Ø 3"])
    }

    @Test func averageCountsEqualsResultAsOneValue() {
        #expect(evaluate(.avg, "avg\n2 + 2 =\n2") == [0: "Ø 3", 1: "4"])
    }

    @Test func averageWithoutNumbers() {
        #expect(evaluate(.avg, "avg\nText") == [0: "Ø –"])
    }

    // MARK: count

    @Test func countsEntriesLinesWordsCharacters() {
        let counts = AggregateSheet.counts(lines: ["count", "☐ Milch kaufen", "", "Brot", "// Kommentar", "", ""])
        #expect(counts == AggregateSheet.Counts(entries: 2, lines: 3, words: 3, characters: 16))
    }

    @Test func countText() {
        #expect(evaluate(.count, "count\nEin Wort") == [0: "1 Eintrag · 1 Zeile · 2 Wörter · 8 Zeichen"])
        #expect(evaluate(.count, "count") == [0: "0 Einträge · 0 Zeilen · 0 Wörter · 0 Zeichen"])
    }

    @Test func otherKeywordsHaveNoAggregate() {
        #expect(evaluate(.list, "list\n1") == [:])
    }
}

struct Phase5KeywordTests {
    @Test(arguments: [("sum: Einkauf", Keyword.sum), ("AVG", .avg), ("count", .count)])
    func parsesNewKeywords(line: String, keyword: Keyword) {
        #expect(KeywordHeader(line: line)?.keyword == keyword)
    }

    @Test func pickerOffersAllKeywordsInOrder() {
        #expect(Keyword.allCases == [.list, .math, .sum, .avg, .count])
    }
}
