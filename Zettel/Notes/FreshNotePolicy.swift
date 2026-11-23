import Foundation

/// "Nach X Minuten ohne Fokus mit neuer leerer Notiz öffnen."
enum FreshNotePolicy {
    /// Choices offered in the settings (minutes). 0 means off.
    static let choices = [0, 1, 5, 10, 15, 30, 60]

    static func shouldStartFresh(lastFocusLoss: Date?, now: Date, idleMinutes: Int) -> Bool {
        guard idleMinutes > 0, let lastFocusLoss else { return false }
        return now.timeIntervalSince(lastFocusLoss) >= TimeInterval(idleMinutes * 60)
    }
}
