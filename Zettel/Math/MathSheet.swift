import Foundation

/// What a line of a `math` note shows on its right side.
struct LineAnnotation: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case result
        case total
        case error
    }

    var text: String
    var kind: Kind
}

/// Evaluates a `math` note line by line, top to bottom.
///
/// - `ausdruck =`  shows the result.
/// - `name : ausdruck`  defines a variable (with a trailing `=` it also shows it).
/// - `ans`  is the nearest result above.
/// - `total =`  sums all results above, except earlier totals.
/// - Lines starting with `//` and all other lines are ignored.
enum MathSheet {
    /// - Parameters:
    ///   - lines: Display lines of the note.
    ///   - firstLine: Index where evaluation starts (1 to skip the keyword header).
    /// - Returns: Annotations by line index.
    static func evaluate(lines: [String], from firstLine: Int = 0, style: NumberStyle) -> [Int: LineAnnotation] {
        var annotations: [Int: LineAnnotation] = [:]
        var variables: [String: Double] = [:]
        var results: [(value: Double, isTotal: Bool)] = []

        for index in lines.indices where index >= firstLine {
            var text = ListLine(display: lines[index]).content.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("//") else { continue }

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

            do {
                let value = try MathEngine.evaluate(expression, variables: scope, style: style)
                if let name = assignment?.name {
                    variables[name.lowercased()] = value
                }
                if showsResult {
                    results.append((value, false))
                    annotations[index] = LineAnnotation(text: style.format(value), kind: .result)
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

    /// `preis : 25` → ("preis", "25"). The name must be a single identifier.
    static func splitAssignment(_ text: String) -> (name: String, expression: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = text[..<colon].trimmingCharacters(in: .whitespaces)
        guard let first = name.first, first.isLetter || first == "_",
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              !["ans", "total", "pi"].contains(name.lowercased())
        else { return nil }
        return (name, String(text[text.index(after: colon)...]))
    }

    static func message(for error: MathError) -> String {
        switch error {
        case .empty, .syntax: "?"
        case .unknownVariable(let name): "\(name)?"
        case .unknownFunction(let name): "\(name)()?"
        case .divisionByZero: "÷ 0"
        case .invalidResult: "–"
        }
    }
}
