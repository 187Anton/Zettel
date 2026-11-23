import AppKit
import UserNotifications

/// Notification and sound when a countdown ends or an interval switches.
/// Both can be turned off in the settings.
@MainActor
final class TimerAlerts: NSObject {
    static let sounds = ["Glass", "Hero", "Ping", "Purr", "Submarine", "Tink"]

    private let preferences: AppPreferences
    private var didRequestAuthorization = false
    private var observer: NSObjectProtocol?

    init(preferences: AppPreferences, timerCenter: TimerCenter) {
        self.preferences = preferences
        super.init()
        UNUserNotificationCenter.current().delegate = self
        timerCenter.onEvent = { [weak self] event in self?.handle(event) }
        // Ask for permission when the first timer starts, not at app launch.
        observer = NotificationCenter.default.addObserver(
            forName: TimerCenter.didChange, object: timerCenter, queue: .main
        ) { [weak self, weak timerCenter] _ in
            MainActor.assumeIsolated {
                guard let self, timerCenter?.timers.isEmpty == false else { return }
                self.requestAuthorizationIfNeeded()
            }
        }
    }

    func handle(_ event: TimerEvent) {
        if preferences.timerNotifications {
            post(event)
        }
        if preferences.timerSound {
            NSSound(named: NSSound.Name(preferences.timerSoundName))?.play()
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard preferences.timerNotifications, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func post(_ event: TimerEvent) {
        let content = UNMutableNotificationContent()
        let title = TimerFormat.title(event.timer)
        switch event.kind {
        case .finished:
            content.title = title
            content.body = Strings.Timer.finished
        case .phaseStarted(let phase):
            content.title = phase == .work ? Strings.Timer.workPhase : Strings.Timer.breakPhase
            content.body = title
        }
        // The sound is played by the app (own setting), not by the notification.
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension TimerAlerts: UNUserNotificationCenterDelegate {
    /// Show banners even while Zettel is the active app (e.g. settings open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
