import Foundation

/// Automatic database backups in `Application Support/Zettel/Backups`.
/// No timer: `backupIfDue` is called at launch and when the window opens.
final class BackupManager: Sendable {
    enum Interval: String, CaseIterable, Sendable {
        case hourly, daily, weekly, never

        var title: String {
            switch self {
            case .hourly: "Stündlich"
            case .daily: "Täglich"
            case .weekly: "Wöchentlich"
            case .never: "Nie"
            }
        }

        var seconds: TimeInterval? {
            switch self {
            case .hourly: 3600
            case .daily: 86400
            case .weekly: 7 * 86400
            case .never: nil
            }
        }
    }

    struct Backup: Identifiable, Equatable, Sendable {
        var id: URL { url }
        var url: URL
        var date: Date
        var size: Int64
    }

    let directory: URL
    let keep: Int
    private let store: NoteStore

    init(store: NoteStore, directory: URL, keep: Int = 10) {
        self.store = store
        self.directory = directory
        self.keep = keep
    }

    static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Zettel/Backups", isDirectory: true)
    }

    private static let prefix = "Zettel-"
    private static let fileExtension = "sqlite"

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    /// All backups, newest first.
    func backups() -> [Backup] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        )) ?? []
        let formatter = Self.formatter()
        return urls.compactMap { url -> Backup? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == Self.fileExtension, name.hasPrefix(Self.prefix),
                  let date = formatter.date(from: String(name.dropFirst(Self.prefix.count)))
            else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return Backup(url: url, date: date, size: size)
        }
        .sorted { $0.date > $1.date }
    }

    @discardableResult
    func createBackup(at date: Date = Date()) throws -> Backup {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var name = Self.prefix + Self.formatter().string(from: date)
        // Two backups within the same second: keep both.
        var url = directory.appendingPathComponent(name).appendingPathExtension(Self.fileExtension)
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            name = Self.prefix + Self.formatter().string(from: date.addingTimeInterval(Double(counter)))
            url = directory.appendingPathComponent(name).appendingPathExtension(Self.fileExtension)
            counter += 1
        }
        try store.backup(to: url)
        prune()
        return backups().first { $0.url == url } ?? Backup(url: url, date: date, size: 0)
    }

    /// Creates a backup if the newest one is older than the interval.
    @discardableResult
    func backupIfDue(interval: Interval, now: Date = Date()) throws -> Backup? {
        guard let seconds = interval.seconds else { return nil }
        if let latest = backups().first, now.timeIntervalSince(latest.date) < seconds { return nil }
        return try createBackup(at: now)
    }

    /// Replaces all notes with a backup. A backup of the current state is made first,
    /// so a restore can itself be undone.
    func restore(_ backup: Backup, now: Date = Date()) throws {
        try createBackup(at: now)
        try store.restore(from: backup.url)
    }

    /// Keeps the newest `keep` backups.
    private func prune() {
        for backup in backups().dropFirst(keep) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }
}
