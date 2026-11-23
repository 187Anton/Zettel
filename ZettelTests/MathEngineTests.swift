import Foundation
import Testing
@testable import Zettel

struct MathEngineTests {
    private func eval(_ input: String, _ variables: [String: Double] = [:], style: NumberStyle = .german) throws -> Double {
        try MathEngine.evaluate(input, variables: variables, style: style)
    }

    private func error(_ input: String, _ variables: [String: Double] = [:]) -> MathError? {
        do {
            _ = try MathEngine.evaluate(input, variables: variables, style: .german)
            return nil
        } catch {
            return error
        }
    }

    // MARK: Operators

    @Test(arguments: [
        ("1 + 2", 3.0), ("7 - 10", -3), ("6 * 7", 42), ("1 / 4", 0.25), ("2 ^ 10", 1024),
        ("2 + 3 * 4", 14), ("(2 + 3) * 4", 20), ("10 - 4 - 3", 3), ("100 / 10 / 2", 5),
        ("2 ^ 3 ^ 2", 512), ("-2 ^ 2", -4), ("2 ^ -1", 0.5), ("--3", 3), ("+5", 5),
        ("-(2 + 3)", -5), ("((1))", 1), ("3 × 4", 12), ("12 ÷ 4", 3), ("12 : 4", 3), ("2·3", 6),
        ("8 − 3", 5),
    ])
    func arithmetic(input: String, expected: Double) throws {
        #expect(try eval(input) == expected)
    }

    // MARK: Numbers

    @Test(arguments: [
        ("3,5", 3.5), ("3.5", 3.5), (",5", 0.5), ("1.000", 1000), ("1.000.000", 1_000_000),
        ("1.234,56", 1234.56), ("1.0000", 1.0), ("12", 12),
    ])
    func germanNumbers(input: String, expected: Double) throws {
        #expect(try eval(input) == expected)
    }

    @Test(arguments: [("1,000", 1000.0), ("1,234.5", 1234.5), ("3.5", 3.5), ("1,5", 1.5)])
    func englishNumbers(input: String, expected: Double) throws {
        #expect(try eval(input, style: .english) == expected)
    }

    // MARK: Percent

    @Test(arguments: [
        ("50%", 0.5), ("200 + 10%", 220), ("200 - 10%", 180), ("200 * 10%", 20),
        ("200 / 50%", 400), ("10% * 200", 20), ("(100 + 100) + 50%", 300),
    ])
    func percent(input: String, expected: Double) throws {
        #expect(abs(try eval(input) - expected) < 1e-9)
    }

    // MARK: Variables & functions

    @Test func variablesAreCaseInsensitive() throws {
        #expect(try eval("Preis * 3", ["preis": 25]) == 75)
        #expect(try eval("größe_2 + 1", ["größe_2": 1]) == 2)
    }

    @Test func constantsAndFunctions() throws {
        #expect(try eval("pi") == Double.pi)
        #expect(try eval("sqrt(16)") == 4)
        #expect(try eval("round(2,5)") == 3)
        #expect(try eval("abs(-3) + floor(2,7) + ceil(0,2)") == 6)
        #expect(try eval("log(1000)") == 3)
    }

    // MARK: Errors

    @Test func errorsInsteadOfCrashes() {
        #expect(error("") == .empty)
        #expect(error("   ") == .empty)
        #expect(error("1 +") == .syntax)
        #expect(error("(1 + 2") == .syntax)
        #expect(error("1 + 2)") == .syntax)
        #expect(error("* 3") == .syntax)
        #expect(error("3 4") == .syntax)
        #expect(error("2 $ 3") == .syntax)
        #expect(error("1 / 0") == .divisionByZero)
        #expect(error("1 / (2 - 2)") == .divisionByZero)
        #expect(error("x + 1") == .unknownVariable("x"))
        #expect(error("foo(2)") == .unknownFunction("foo"))
        #expect(error("sqrt(-1)") == .invalidResult)
        #expect(error("10 ^ 400") == .invalidResult)
        #expect(error("%") == .syntax)
    }

    @Test func randomInputNeverCrashes() {
        let alphabet = Array("0123456789+-*/^%()., abx=:")
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let length = Int.random(in: 0...12, using: &generator)
            let input = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            _ = try? MathEngine.evaluate(input, variables: ["a": 1], style: .german)
        }
    }
}

struct NumberStyleTests {
    @Test func germanFormatting() {
        #expect(NumberStyle.german.format(1234.5) == "1.234,5")
        #expect(NumberStyle.german.format(1_000_000) == "1.000.000")
        #expect(NumberStyle.german.format(1.0 / 3) == "0,3333")
        #expect(NumberStyle.german.format(0.1 + 0.2) == "0,3")
        #expect(NumberStyle.german.format(-42) == "-42")
    }

    @Test func fixedDecimalsRoundHalfUp() {
        let style = NumberStyle(decimalSeparator: ",", groupingSeparator: ".", decimals: 2)
        #expect(style.format(2.5) == "2,50")
        #expect(style.format(1.005) == "1,01" || style.format(1.005) == "1,00") // binary representation
        #expect(style.format(0.125) == "0,13")
        #expect(NumberStyle(decimalSeparator: ",", groupingSeparator: nil, decimals: 0).format(2.5) == "3")
    }

    @Test func noNegativeZero() {
        let style = NumberStyle(decimalSeparator: ",", groupingSeparator: nil, decimals: 2)
        #expect(style.format(-0.001) == "0,00")
    }

    @Test func otherSeparators() {
        #expect(NumberStyle.english.format(1234.5) == "1,234.5")
        #expect(NumberStyle(decimalSeparator: ".", groupingSeparator: "'", decimals: nil).format(1234567.25) == "1'234'567.25")
        #expect(NumberStyle(decimalSeparator: ",", groupingSeparator: nil, decimals: nil).format(1234.5) == "1234,5")
    }

    @Test func groupingEqualToDecimalIsDropped() {
        #expect(NumberStyle(decimalSeparator: ",", groupingSeparator: ",", decimals: nil).groupingSeparator == nil)
    }
}

struct LabelTests {
    @Test(arguments: [
        ("Käse 3 * 1,99", 5.97),
        ("Essen pro Tag 35 * 7", 245),
        ("Coca-Cola 2 + 1", 3),
        ("Miete: 800", 800),
        ("Rabatt -5 + 10", 5),
        ("Summe (2 + 3) * 2", 10),
    ])
    func ignoresLeadingLabel(input: String, expected: Double) throws {
        #expect(abs(try MathEngine.evaluateIgnoringLabel(input, style: .german) - expected) < 1e-9)
    }

    @Test func labelBeforeVariable() throws {
        #expect(try MathEngine.evaluateIgnoringLabel("Kosten preis * 3", variables: ["preis": 25], style: .german) == 75)
    }

    @Test func labelNeverHidesUnknownVariables() {
        #expect(throws: MathError.unknownVariable("preis")) {
            try MathEngine.evaluateIgnoringLabel("preis * 3", style: .german)
        }
        #expect(throws: MathError.unknownVariable("preis")) {
            try MathEngine.evaluateIgnoringLabel("Kosten preis * 3", style: .german)
        }
        #expect(throws: MathError.unknownVariable("x")) {
            try MathEngine.evaluateIgnoringLabel("x", style: .german)
        }
    }

    @Test func knownVariableIsNeverALabel() {
        #expect(throws: MathError.syntax) {
            try MathEngine.evaluateIgnoringLabel("preis menge * 3", variables: ["preis": 1, "menge": 2], style: .german)
        }
    }

    @Test func labelNeverHidesDivisionByZero() {
        #expect(throws: MathError.divisionByZero) {
            try MathEngine.evaluateIgnoringLabel("Teilen 1 / 0", style: .german)
        }
    }

    @Test func variablesStillWin() throws {
        #expect(try MathEngine.evaluateIgnoringLabel("preis * 3", variables: ["preis": 2], style: .german) == 6)
    }

    @Test func labelRemainders() {
        #expect(MathEngine.labelRemainders("Brot 2,50") == ["2,50"])
        #expect(MathEngine.labelRemainders("Kosten für preis * 3", variables: ["preis": 1]) == ["für preis * 3", "preis * 3"])
        #expect(MathEngine.labelRemainders("2 + 3").isEmpty)
        #expect(MathEngine.labelRemainders("a * 3") == ["* 3"])
    }
}

struct CommentSyntaxTests {
    @Test(arguments: [
        ("// ganz", 0), ("  // eingerückt", 2), ("Pfand 0,25 // zurück", 11), ("x\t//y", 2),
    ])
    func findsComments(content: String, start: Int) {
        #expect(CommentSyntax.commentStart(in: content) == start)
    }

    @Test(arguments: ["https://example.com", "a//b", "Text", "/ einzeln"])
    func noComment(content: String) {
        #expect(CommentSyntax.commentStart(in: content) == nil)
    }

    @Test func codePart() {
        #expect(CommentSyntax.code(of: "Pfand 0,25 // zurück") == "Pfand 0,25")
        #expect(CommentSyntax.code(of: "// nur Kommentar") == "")
        #expect(CommentSyntax.code(of: "Brot 2") == "Brot 2")
    }
}
