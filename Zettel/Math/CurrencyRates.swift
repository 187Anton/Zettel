import Foundation

/// Exchange rates as "1 EUR = x". Own rates always win over downloaded ones.
struct CurrencyRates: Codable, Equatable, Sendable {
    /// From the ECB (opt-in).
    var fetched: [String: Double] = [:]
    /// Date of the downloaded rates (as published by the ECB).
    var fetchedDate: Date?
    /// When the download was last attempted successfully.
    var lastUpdate: Date?
    /// Entered by the user.
    var manual: [String: Double] = [:]

    var effective: [String: Double] {
        var rates = fetched.merging(manual) { _, own in own }
        rates["EUR"] = 1
        return rates
    }

    /// Download needed if never done or the last one is older than about a day.
    func isUpdateDue(now: Date) -> Bool {
        guard let lastUpdate else { return true }
        return now.timeIntervalSince(lastUpdate) > 20 * 3600
    }
}

/// The ECB's daily euro reference rates (about 30 currencies, published on
/// working days around 16:00 CET). Free, no account or key.
enum ECBReferenceRates {
    static let url = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!

    static func parse(_ data: Data) -> (date: Date?, rates: [String: Double])? {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.rates.isEmpty else { return nil }
        return (delegate.date, delegate.rates)
    }

    /// Downloads the rates. Ephemeral session: no cookies, no cache, no stored credentials.
    static func download() async throws -> (date: Date?, rates: [String: Double]) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let parsed = parse(data) else {
            throw URLError(.badServerResponse)
        }
        return parsed
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var rates: [String: Double] = [:]
        var date: Date?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            guard elementName == "Cube" else { return }
            if let time = attributes["time"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
                formatter.dateFormat = "yyyy-MM-dd"
                date = formatter.date(from: time)
            }
            if let code = attributes["currency"], let rate = attributes["rate"].flatMap(Double.init), rate > 0, code.count == 3 {
                rates[code.uppercased()] = rate
            }
        }
    }
}
