import Foundation

/// A unit of measurement or a currency. Linear units convert via
/// `base = value × factor + offset` (offset only for temperatures).
struct MeasureUnit: Equatable, Sendable {
    enum Dimension: Equatable, Sendable {
        case length, area, volume, mass, temperature, currency
    }

    /// Shown after results, e.g. "cm", "°F", "USD".
    let symbol: String
    let dimension: Dimension
    let factor: Double
    let offset: Double

    init(_ symbol: String, _ dimension: Dimension, _ factor: Double = 1, offset: Double = 0) {
        self.symbol = symbol
        self.dimension = dimension
        self.factor = factor
        self.offset = offset
    }

    static func currency(_ code: String) -> MeasureUnit {
        MeasureUnit(code, .currency)
    }
}

/// All known units, looked up by name (case-insensitive). Local tables only.
enum UnitCatalog {
    /// Base units: m, m², l, kg, K.
    private static let entries: [(names: [String], unit: MeasureUnit)] = [
        // Length (m)
        (["mm", "millimeter"], MeasureUnit("mm", .length, 0.001)),
        (["cm", "zentimeter", "centimeter"], MeasureUnit("cm", .length, 0.01)),
        (["dm", "dezimeter"], MeasureUnit("dm", .length, 0.1)),
        (["m", "meter", "metre"], MeasureUnit("m", .length)),
        (["km", "kilometer"], MeasureUnit("km", .length, 1000)),
        (["in", "inch", "inches", "zoll", "\""], MeasureUnit("in", .length, 0.0254)),
        (["ft", "foot", "feet", "fuß", "fuss"], MeasureUnit("ft", .length, 0.3048)),
        (["yd", "yard", "yards"], MeasureUnit("yd", .length, 0.9144)),
        (["mi", "mile", "miles", "meile", "meilen"], MeasureUnit("mi", .length, 1609.344)),
        (["nmi", "seemeile", "seemeilen"], MeasureUnit("nmi", .length, 1852)),
        // Area (m²)
        (["mm²", "mm2"], MeasureUnit("mm²", .area, 1e-6)),
        (["cm²", "cm2"], MeasureUnit("cm²", .area, 1e-4)),
        (["m²", "m2", "qm"], MeasureUnit("m²", .area)),
        (["km²", "km2"], MeasureUnit("km²", .area, 1e6)),
        (["ha", "hektar", "hectare"], MeasureUnit("ha", .area, 10_000)),
        (["in²", "in2"], MeasureUnit("in²", .area, 0.00064516)),
        (["ft²", "ft2", "sqft"], MeasureUnit("ft²", .area, 0.09290304)),
        (["acre", "acres"], MeasureUnit("acre", .area, 4046.8564224)),
        // Volume (l)
        (["ml", "milliliter"], MeasureUnit("ml", .volume, 0.001)),
        (["cl", "zentiliter"], MeasureUnit("cl", .volume, 0.01)),
        (["dl", "deziliter"], MeasureUnit("dl", .volume, 0.1)),
        (["l", "liter", "litre"], MeasureUnit("l", .volume)),
        (["m³", "m3", "kubikmeter"], MeasureUnit("m³", .volume, 1000)),
        (["cm³", "cm3", "ccm"], MeasureUnit("cm³", .volume, 0.001)),
        (["tl", "tsp", "teelöffel"], MeasureUnit("TL", .volume, 0.005)),
        (["el", "tbsp", "esslöffel"], MeasureUnit("EL", .volume, 0.015)),
        (["cup", "cups", "tasse", "tassen"], MeasureUnit("cup", .volume, 0.2365882365)),
        (["floz", "fl.oz"], MeasureUnit("fl oz", .volume, 0.0295735295625)),
        (["pt", "pint", "pints"], MeasureUnit("pt", .volume, 0.473176473)),
        (["qt", "quart", "quarts"], MeasureUnit("qt", .volume, 0.946352946)),
        (["gal", "gallon", "gallons", "gallone", "gallonen"], MeasureUnit("gal", .volume, 3.785411784)),
        // Mass (kg)
        (["mg", "milligramm"], MeasureUnit("mg", .mass, 1e-6)),
        (["g", "gramm", "gram"], MeasureUnit("g", .mass, 0.001)),
        (["kg", "kilo", "kilogramm", "kilogram"], MeasureUnit("kg", .mass)),
        (["t", "tonne", "tonnen"], MeasureUnit("t", .mass, 1000)),
        (["oz", "ounce", "ounces", "unze", "unzen"], MeasureUnit("oz", .mass, 0.028349523125)),
        (["lb", "lbs", "pound", "pounds"], MeasureUnit("lb", .mass, 0.45359237)),
        (["pfund"], MeasureUnit("Pfund", .mass, 0.5)),
        (["st", "stone"], MeasureUnit("st", .mass, 6.35029318)),
        // Temperature (K)
        (["°c", "c", "celsius", "grad"], MeasureUnit("°C", .temperature, 1, offset: 273.15)),
        (["°f", "f", "fahrenheit"], MeasureUnit("°F", .temperature, 5.0 / 9.0, offset: 459.67 * 5.0 / 9.0)),
        (["k", "kelvin"], MeasureUnit("K", .temperature)),
    ]

    private static let byName: [String: MeasureUnit] = {
        var table: [String: MeasureUnit] = [:]
        for (names, unit) in entries {
            for name in names { table[name] = unit }
        }
        return table
    }()

    /// Currency symbols and the codes of the ECB reference rates.
    private static let currencySymbols: [String: String] = ["€": "EUR", "$": "USD", "£": "GBP", "¥": "JPY", "fr.": "CHF"]
    static let knownCurrencies: Set<String> = [
        "EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "ISK", "NOK",
        "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR", "NZD", "PHP",
        "SGD", "THB", "ZAR",
    ]

    /// - Parameter extraCurrencies: codes with a user-defined rate.
    static func unit(named name: String, extraCurrencies: Set<String> = []) -> MeasureUnit? {
        let lower = name.lowercased()
        if let unit = byName[lower] { return unit }
        if let code = currencySymbols[lower] { return .currency(code) }
        let upper = name.uppercased()
        if upper.count == 3, knownCurrencies.contains(upper) || extraCurrencies.contains(upper) {
            return .currency(upper)
        }
        return nil
    }
}

/// Converts between units; currencies via rates "1 EUR = x".
struct UnitConverter: Sendable {
    /// Units of each currency per 1 EUR.
    var rates: [String: Double]

    static let none = UnitConverter(rates: [:])

    var currencies: Set<String> { Set(rates.keys) }

    func convert(_ value: Double, from: MeasureUnit, to: MeasureUnit) throws(MathError) -> Double {
        guard from.dimension == to.dimension else { throw .incompatibleUnits }
        if from.dimension == .currency {
            guard let fromRate = rate(from.symbol) else { throw .missingRate(from.symbol) }
            guard let toRate = rate(to.symbol) else { throw .missingRate(to.symbol) }
            return value / fromRate * toRate
        }
        let base = value * from.factor + from.offset
        return (base - to.offset) / to.factor
    }

    private func rate(_ code: String) -> Double? {
        code == "EUR" ? 1 : rates[code].flatMap { $0 > 0 ? $0 : nil }
    }
}

/// An expression with a unit: `10 cm to inch`, `100 € in USD`, or just `5 km`.
struct UnitExpression: Equatable, Sendable {
    var expression: String
    var from: MeasureUnit
    var to: MeasureUnit?

    static let separators: Set<String> = ["to", "in", "->", "→", "as", "als", "nach"]

    /// - Parameter extraCurrencies: currency codes with a user-defined rate.
    static func parse(_ text: String, extraCurrencies: Set<String> = []) -> UnitExpression? {
        let tokens = tokenize(text)
        func unit(_ token: String) -> MeasureUnit? { UnitCatalog.unit(named: token, extraCurrencies: extraCurrencies) }

        // "<expression> <unit> to <unit>" – search the separator from the end.
        if tokens.count >= 4 {
            for index in stride(from: tokens.count - 2, through: 2, by: -1)
            where separators.contains(tokens[index].lowercased()) && index == tokens.count - 2 {
                guard let from = unit(tokens[index - 1]), let to = unit(tokens[index + 1]) else { continue }
                return UnitExpression(expression: tokens[..<(index - 1)].joined(separator: " "), from: from, to: to)
            }
        }
        // "<expression> <unit>"
        if tokens.count >= 2, let from = unit(tokens[tokens.count - 1]) {
            return UnitExpression(expression: tokens.dropLast().joined(separator: " "), from: from, to: nil)
        }
        return nil
    }

    /// Splits at whitespace and separates units glued to numbers: "10cm" → "10", "cm";
    /// "20°C" → "20", "°C"; "€10" → "10", "€".
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let first = word.first, "€$£¥".contains(first), word.dropFirst().first?.isNumber == true {
                tokens.append(String(word.dropFirst()))
                tokens.append(String(first))
                continue
            }
            let characters = Array(word)
            if let split = characters.indices.first(where: { index in
                index > 0 && (characters[index - 1].isNumber) && (characters[index].isLetter || "°€$£¥\"".contains(characters[index]))
            }), characters[..<split].allSatisfy({ $0.isNumber || ".,".contains($0) }) {
                tokens.append(String(characters[..<split]))
                tokens.append(String(characters[split...]))
                continue
            }
            tokens.append(word)
        }
        return tokens
    }
}

extension MathEngine {
    /// A calculation line, optionally with units:
    /// - `10 cm to inch` → converted value with target unit,
    /// - `2 * 3` → plain value,
    /// - `5 km` → value with unit (only if it does not compute without the unit).
    static func evaluateLine(
        _ text: String,
        variables: [String: Double] = [:],
        style: NumberStyle,
        converter: UnitConverter = .none
    ) throws(MathError) -> (value: Double, unit: MeasureUnit?) {
        let parsed = UnitExpression.parse(text, extraCurrencies: converter.currencies)
        if let parsed, let target = parsed.to {
            let value = try evaluateIgnoringLabel(parsed.expression, variables: variables, style: style)
            return (try converter.convert(value, from: parsed.from, to: target), target)
        }
        do {
            return (try evaluateIgnoringLabel(text, variables: variables, style: style), nil)
        } catch {
            guard let parsed, !parsed.expression.isEmpty,
                  let value = try? evaluateIgnoringLabel(parsed.expression, variables: variables, style: style)
            else { throw error }
            return (value, parsed.from)
        }
    }
}
