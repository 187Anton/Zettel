import Foundation

/// Finds web links in note text (NSDataDetector) and computes their short form.
enum LinkDetection {
    struct Link: Equatable, Sendable {
        var range: NSRange
        var url: URL
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func links(in text: String, range: NSRange? = nil) -> [Link] {
        guard let detector else { return [] }
        let ns = text as NSString
        let searchRange = range ?? NSRange(location: 0, length: ns.length)
        return detector.matches(in: text, range: searchRange).compactMap { match in
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return Link(range: match.range, url: url)
        }
    }

    static let shortenThreshold = 40
    static let keepStart = 28
    static let keepEnd = 10

    /// For long links: the part in the middle that is hidden behind "…", in text
    /// coordinates. `nil` for links that are short enough.
    static func hiddenRange(of link: Link) -> NSRange? {
        guard link.range.length > shortenThreshold else { return nil }
        return NSRange(location: link.range.location + keepStart, length: link.range.length - keepStart - keepEnd)
    }
}
