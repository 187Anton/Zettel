import Foundation

/// Finds numbers in free text: `Brot 2,50 €` → 2.5, `Rabatt -5` → -5, `1.299,00` → 1299.
///
/// Numbers glued to a letter on the left (`H2O`, `Phase5`) are not counted.
/// A minus counts as sign only at the start or after a space or `(`.
enum NumberExtraction {
    static func numbers(in text: String, style: NumberStyle) -> [Double] {
        let characters = Array(text)
        var result: [Double] = []
        var index = 0

        func isDigit(_ offset: Int) -> Bool { MathTokenizer.isDigit(characters, offset) }
        func isBoundary(_ offset: Int) -> Bool {
            offset < 0 || characters[offset].isWhitespace || "([{".contains(characters[offset])
        }

        while index < characters.count {
            let character = characters[index]
            var sign: Double = 1
            var start = index

            if (character == "-" || character == "−"), isBoundary(index - 1),
               isDigit(index + 1) || ((index + 2 < characters.count) && ".,".contains(characters[index + 1]) && isDigit(index + 2)) {
                sign = -1
                start = index + 1
            }

            let startsNumber = isDigit(start) || (".,".contains(characters[start]) && isDigit(start + 1) && isBoundary(start - 1))
            let gluedToWord = start > 0 && (characters[start - 1].isLetter || characters[start - 1] == "_") && sign > 0
            if startsNumber, !gluedToWord, let (value, end) = MathTokenizer.scanNumber(characters, from: start, style: style) {
                result.append(sign * value)
                index = end
                continue
            }
            if startsNumber {
                // Skip the rest of a glued number ("H20" → skip "20").
                index = start
                while index < characters.count, isDigit(index) || ".,".contains(characters[index]) { index += 1 }
                continue
            }
            index += 1
        }
        return result
    }
}

/// Evaluates `sum`, `avg` and `count` notes. The aggregate is shown on the
/// header line (index 0); lines ending with `=` show and contribute their result.
enum AggregateSheet {
    static func evaluate(_ keyword: Keyword, lines: [String], style: NumberStyle, converter: UnitConverter = .none) -> [Int: LineAnnotation] {
        switch keyword {
        case .sum, .avg: numbers(keyword, lines: lines, style: style, converter: converter)
        case .count: count(lines: lines)
        case .list, .math: [:]
        }
    }

    // MARK: sum / avg

    private static func numbers(_ keyword: Keyword, lines: [String], style: NumberStyle, converter: UnitConverter) -> [Int: LineAnnotation] {
        var annotations: [Int: LineAnnotation] = [:]
        var values: [Double] = []

        for (index, line) in lines.enumerated().dropFirst() {
            let content = CommentSyntax.code(of: ListLine(display: line).content).trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }

            if content.hasSuffix("=") {
                let expression = String(content.dropLast())
                do {
                    let (value, unit) = try MathEngine.evaluateLine(expression, style: style, converter: converter)
                    values.append(value)
                    annotations[index] = LineAnnotation(text: MathSheet.format(value, unit: unit, style: style), kind: .result)
                } catch {
                    annotations[index] = LineAnnotation(text: MathSheet.message(for: error), kind: .error)
                }
                continue
            }

            let found = NumberExtraction.numbers(in: content, style: style)
            switch keyword {
            case .sum: if !found.isEmpty { values.append(found.reduce(0, +)) }
            default: values.append(contentsOf: found)
            }
        }

        if keyword == .sum {
            annotations[0] = LineAnnotation(text: style.format(values.reduce(0, +)), kind: .total)
        } else {
            let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            annotations[0] = LineAnnotation(text: "Ø " + (average.map(style.format) ?? "–"), kind: .total)
        }
        return annotations
    }

    // MARK: count

    struct Counts: Equatable {
        var entries = 0
        var lines = 0
        var words = 0
        var characters = 0
    }

    /// Lines: up to the last non-empty line (blank lines in between count).
    /// Entries: non-empty lines. Words and characters: without list markers,
    /// characters including spaces. `//` lines are left out.
    static func counts(lines: [String]) -> Counts {
        let body = Array(lines.dropFirst())
        let lastUsed = body.lastIndex { !$0.allSatisfy(\.isWhitespace) }
        var counts = Counts()
        guard let lastUsed else { return counts }

        for line in body[...lastUsed] {
            let content = ListLine(display: line).content
            guard !content.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
            let trimmed = CommentSyntax.code(of: content).trimmingCharacters(in: .whitespaces)
            counts.lines += 1
            guard !trimmed.isEmpty else { continue }
            counts.entries += 1
            counts.words += trimmed.split(whereSeparator: \.isWhitespace).count
            counts.characters += trimmed.count
        }
        return counts
    }

    private static func count(lines: [String]) -> [Int: LineAnnotation] {
        let counts = counts(lines: lines)
        let text = [
            plural(counts.entries, "Eintrag", "Einträge"),
            plural(counts.lines, "Zeile", "Zeilen"),
            plural(counts.words, "Wort", "Wörter"),
            plural(counts.characters, "Zeichen", "Zeichen"),
        ].joined(separator: " · ")
        return [0: LineAnnotation(text: text, kind: .info)]
    }

    private static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
