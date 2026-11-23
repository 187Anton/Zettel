import Foundation
import Testing
@testable import Zettel

struct TimerCommandTests {
    @Test(arguments: [
        ("timer", TimerCommand.start(TimerSpec(kind: .stopwatch, name: nil))),
        ("Timer: Lauf", .start(TimerSpec(kind: .stopwatch, name: "Lauf"))),
        ("timer 10", .start(TimerSpec(kind: .countdown(600), name: nil))),
        ("timer 3.5", .start(TimerSpec(kind: .countdown(210), name: nil))),
        ("timer 3,5", .start(TimerSpec(kind: .countdown(210), name: nil))),
        ("timer 3:30", .start(TimerSpec(kind: .countdown(210), name: nil))),
        ("timer 45:00", .start(TimerSpec(kind: .countdown(2700), name: nil))),
        ("timer 21:15", .start(TimerSpec(kind: .until(hour: 21, minute: 15), name: nil))),
        ("timer 09:00", .start(TimerSpec(kind: .until(hour: 9, minute: 0), name: nil))),
        ("timer 21:15: Film", .start(TimerSpec(kind: .until(hour: 21, minute: 15), name: "Film"))),
        ("timer 5: Wäsche", .start(TimerSpec(kind: .countdown(300), name: "Wäsche"))),
        ("timer 5:Wäsche", .start(TimerSpec(kind: .countdown(300), name: "Wäsche"))),
        ("timer pomo", .start(TimerSpec(kind: .pomodoro, name: nil))),
        ("timer pomo: Bericht", .start(TimerSpec(kind: .pomodoro, name: "Bericht"))),
        ("timer 5 1", .start(TimerSpec(kind: .intervals(work: 300, rest: 60), name: nil))),
        ("  timer 1  ", .start(TimerSpec(kind: .countdown(60), name: nil))),
        ("timer p", .control(.togglePause)),
        ("timer r", .control(.restart)),
        ("timer s", .control(.stop)),
        ("timer 0", .control(.stop)),
        ("TIMER S", .control(.stop)),
    ])
    func parses(line: String, expected: TimerCommand) {
        #expect(TimerCommand(line: line) == expected)
    }

    @Test(arguments: [
        "timers", "timerx 5", "mein timer 5", "timer abc", "timer -5", "timer 5 1 2",
        "timer 3:5", "timer 3:75", "timer 2000", "timer p: Name", "",
    ])
    func rejects(line: String) {
        #expect(TimerCommand(line: line) == nil)
    }

    @Test func normalizesLines() {
        #expect(TimerCommand.normalized("  Timer   5:  Wäsche ") == "timer 5: wäsche")
    }
}

struct RunningTimerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func timer(_ kind: TimerKind) -> RunningTimer {
        RunningTimer(noteID: "n", command: "timer", spec: TimerSpec(kind: kind, name: nil), at: start)
    }

    @Test func countdown() {
        let t = timer(.countdown(60))
        #expect(t.status(at: start.addingTimeInterval(20)) == .countdown(remaining: 40))
        #expect(t.status(at: start.addingTimeInterval(60)) == .finished)
        #expect(t.phaseEnds(at: start.addingTimeInterval(59)) == 0)
        #expect(t.phaseEnds(at: start.addingTimeInterval(61)) == 1)
    }

    @Test func pauseFreezesTime() {
        var t = timer(.countdown(60))
        t.togglePause(at: start.addingTimeInterval(10))
        #expect(t.status(at: start.addingTimeInterval(500)) == .countdown(remaining: 50))
        t.togglePause(at: start.addingTimeInterval(500))
        #expect(t.status(at: start.addingTimeInterval(520)) == .countdown(remaining: 30))
    }

    @Test func restartResets() {
        var t = timer(.countdown(60))
        t.reportedPhaseEnds = 1
        t.restart(at: start.addingTimeInterval(100))
        #expect(t.status(at: start.addingTimeInterval(110)) == .countdown(remaining: 50))
        #expect(t.reportedPhaseEnds == 0)
    }

    @Test func stopwatchCountsUp() {
        #expect(timer(.stopwatch).status(at: start.addingTimeInterval(75)) == .stopwatch(elapsed: 75))
    }

    @Test func intervalsAlternate() {
        let t = timer(.intervals(work: 300, rest: 60))
        #expect(t.status(at: start.addingTimeInterval(100)) == .interval(phase: .work, remaining: 200))
        #expect(t.status(at: start.addingTimeInterval(330)) == .interval(phase: .rest, remaining: 30))
        #expect(t.status(at: start.addingTimeInterval(370)) == .interval(phase: .work, remaining: 290))
        #expect(t.phaseEnds(at: start.addingTimeInterval(299)) == 0)
        #expect(t.phaseEnds(at: start.addingTimeInterval(300)) == 1)
        #expect(t.phaseEnds(at: start.addingTimeInterval(360)) == 2)
        #expect(t.phaseEnds(at: start.addingTimeInterval(700)) == 3)
    }

    @Test func untilResolvesToNextOccurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 20, minute: 0))!
        let later = RunningTimer(noteID: "n", command: "", spec: TimerSpec(kind: .until(hour: 21, minute: 15), name: nil), at: now, calendar: calendar)
        #expect(later.kind == .countdown(75 * 60))
        let tomorrow = RunningTimer(noteID: "n", command: "", spec: TimerSpec(kind: .until(hour: 7, minute: 0), name: nil), at: now, calendar: calendar)
        #expect(tomorrow.kind == .countdown(11 * 3600))
    }

    @Test func formats() {
        #expect(TimerFormat.clock(0) == "0:00")
        #expect(TimerFormat.clock(65) == "1:05")
        #expect(TimerFormat.clock(3725) == "1:02:05")
        #expect(TimerFormat.clock(59.2, roundUp: true) == "1:00")
        var t = timer(.countdown(600))
        #expect(TimerFormat.status(t, at: start.addingTimeInterval(1)) == "9:59")
        t.togglePause(at: start.addingTimeInterval(1))
        #expect(TimerFormat.status(t, at: start.addingTimeInterval(1)) == "⏸ 9:59")
        #expect(TimerFormat.status(timer(.countdown(10)), at: start.addingTimeInterval(20)) == "✓ fertig")
        #expect(TimerFormat.status(timer(.pomodoro), at: start.addingTimeInterval(25 * 60 + 1)) == "Pause 4:59")
        #expect(TimerFormat.title(timer(.pomodoro)) == "Pomodoro")
    }

    @Test func menuBarShowsMinutesUntilTheLastMinute() {
        let countdown = timer(.countdown(600))
        #expect(TimerFormat.menuBar(countdown, at: start) == "10 min")
        #expect(TimerFormat.menuBar(countdown, at: start.addingTimeInterval(1)) == "10 min")
        #expect(TimerFormat.menuBar(countdown, at: start.addingTimeInterval(541)) == "0:59")
        #expect(TimerFormat.menuBar(timer(.stopwatch), at: start.addingTimeInterval(30)) == "0 min")
        #expect(TimerFormat.menuBar(timer(.stopwatch), at: start.addingTimeInterval(4500)) == "1:15 h")
        #expect(TimerFormat.menuBar(timer(.countdown(5)), at: start.addingTimeInterval(9)) == "✓")
        #expect(TimerFormat.title(timer(.countdown(300))) == "Timer 5:00")
    }
}

@MainActor
final class FakeTickScheduler: TickScheduler {
    private(set) var tick: (@MainActor () -> Void)?
    var isRunning: Bool { tick != nil }
    func start(_ tick: @escaping @MainActor () -> Void) { self.tick = tick }
    func stop() { tick = nil }
}

@MainActor
struct TimerCenterTests {
    private let clock = TestClock()
    private let scheduler = FakeTickScheduler()

    private func makeCenter() -> TimerCenter {
        TimerCenter(now: clock.closure, scheduler: scheduler)
    }

    @Test func tickRunsOnlyWhileATimerRuns() {
        let center = makeCenter()
        #expect(!scheduler.isRunning)

        let timer = center.start(TimerSpec(kind: .countdown(5), name: nil), noteID: "n", line: "timer 5")
        #expect(scheduler.isRunning)

        center.apply(.togglePause, to: timer.id)
        #expect(!scheduler.isRunning)
        center.apply(.togglePause, to: timer.id)
        #expect(scheduler.isRunning)

        center.apply(.stop, to: timer.id)
        #expect(!scheduler.isRunning)
        #expect(center.timers.isEmpty)
    }

    @Test func finishedCountdownReportsOnceAndStopsTicking() {
        let center = makeCenter()
        var events: [TimerEvent.Kind] = []
        center.onEvent = { events.append($0.kind) }
        center.start(TimerSpec(kind: .countdown(3), name: "Tee"), noteID: "n", line: "timer 0,05: Tee")

        clock.advance(seconds: 2)
        scheduler.tick?()
        #expect(events.isEmpty)

        clock.advance(seconds: 2)
        scheduler.tick?()
        #expect(events == [.finished])
        #expect(!scheduler.isRunning)
        #expect(center.timers.count == 1) // stays visible as "fertig"
        #expect(center.activeTimers.isEmpty)
    }

    @Test func intervalsReportEachSwitch() {
        let center = makeCenter()
        var events: [TimerEvent.Kind] = []
        center.onEvent = { events.append($0.kind) }
        center.start(TimerSpec(kind: .intervals(work: 10, rest: 5), name: nil), noteID: "n", line: "timer 1 1")

        for _ in 0..<16 {
            clock.advance(seconds: 1)
            scheduler.tick?()
        }
        #expect(events == [.phaseStarted(.rest), .phaseStarted(.work)])
        #expect(scheduler.isRunning)
    }

    @Test func missedTicksReportOnlyOnce() {
        let center = makeCenter()
        var events = 0
        center.onEvent = { _ in events += 1 }
        center.start(TimerSpec(kind: .countdown(60), name: nil), noteID: "n", line: "timer 1")
        clock.advance(seconds: 3600) // Mac was asleep
        scheduler.tick?()
        scheduler.tick?()
        #expect(events == 1)
    }

    @Test func startingSameLineReplacesTimer() {
        let center = makeCenter()
        center.start(TimerSpec(kind: .countdown(60), name: nil), noteID: "n", line: "timer 1")
        center.start(TimerSpec(kind: .countdown(60), name: nil), noteID: "n", line: "Timer  1")
        #expect(center.timers.count == 1)
        center.start(TimerSpec(kind: .countdown(60), name: nil), noteID: "other", line: "timer 1")
        #expect(center.timers.count == 2)
    }

    @Test func controlTargetIsNearestTimerAbove() {
        let center = makeCenter()
        let first = center.start(TimerSpec(kind: .countdown(60), name: nil), noteID: "n", line: "timer 1")
        let second = center.start(TimerSpec(kind: .countdown(120), name: nil), noteID: "n", line: "timer 2")
        #expect(center.target(noteID: "n", linesAbove: ["timer 1", "Text"])?.id == first.id)
        #expect(center.target(noteID: "n", linesAbove: ["timer 1", "timer 2", "x"])?.id == second.id)
        #expect(center.target(noteID: "n", linesAbove: [])?.id == second.id)
        #expect(center.target(noteID: "elsewhere", linesAbove: [])?.id == second.id)
    }

    @Test func primaryTimerIsSoonestCountdown() {
        let center = makeCenter()
        center.start(TimerSpec(kind: .stopwatch, name: nil), noteID: "n", line: "timer")
        let soon = center.start(TimerSpec(kind: .countdown(60), name: nil), noteID: "n", line: "timer 1")
        center.start(TimerSpec(kind: .countdown(600), name: nil), noteID: "n", line: "timer 10")
        #expect(center.primaryTimer?.id == soon.id)
    }
}
