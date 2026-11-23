import Foundation
import Testing
@testable import Zettel

struct UnitConversionTests {
    private let converter = UnitConverter(rates: ["USD": 1.08, "GBP": 0.85, "JPY": 160])

    private func convert(_ value: Double, _ from: String, _ to: String) throws -> Double {
        let from = try #require(UnitCatalog.unit(named: from))
        let to = try #require(UnitCatalog.unit(named: to))
        return try converter.convert(value, from: from, to: to)
    }

    @Test(arguments: [
        (10.0, "cm", "inch", 3.937007874),
        (1, "mi", "km", 1.609344),
        (6, "ft", "m", 1.8288),
        (1, "km²", "ha", 100),
        (1, "acre", "m²", 4046.8564224),
        (1, "gal", "l", 3.785411784),
        (500, "ml", "cup", 2.113376419),
        (1, "lb", "g", 453.59237),
        (2, "Pfund", "kg", 1),
        (100, "°C", "°F", 212),
        (-40, "F", "C", -40),
        (0, "K", "°C", -273.15),
        (32, "fahrenheit", "kelvin", 273.15),
    ])
    func converts(value: Double, from: String, to: String, expected: Double) throws {
        #expect(abs(try convert(value, from, to) - expected) < 1e-6)
    }

    @Test func currencies() throws {
        #expect(abs(try convert(100, "EUR", "USD") - 108) < 1e-9)
        #expect(abs(try convert(108, "$", "€") - 100) < 1e-9)
        #expect(abs(try convert(85, "GBP", "USD") - 108) < 1e-9)
    }

    @Test func incompatibleAndMissing() throws {
        #expect(throws: MathError.incompatibleUnits) { try convert(1, "kg", "m") }
        #expect(throws: MathError.missingRate("CHF")) { try convert(1, "EUR", "CHF") }
    }

    @Test func userDefinedCurrencyCodes() {
        #expect(UnitCatalog.unit(named: "BTC") == nil)
        #expect(UnitCatalog.unit(named: "btc", extraCurrencies: ["BTC"]) == .currency("BTC"))
        #expect(UnitCatalog.unit(named: "chf") == .currency("CHF"))
    }
}

struct UnitExpressionTests {
    @Test(arguments: [
        ("10 cm to inch", "10", "cm", "in"),
        ("10cm in in", "10", "cm", "in"),
        ("10 in in cm", "10", "in", "cm"),
        ("2 * 3 km → mi", "2 * 3", "km", "mi"),
        ("20°C in °F", "20", "°C", "°F"),
        ("100 € in $", "100", "EUR", "USD"),
        ("€100 to usd", "100", "EUR", "USD"),
        ("Flug 420 eur in gbp", "Flug 420", "EUR", "GBP"),
        ("5 kg als Pfund", "5", "kg", "Pfund"),
    ])
    func parsesConversions(text: String, expression: String, from: String, to: String) throws {
        let parsed = try #require(UnitExpression.parse(text))
        #expect(parsed.expression == expression)
        #expect(parsed.from.symbol == from)
        #expect(parsed.to?.symbol == to)
    }

    @Test func unitWithoutTarget() throws {
        let parsed = try #require(UnitExpression.parse("5 km"))
        #expect(parsed.expression == "5")
        #expect(parsed.to == nil)
    }

    @Test(arguments: ["2 + 3", "preis * 3", "Text ohne Einheit", "cm"])
    func noUnitExpression(text: String) {
        #expect(UnitExpression.parse(text)?.to == nil)
        #expect(UnitExpression.parse(text).map { !$0.expression.isEmpty } != true || text == "preis * 3" || text == "Text ohne Einheit")
    }
}

struct UnitLineTests {
    private func line(_ text: String, _ variables: [String: Double] = [:], rates: [String: Double] = [:]) throws -> String {
        let (value, unit) = try MathEngine.evaluateLine(text, variables: variables, style: .german, converter: UnitConverter(rates: rates))
        return MathSheet.format(value, unit: unit, style: .german)
    }

    @Test func conversionsInLines() throws {
        #expect(try line("10 cm to inch") == "3,937 in")
        #expect(try line("Raumhöhe 2,5 m in ft") == "8,2021 ft")
        #expect(try line("breite * 2 m to cm", ["breite": 1.5]) == "300 cm")
        #expect(try line("100 € in USD", rates: ["USD": 1.0812]) == "108,12 USD")
    }

    @Test func plainExpressionsStayPlain() throws {
        #expect(try line("2 * 3") == "6")
        #expect(try line("x * m", ["x": 2, "m": 4]) == "8") // variable named like a unit
    }

    @Test func valueWithUnitOnly() throws {
        #expect(try line("5 km") == "5 km")
        #expect(try line("3 * 4 kg") == "12 kg")
    }

    @Test func errors() {
        #expect(throws: MathError.missingRate("USD")) { try line("10 EUR to USD") }
        #expect(throws: MathError.incompatibleUnits) { try line("10 kg to cm") }
        #expect(throws: MathError.unknownVariable("t")) { try line("kosten * t", ["kosten": 2]) } // "t" is no ton here
    }
}

struct UnitSheetTests {
    @Test func mathNoteWithUnits() {
        let lines = ["math: Reise", "strecke : 420", "strecke km to mi =", "ans * 2 =", "Benzin 50 l in gal =", "200 € in USD ="]
        let annotations = MathSheet.evaluate(lines: lines, from: 1, style: .german, converter: UnitConverter(rates: ["USD": 1.1]))
        #expect(annotations.mapValues(\.text) == [2: "260,9759 mi", 3: "521,9518", 4: "13,2086 gal", 5: "220 USD"])
    }

    @Test func variablesWithUnits() {
        let lines = ["math", "strecke : 420 km", "strecke km to mi =", "laenge : 2 ft in cm", "laenge ="]
        let annotations = MathSheet.evaluate(lines: lines, from: 1, style: .german)
        #expect(annotations.mapValues(\.text) == [2: "260,9759 mi", 4: "60,96"])
    }

    @Test func missingRateIsShown() {
        let annotations = MathSheet.evaluate(lines: ["math", "10 EUR in CHF ="], from: 1, style: .german)
        #expect(annotations[1] == LineAnnotation(text: "Kurs CHF?", kind: .error))
    }

    @Test func sumNoteAddsConvertedValues() {
        let annotations = AggregateSheet.evaluate(
            .sum, lines: ["sum", "Hotel 100 USD in EUR =", "Essen 20"], style: .german,
            converter: UnitConverter(rates: ["USD": 1.25])
        )
        #expect(annotations[1]?.text == "80 EUR")
        #expect(annotations[0]?.text == "100")
    }
}

struct CurrencyRatesTests {
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
      <gesmes:subject>Reference rates</gesmes:subject>
      <Cube>
        <Cube time='2026-11-23'>
          <Cube currency='USD' rate='1.0812'/>
          <Cube currency='JPY' rate='162.35'/>
          <Cube currency='GBP' rate='0.8431'/>
        </Cube>
      </Cube>
    </gesmes:Envelope>
    """

    @Test func parsesECBFile() throws {
        let parsed = try #require(ECBReferenceRates.parse(Data(xml.utf8)))
        #expect(parsed.rates == ["USD": 1.0812, "JPY": 162.35, "GBP": 0.8431])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        #expect(parsed.date.map { calendar.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2026, month: 11, day: 23))
    }

    @Test func rejectsGarbage() {
        #expect(ECBReferenceRates.parse(Data("<html>Fehler</html>".utf8)) == nil)
        #expect(ECBReferenceRates.parse(Data()) == nil)
    }

    @Test func ownRatesWin() {
        var rates = CurrencyRates()
        rates.fetched = ["USD": 1.08, "GBP": 0.84]
        rates.manual = ["USD": 1.10, "BTC": 0.000011]
        #expect(rates.effective == ["USD": 1.10, "GBP": 0.84, "BTC": 0.000011, "EUR": 1])
    }

    @Test func updateDueAboutDaily() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var rates = CurrencyRates()
        #expect(rates.isUpdateDue(now: now))
        rates.lastUpdate = now.addingTimeInterval(-3600)
        #expect(!rates.isUpdateDue(now: now))
        rates.lastUpdate = now.addingTimeInterval(-21 * 3600)
        #expect(rates.isUpdateDue(now: now))
    }

    @MainActor
    @Test func preferencesRoundTripAndOffByDefault() {
        let storage = TemporaryDefaults()
        let preferences = AppPreferences(defaults: storage.defaults)
        #expect(preferences.currencyAutoUpdate == false)
        var rates = CurrencyRates()
        rates.manual = ["CHF": 0.95]
        preferences.currencyRates = rates
        #expect(AppPreferences(defaults: storage.defaults).currencyRates == rates)
        #expect(preferences.unitConverter.rates["CHF"] == 0.95)
    }
}
