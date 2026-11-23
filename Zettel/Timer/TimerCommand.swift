import Foundation

/// What a timer does.
enum TimerKind: Equatable, Sendable {
    /// Counts up.
    case stopwatch
    /// Counts down a duration in seconds.
    case countdown(TimeInterval)
    /// Counts down to a time of day (resolved to a duration when started).
    case until(hour: Int, minute: Int)
    /// Alternating work and break phases (seconds), repeating.
    case intervals(work: TimeInterval, rest: TimeInterval)

    static let pomodoro = TimerKind.intervals(work: 25 * 60, rest: 5 * 60)
}

struct TimerSpec: Equatable, Sendable {
    var kind: TimerKind
    var name: String?
}

enum TimerControl: Equatable, Sendable {
    case togglePause
    case restart
    case stop
}

/// A `timer …` line, typed at the start of any line.
///
/// | Line | Meaning |
/// |---|---|
/// | `timer` | stopwatch |
/// | `timer 10` | 10 minutes |
/// | `timer 3.5`, `timer 3,5`, `timer 3:30` | 3:30 minutes |
/// | `timer 21:15` | countdown to 21:15 (two-digit hour 00–23) |
/// | `timer 5: Wäsche` | named countdown (also `timer: Name` for a stopwatch) |
/// | `timer pomo` | 25 min work / 5 min break |
/// | `timer 5 1` | 5 min work / 1 min break |
/// | `timer p` / `timer r` / `timer s`, `timer 0` | pause–resume / restart / stop |
enum TimerCommand: Equatable, Sendable {
    case start(TimerSpec)
    case control(TimerControl)

    static let maxDuration: TimeInterval = 24 * 60 * 60

    init?(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("timer") else { return nil }
        let afterKeyword = trimmed.dropFirst(5)
        // "timer" must be a whole word: "timer", "timer 10", "timer: Name".
        if let next = afterKeyword.first, !(next.isWhitespace || next == ":") { return nil }

        let (specText, name) = Self.splitName(String(afterKeyword))
        let words = specText.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }

        switch words {
        case []:
            self = .start(TimerSpec(kind: .stopwatch, name: name))
        case ["p"], ["pause"]:
            guard name == nil else { return nil }
            self = .control(.togglePause)
        case ["r"], ["restart"]:
            guard name == nil else { return nil }
            self = .control(.restart)
        case ["s"], ["stop"], ["0"]:
            guard name == nil else { return nil }
            self = .control(.stop)
        case ["pomo"]:
            self = .start(TimerSpec(kind: .pomodoro, name: name))
        case let pair where pair.count == 2:
            guard let work = Self.minutes(pair[0]), let rest = Self.minutes(pair[1]) else { return nil }
            self = .start(TimerSpec(kind: .intervals(work: work, rest: rest), name: name))
        case let single where single.count == 1:
            guard let kind = Self.durationOrTime(single[0]) else { return nil }
            self = .start(TimerSpec(kind: kind, name: name))
        default:
            return nil
        }
    }

    /// Splits at the first `:` that is not part of a time (`5:30`): `" 5: Wäsche"` → (" 5", "Wäsche").
    private static func splitName(_ text: String) -> (String, String?) {
        let characters = Array(text)
        for (index, character) in characters.enumerated() where character == ":" {
            let previousIsDigit = index > 0 && characters[index - 1].isNumber
            let nextIsDigit = index + 1 < characters.count && characters[index + 1].isNumber
            if previousIsDigit && nextIsDigit { continue }
            let name = String(characters[(index + 1)...]).trimmingCharacters(in: .whitespaces)
            return (String(characters[..<index]), name.isEmpty ? nil : name)
        }
        return (text, nil)
    }

    /// `10`, `3.5`, `3,5` → seconds (minutes × 60).
    private static func minutes(_ text: String) -> TimeInterval? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value > 0, value * 60 <= maxDuration
        else { return nil }
        return (value * 60).rounded()
    }

    private static func durationOrTime(_ text: String) -> TimerKind? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard let first = Int(parts[0]), let second = Int(parts[1]),
                  parts[1].count == 2, second < 60, first >= 0
            else { return nil }
            // Two-digit hour up to 23 is a time of day, otherwise minutes:seconds.
            if parts[0].count == 2, first <= 23 {
                return .until(hour: first, minute: second)
            }
            let seconds = TimeInterval(first * 60 + second)
            guard seconds > 0, seconds <= maxDuration else { return nil }
            return .countdown(seconds)
        }
        return minutes(text).map { .countdown($0) }
    }

    /// A line in normalized form, used to find the timer that belongs to it.
    static func normalized(_ line: String) -> String {
        line.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
