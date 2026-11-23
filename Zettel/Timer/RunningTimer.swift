import Foundation

/// A started timer. Pure value: everything is computed from absolute dates, so
/// sleep, wake and late ticks never make it drift.
struct RunningTimer: Identifiable, Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case work, rest
    }

    enum Status: Equatable, Sendable {
        case stopwatch(elapsed: TimeInterval)
        case countdown(remaining: TimeInterval)
        case interval(phase: Phase, remaining: TimeInterval)
        case finished
    }

    let id: UUID
    var noteID: String
    /// Normalized line the timer was started from.
    var command: String
    var name: String?
    /// The kind with `.until` resolved to a countdown when started.
    var kind: TimerKind
    var startedAt: Date
    var pausedAt: Date?
    var pausedDuration: TimeInterval = 0
    /// Phase ends already reported (finish of a countdown, each interval switch).
    var reportedPhaseEnds = 0

    init(id: UUID = UUID(), noteID: String, command: String, spec: TimerSpec, at date: Date, calendar: Calendar = .current) {
        self.id = id
        self.noteID = noteID
        self.command = command
        self.name = spec.name
        self.kind = Self.resolve(spec.kind, at: date, calendar: calendar)
        self.startedAt = date
    }

    /// `.until(21, 15)` → countdown to the next 21:15 (today or tomorrow).
    static func resolve(_ kind: TimerKind, at date: Date, calendar: Calendar) -> TimerKind {
        guard case .until(let hour, let minute) = kind else { return kind }
        let target = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime
        ) ?? date
        return .countdown(target.timeIntervalSince(date).rounded())
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        let end = pausedAt ?? date
        return max(0, end.timeIntervalSince(startedAt) - pausedDuration)
    }

    func status(at date: Date) -> Status {
        let elapsed = elapsed(at: date)
        switch kind {
        case .stopwatch:
            return .stopwatch(elapsed: elapsed)
        case .countdown(let duration):
            return elapsed >= duration ? .finished : .countdown(remaining: duration - elapsed)
        case .intervals(let work, let rest):
            let cycle = work + rest
            let position = elapsed.truncatingRemainder(dividingBy: cycle)
            return position < work
                ? .interval(phase: .work, remaining: work - position)
                : .interval(phase: .rest, remaining: cycle - position)
        case .until:
            return .finished // resolved in init
        }
    }

    /// Needs the once-per-second tick (not paused, not finished).
    func isTicking(at date: Date) -> Bool {
        !isPaused && status(at: date) != .finished
    }

    /// Number of phase ends up to `date`.
    func phaseEnds(at date: Date) -> Int {
        let elapsed = elapsed(at: date)
        switch kind {
        case .stopwatch, .until:
            return 0
        case .countdown(let duration):
            return elapsed >= duration ? 1 : 0
        case .intervals(let work, let rest):
            let cycle = work + rest
            let cycles = (elapsed / cycle).rounded(.down)
            let position = elapsed - cycles * cycle
            return Int(cycles) * 2 + (position >= work ? 1 : 0)
        }
    }

    // MARK: Changes

    mutating func togglePause(at date: Date) {
        if let pausedAt {
            pausedDuration += date.timeIntervalSince(pausedAt)
            self.pausedAt = nil
        } else if status(at: date) != .finished {
            pausedAt = date
        }
    }

    mutating func restart(at date: Date) {
        startedAt = date
        pausedAt = nil
        pausedDuration = 0
        reportedPhaseEnds = 0
    }
}

/// Text formats for timers.
enum TimerFormat {
    /// `65` → "1:05", `3725` → "1:02:05". Countdowns round up, so 0:01 shows until the end.
    static func clock(_ seconds: TimeInterval, roundUp: Bool = false) -> String {
        let total = max(0, Int(roundUp ? seconds.rounded(.up) : seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Text shown next to the timer line.
    static func status(_ timer: RunningTimer, at date: Date) -> String {
        let text: String = switch timer.status(at: date) {
        case .stopwatch(let elapsed): clock(elapsed)
        case .countdown(let remaining): clock(remaining, roundUp: true)
        case .interval(let phase, let remaining): "\(phase == .work ? "Arbeit" : "Pause") \(clock(remaining, roundUp: true))"
        case .finished: "✓ fertig"
        }
        return timer.isPaused ? "⏸ " + text : text
    }

    /// Short text for the menu bar. Minutes only (seconds in the last minute), so
    /// the menu bar redraws once per minute: redrawing it is what costs CPU.
    static func menuBar(_ timer: RunningTimer, at date: Date) -> String {
        switch timer.status(at: date) {
        case .stopwatch(let elapsed): coarse(minutes: Int(elapsed / 60))
        case .countdown(let remaining), .interval(_, let remaining):
            remaining <= 60 ? clock(remaining, roundUp: true) : coarse(minutes: Int((remaining / 60).rounded(.up)))
        case .finished: "✓"
        }
    }

    /// `9` → "9 min", `75` → "1:15 h".
    static func coarse(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d:%02d h", minutes / 60, minutes % 60)
    }

    /// Label in menus and notifications: the name, or a description of the kind.
    static func title(_ timer: RunningTimer) -> String {
        if let name = timer.name { return name }
        switch timer.kind {
        case .stopwatch: return "Stoppuhr"
        case .countdown(let duration): return "Timer \(clock(duration))"
        case .intervals(let work, let rest):
            return timer.kind == .pomodoro ? "Pomodoro" : "Intervall \(clock(work)) / \(clock(rest))"
        case .until: return "Timer"
        }
    }
}
