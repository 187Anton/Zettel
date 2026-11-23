import Foundation

/// What a line of a `math` note shows on its right side.
struct LineAnnotation: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case result
        case total
        case error
        /// Neutral information, e.g. the counts of a `count` note.
        case info
    }

    var text: String
    var kind: Kind
}

/// Evaluates a `math` note line by line, top to bottom.
///
/// - `ausdruck =`  shows the result.
/// - `name : ausdruck`  defines a variable (with a trailing `=` it also shows it).
///   Names may have several words: `Preis pro Stück : 2,50`.
/// - `ans`  is the nearest result above.
/// - `total =`  sums all results above, except earlier totals.
/// - Lines starting with `//` and all other lines are ignored.
enum MathSheet {
    /// - Parameters:
    ///   - lines: Display lines of the note.
    ///   - firstLine: Index where evaluation starts (1 to skip the keyword header).
    /// - Returns: Annotations by line index.
    static func evaluate(lines: [String], from firstLine: Int = 0, style: NumberStyle, converter: UnitConverter = .none) -> [Int: LineAnnotation] {
        var annotations: [Int: LineAnnotation] = [:]
        var variables: [String: Double] = [:]
        var results: [(value: Double, isTotal: Bool)] = []

        for index in lines.indices where index >= firstLine {
            var text = CommentSyntax.code(of: ListLine(display: lines[index]).content).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            let showsResult = text.hasSuffix("=")
            if showsResult {
                text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            }

            if showsResult, text.lowercased() == "total" {
                let sum = results.filter { !$0.isTotal }.reduce(0) { $0 + $1.value }
                results.append((sum, true))
                annotations[index] = LineAnnotation(text: style.format(sum), kind: .total)
                continue
            }

            let assignment = splitAssignment(text)
            let expression = assignment?.expression ?? text
            guard showsResult || assignment != nil else { continue }

            var scope = variables
            if let last = results.last { scope["ans"] = last.value }
            let prepared = substituteMultiWordNames(in: expression, scope: &scope)

            do {
                // Units work in definitions too: "strecke : 420 km" stores 420.
                let (value, unit) = try MathEngine.evaluateLine(prepared, variables: scope, style: style, converter: converter)
                if let name = assignment?.name {
                    variables[name.lowercased()] = value
                }
                if showsResult {
                    results.append((value, false))
                    annotations[index] = LineAnnotation(text: format(value, unit: unit, style: style), kind: .result)
                }
            } catch {
                // Incomplete definitions while typing stay quiet; results show the problem.
                if showsResult {
                    annotations[index] = LineAnnotation(text: message(for: error), kind: .error)
                }
            }
        }
        return annotations
    }

    static let maxNameWords = 5

    /// `preis : 25` → ("preis", " 25"); `Preis pro  Stück: 2` → ("Preis pro Stück", " 2").
    /// A name is 1–5 words of letters, digits and `_`, starting with a letter.
    static func splitAssignment(_ text: String) -> (name: String, expression: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let words = text[..<colon].split(whereSeparator: \.isWhitespace)
        guard (1...maxNameWords).contains(words.count),
              let first = words[0].first, first.isLetter || first == "_",
              words.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } })
        else { return nil }
        let name = words.joined(separator: " ")
        guard !["ans", "total", "pi"].contains(name.lowercased()) else { return nil }
        return (name, String(text[text.index(after: colon)...]))
    }

    /// Replaces multi-word variable names in an expression with placeholder
    /// identifiers that the parser understands, longest names first.
    /// `Preis pro Stück * 3` → `_v0 * 3` with `_v0` added to `scope`.
    static func substituteMultiWordNames(in expression: String, scope: inout [String: Double]) -> String {
        let names = scope.keys.filter { $0.contains(" ") }.sorted { $0.count > $1.count }
        guard !names.isEmpty else { return expression }

        var result = expression
        for (number, name) in names.enumerated() {
            let words = name.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = "(?<![\\p{L}\\p{N}_])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let placeholder = "_v\(number)"
            let range = NSRange(location: 0, length: (result as NSString).length)
            let replaced = regex.stringByReplacingMatches(in: result, range: range, withTemplate: placeholder)
            if replaced != result {
                scope[placeholder] = scope[name]
                result = replaced
            }
        }
        return result
    }

    /// "3,94 in", "92,5 USD", "42".
    static func format(_ value: Double, unit: MeasureUnit?, style: NumberStyle) -> String {
        guard let unit else { return style.format(value) }
        return style.format(value) + " " + unit.symbol
    }

    static func message(for error: MathError) -> String {
        switch error {
        case .empty, .syntax: "?"
        case .unknownVariable(let name): "\(name)?"
        case .unknownFunction(let name): "\(name)()?"
        case .divisionByZero: "÷ 0"
        case .invalidResult: "–"
        case .incompatibleUnits: "Einheit?"
        case .missingRate(let code): "Kurs \(code)?"
        }
    }
}
