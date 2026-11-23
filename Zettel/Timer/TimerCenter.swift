import Foundation

/// Something that calls `tick` about once per second while started.
@MainActor
protocol TickScheduler: AnyObject {
    var isRunning: Bool { get }
    func start(_ tick: @escaping @MainActor () -> Void)
    func stop()
}

/// `Foundation.Timer` on the main run loop. While it runs, App Nap is disabled so
/// the countdown and the alert stay on time; nothing runs when no timer is active.
@MainActor
final class RunLoopTickScheduler: TickScheduler {
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    var isRunning: Bool { timer != nil }

    func start(_ tick: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Timer läuft"
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}

/// A timer reached the end of a countdown or switched an interval phase.
struct TimerEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case finished
        case phaseStarted(RunningTimer.Phase)
    }

    var timer: RunningTimer
    var kind: Kind
}

/// All timers of the app. Independent of any window: timers keep running when
/// the note window is closed. UI-free; the tick source and clock are injected.
@MainActor
final class TimerCenter {
    static let didChange = Notification.Name("TimerCenterDidChange")

    private let now: () -> Date
    private let calendar: Calendar
    private let scheduler: TickScheduler
    /// Called for each finished countdown or interval switch (notification, sound).
    var onEvent: ((TimerEvent) -> Void)?

    private(set) var timers: [RunningTimer] = []

    init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current, scheduler: TickScheduler? = nil) {
        self.now = now
        self.calendar = calendar
        self.scheduler = scheduler ?? RunLoopTickScheduler()
    }

    var date: Date { now() }
    var isTicking: Bool { scheduler.isRunning }

    // MARK: Lookup

    func timer(id: UUID) -> RunningTimer? {
        timers.first { $0.id == id }
    }

    /// The timer started from this line of this note, if any.
    func timer(noteID: String, line: String) -> RunningTimer? {
        let command = TimerCommand.normalized(line)
        return timers.last { $0.noteID == noteID && $0.command == command }
    }

    /// Timers shown in the menu bar and the status menu (not finished).
    var activeTimers: [RunningTimer] {
        let date = now()
        return timers.filter { $0.status(at: date) != .finished }
    }

    /// The timer whose time matters most: the countdown ending soonest, else a stopwatch.
    var primaryTimer: RunningTimer? {
        let date = now()
        let running = activeTimers.filter { !$0.isPaused }
        func remaining(_ timer: RunningTimer) -> TimeInterval? {
            switch timer.status(at: date) {
            case .countdown(let remaining), .interval(_, let remaining): remaining
            default: nil
            }
        }
        return running.filter { remaining($0) != nil }.min { remaining($0)! < remaining($1)! }
            ?? running.first ?? activeTimers.first
    }

    // MARK: Changes

    /// Starts a timer for a line. Replaces a finished or stopped timer of the same line.
    @discardableResult
    func start(_ spec: TimerSpec, noteID: String, line: String) -> RunningTimer {
        let command = TimerCommand.normalized(line)
        timers.removeAll { $0.noteID == noteID && $0.command == command }
        let timer = RunningTimer(noteID: noteID, command: command, spec: spec, at: now(), calendar: calendar)
        timers.append(timer)
        changed()
        return timer
    }

    func apply(_ control: TimerControl, to id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        switch control {
        case .togglePause: timers[index].togglePause(at: now())
        case .restart: timers[index].restart(at: now())
        case .stop: timers.remove(at: index)
        }
        changed()
    }

    /// Target of `timer p/r/s` typed in a note: the nearest timer line above the
    /// command, else the newest timer of the note, else the newest timer at all.
    func target(noteID: String, linesAbove: [String]) -> RunningTimer? {
        for line in linesAbove.reversed() {
            if let timer = timer(noteID: noteID, line: line) { return timer }
        }
        return timers.last { $0.noteID == noteID } ?? timers.last
    }

    // MARK: Ticking

    /// Reports phase ends and keeps the tick running only while needed.
    func tick() {
        let date = now()
        for index in timers.indices where !timers[index].isPaused {
            let ends = timers[index].phaseEnds(at: date)
            guard ends > timers[index].reportedPhaseEnds else { continue }
            timers[index].reportedPhaseEnds = ends
            let timer = timers[index]
            switch timer.status(at: date) {
            case .finished: onEvent?(TimerEvent(timer: timer, kind: .finished))
            case .interval(let phase, _): onEvent?(TimerEvent(timer: timer, kind: .phaseStarted(phase)))
            default: break
            }
        }
        changed()
    }

    private func changed() {
        let date = now()
        if timers.contains(where: { $0.isTicking(at: date) }) {
            scheduler.start { [weak self] in self?.tick() }
        } else {
            scheduler.stop()
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
