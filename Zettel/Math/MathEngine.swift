import Foundation

/// Errors of the calculator. Never crashes on bad input.
enum MathError: Error, Equatable, Sendable {
    case empty
    case syntax
    case unknownVariable(String)
    case unknownFunction(String)
    case divisionByZero
    /// Infinite or not a number (e.g. `sqrt(-1)`).
    case invalidResult
    /// e.g. `10 kg to cm`.
    case incompatibleUnits
    /// No exchange rate for this currency code.
    case missingRate(String)
}

/// How numbers are written in input and output.
struct NumberStyle: Equatable, Sendable {
    /// Decimal separator, "," or ".".
    var decimalSeparator: Character
    /// Grouping separator or `nil`. Never equal to the decimal separator.
    var groupingSeparator: Character?
    /// Fixed number of decimals, or `nil` for automatic (up to `automaticMaxDecimals`).
    var decimals: Int?

    static let automaticMaxDecimals = 4

    init(decimalSeparator: Character, groupingSeparator: Character?, decimals: Int?) {
        self.decimalSeparator = decimalSeparator
        self.groupingSeparator = groupingSeparator == decimalSeparator ? nil : groupingSeparator
        self.decimals = decimals.map { min(max($0, 0), 10) }
    }

    /// German style: `1.234,56`.
    static let german = NumberStyle(decimalSeparator: ",", groupingSeparator: ".", decimals: nil)
    /// English style: `1,234.56`.
    static let english = NumberStyle(decimalSeparator: ".", groupingSeparator: ",", decimals: nil)

    /// Defaults matching the user's region.
    static var system: NumberStyle {
        let locale = Locale.current
        let decimal = locale.decimalSeparator?.first ?? "."
        let grouping = locale.groupingSeparator?.first
        return NumberStyle(decimalSeparator: decimal == "," ? "," : ".", groupingSeparator: grouping, decimals: nil)
    }

    func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = decimals ?? 0
        formatter.maximumFractionDigits = decimals ?? Self.automaticMaxDecimals
        formatter.decimalSeparator = String(decimalSeparator)
        formatter.usesGroupingSeparator = groupingSeparator != nil
        formatter.groupingSeparator = groupingSeparator.map(String.init) ?? ""
        formatter.groupingSize = 3
        let text = formatter.string(from: NSNumber(value: value)) ?? String(value)
        // Avoid "-0" after rounding tiny negative values.
        if text.hasPrefix("-"), !text.contains(where: { $0.isNumber && $0 != "0" }) {
            return String(text.dropFirst())
        }
        return text
    }
}

// MARK: - Tokenizer

enum MathToken: Equatable, Sendable {
    case number(Double)
    case identifier(String)
    case plus, minus, times, divide, power, percent
    case openParen, closeParen
}

enum MathTokenizer {
    /// Splits an expression into tokens. Accepts the style's decimal separator,
    /// "." or "," as decimal point otherwise, and grouping separators between
    /// groups of three digits (`1.000.000`).
    static func tokenize(_ input: String, style: NumberStyle) throws(MathError) -> [MathToken] {
        let characters = Array(input)
        var tokens: [MathToken] = []
        var index = 0

        func isDigit(_ offset: Int) -> Bool {
            Self.isDigit(characters, offset)
        }

        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if isDigit(index) || ((character == "." || character == ",") && isDigit(index + 1)) {
                guard let (value, end) = scanNumber(characters, from: index, style: style) else { throw .syntax }
                tokens.append(.number(value))
                index = end
                continue
            }
            if character.isLetter || character == "_" {
                var name = ""
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
                    name.append(characters[index])
                    index += 1
                }
                tokens.append(.identifier(name))
                continue
            }
            switch character {
            case "+": tokens.append(.plus)
            case "-", "−", "–": tokens.append(.minus)
            case "*", "×", "·": tokens.append(.times)
            case "/", "÷", ":": tokens.append(.divide)
            case "^": tokens.append(.power)
            case "%": tokens.append(.percent)
            case "(": tokens.append(.openParen)
            case ")": tokens.append(.closeParen)
            default: throw .syntax
            }
            index += 1
        }
        return tokens
    }

    static func isDigit(_ characters: [Character], _ offset: Int) -> Bool {
        offset >= 0 && offset < characters.count && characters[offset].isASCII && characters[offset].isNumber
    }

    /// Reads an unsigned number starting at `start` (a digit, or "."/"," before a
    /// digit). Returns the value and the index after the number.
    static func scanNumber(_ characters: [Character], from start: Int, style: NumberStyle) -> (Double, Int)? {
        var index = start
        var digits = ""
        var hasDecimalPoint = false
        func isDigit(_ offset: Int) -> Bool { Self.isDigit(characters, offset) }

        while index < characters.count {
            let current = characters[index]
            if isDigit(index) {
                digits.append(current)
                index += 1
            } else if !hasDecimalPoint, current == style.groupingSeparator, !digits.isEmpty,
                      isDigit(index + 1), isDigit(index + 2), isDigit(index + 3), !isDigit(index + 4) {
                index += 1 // grouping separator, e.g. the "." in "1.000"
            } else if !hasDecimalPoint, current == "." || current == ",", isDigit(index + 1) {
                digits.append(".")
                hasDecimalPoint = true
                index += 1
            } else {
                break
            }
        }
        guard !digits.isEmpty, let value = Double(digits.hasPrefix(".") ? "0" + digits : digits) else { return nil }
        return (value, index)
    }
}

// MARK: - Parser

indirect enum MathExpression: Equatable, Sendable {
    case number(Double)
    case variable(String)
    case negate(MathExpression)
    case percent(MathExpression)
    case binary(Operator, MathExpression, MathExpression)
    case call(String, MathExpression)

    enum Operator: Equatable, Sendable {
        case add, subtract, multiply, divide, power
    }
}

/// Recursive-descent parser.
///
/// ```
/// expression := term (("+" | "-") term)*
/// term       := unary (("*" | "/") unary)*
/// unary      := ("-" | "+") unary | power
/// power      := postfix ("^" unary)?        (right-associative, -2^2 = -4)
/// postfix    := primary "%"*
/// primary    := number | identifier | identifier "(" expression ")" | "(" expression ")"
/// ```
struct MathParser {
    private let tokens: [MathToken]
    private var position = 0

    private init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    static func parse(_ input: String, style: NumberStyle) throws(MathError) -> MathExpression {
        let tokens = try MathTokenizer.tokenize(input, style: style)
        guard !tokens.isEmpty else { throw .empty }
        var parser = MathParser(tokens: tokens)
        let expression = try parser.parseExpression()
        guard parser.position == tokens.count else { throw .syntax }
        return expression
    }

    private var current: MathToken? {
        position < tokens.count ? tokens[position] : nil
    }

    private mutating func advance() {
        position += 1
    }

    private mutating func parseExpression() throws(MathError) -> MathExpression {
        var left = try parseTerm()
        while let token = current {
            switch token {
            case .plus:
                advance()
                left = .binary(.add, left, try parseTerm())
            case .minus:
                advance()
                left = .binary(.subtract, left, try parseTerm())
            default:
                return left
            }
        }
        return left
    }

    private mutating func parseTerm() throws(MathError) -> MathExpression {
        var left = try parseUnary()
        while let token = current {
            switch token {
            case .times:
                advance()
                left = .binary(.multiply, left, try parseUnary())
            case .divide:
                advance()
                left = .binary(.divide, left, try parseUnary())
            default:
                return left
            }
        }
        return left
    }

    private mutating func parseUnary() throws(MathError) -> MathExpression {
        switch current {
        case .minus:
            advance()
            return .negate(try parseUnary())
        case .plus:
            advance()
            return try parseUnary()
        default:
            return try parsePower()
        }
    }

    private mutating func parsePower() throws(MathError) -> MathExpression {
        let base = try parsePostfix()
        guard current == .power else { return base }
        advance()
        return .binary(.power, base, try parseUnary())
    }

    private mutating func parsePostfix() throws(MathError) -> MathExpression {
        var expression = try parsePrimary()
        while current == .percent {
            advance()
            expression = .percent(expression)
        }
        return expression
    }

    private mutating func parsePrimary() throws(MathError) -> MathExpression {
        switch current {
        case .number(let value):
            advance()
            return .number(value)
        case .identifier(let name):
            advance()
            guard current == .openParen else { return .variable(name) }
            advance()
            let argument = try parseExpression()
            guard current == .closeParen else { throw .syntax }
            advance()
            return .call(name, argument)
        case .openParen:
            advance()
            let inner = try parseExpression()
            guard current == .closeParen else { throw .syntax }
            advance()
            return inner
        default:
            throw .syntax
        }
    }
}

// MARK: - Evaluator

enum MathEvaluator {
    /// Variable names are case-insensitive; pass lowercased keys.
    static func evaluate(_ expression: MathExpression, variables: [String: Double] = [:]) throws(MathError) -> Double {
        let value = try value(of: expression, variables: variables)
        guard value.isFinite else { throw .invalidResult }
        return value
    }

    private static func value(of expression: MathExpression, variables: [String: Double]) throws(MathError) -> Double {
        switch expression {
        case .number(let number):
            return number
        case .variable(let name):
            let key = name.lowercased()
            if let value = variables[key] { return value }
            if key == "pi" || key == "π" { return Double.pi }
            throw .unknownVariable(name)
        case .negate(let inner):
            return -(try value(of: inner, variables: variables))
        case .percent(let inner):
            return try value(of: inner, variables: variables) / 100
        case .call(let name, let argument):
            return try call(name, try value(of: argument, variables: variables))
        case .binary(let op, let left, let right):
            let lhs = try value(of: left, variables: variables)
            // "200 + 10%" = 220, "200 - 10%" = 180: percent of the left side.
            if case .percent(let percentage) = right, op == .add || op == .subtract {
                let share = lhs * (try value(of: percentage, variables: variables)) / 100
                return op == .add ? lhs + share : lhs - share
            }
            let rhs = try value(of: right, variables: variables)
            switch op {
            case .add: return lhs + rhs
            case .subtract: return lhs - rhs
            case .multiply: return lhs * rhs
            case .divide:
                guard rhs != 0 else { throw .divisionByZero }
                return lhs / rhs
            case .power:
                let result = pow(lhs, rhs)
                guard result.isFinite else { throw .invalidResult }
                return result
            }
        }
    }

    private static func call(_ name: String, _ argument: Double) throws(MathError) -> Double {
        let result: Double
        switch name.lowercased() {
        case "sqrt", "wurzel": result = argument.squareRoot()
        case "abs": result = abs(argument)
        case "round", "runden": result = argument.rounded(.toNearestOrAwayFromZero)
        case "floor": result = argument.rounded(.down)
        case "ceil": result = argument.rounded(.up)
        case "ln": result = log(argument)
        case "log": result = log10(argument)
        case "sin": result = sin(argument)
        case "cos": result = cos(argument)
        case "tan": result = tan(argument)
        default: throw .unknownFunction(name)
        }
        guard result.isFinite else { throw .invalidResult }
        return result
    }
}

enum MathEngine {
    static func evaluate(_ input: String, variables: [String: Double] = [:], style: NumberStyle = .german) throws(MathError) -> Double {
        try MathEvaluator.evaluate(MathParser.parse(input, style: style), variables: variables)
    }

    /// Like `evaluate`, but leading label words are ignored if the whole input
    /// does not compute: `Käse 3 * 1,99` → 5.97, `Kosten preis * 3` → 3 × preis.
    ///
    /// Label words are plain words (no operators) that are not variables or
    /// functions, so `preis * 3` with an unknown `preis` still reports `preis?`.
    static func evaluateIgnoringLabel(_ input: String, variables: [String: Double] = [:], style: NumberStyle = .german) throws(MathError) -> Double {
        let firstError: MathError
        do {
            return try evaluate(input, variables: variables, style: style)
        } catch {
            if error == .divisionByZero || error == .invalidResult { throw error }
            firstError = error
        }

        var bestError = firstError
        for remainder in labelRemainders(input, variables: variables) {
            do {
                return try evaluate(remainder, variables: variables, style: style)
            } catch {
                // Prefer a specific problem ("preis?", "÷ 0") over a plain syntax error.
                if bestError == .syntax || bestError == .empty, error != .syntax, error != .empty {
                    bestError = error
                }
            }
        }
        throw bestError
    }

    /// The input with 1, 2, … leading label words removed.
    static func labelRemainders(_ input: String, variables: [String: Double] = [:]) -> [String] {
        var remainders: [String] = []
        var rest = Substring(input)
        while true {
            rest = rest.drop { $0.isWhitespace }
            let word = rest.prefix { !$0.isWhitespace }
            guard isLabelWord(word, variables: variables) else { break }
            rest = rest.dropFirst(word.count)
            let remainder = rest.trimmingCharacters(in: .whitespaces)
            guard !remainder.isEmpty else { break }
            remainders.append(remainder)
        }
        return remainders
    }

    private static func isLabelWord(_ word: Substring, variables: [String: Double]) -> Bool {
        guard word.contains(where: \.isLetter),
              word.allSatisfy({ $0.isLetter || ":.,-'’&".contains($0) })
        else { return false }
        let name = word.trimmingCharacters(in: CharacterSet(charactersIn: ":.,")).lowercased()
        return variables[name] == nil && !["ans", "pi", "π"].contains(name)
    }
}
