import CoreGraphics
import Foundation

/// Typed access to persisted settings. Backed by `UserDefaults`, injectable for tests.
@MainActor
final class AppPreferences {
    /// Keys are shared with `@AppStorage` in the settings view.
    enum Key {
        static let newNoteAfterIdleMinutes = "notes.newNoteAfterIdleMinutes"
        static let checkedItemBehavior = "lists.checkedItemBehavior"
        static let mathDecimals = "math.decimals"
        static let mathDecimalSeparator = "math.decimalSeparator"
        static let mathGroupingSeparator = "math.groupingSeparator"
        static let noteExpiry = "notes.expiry"
        static let trashPeriod = "notes.trashPeriod"
        static let slotShortcuts = "notes.slotShortcuts"
        static let backupInterval = "backup.interval"
        static let theme = "appearance.theme"
        static let fontSize = "appearance.fontSize"
        static let transparentWindow = "appearance.transparentWindow"
        static let hideMarkdownMarkers = "appearance.hideMarkdownMarkers"
        static let currencyRates = "currency.rates"
        static let currencyAutoUpdate = "currency.autoUpdate"
        static let timerNotifications = "timer.notifications"
        static let timerSound = "timer.sound"
        static let timerSoundName = "timer.soundName"
        static let timerInMenuBar = "timer.showInMenuBar"
        static let toggleWindowHotKey = "hotKey.toggleWindow"
        static let isPanelPinned = "panel.isPinned"
        static let panelFrame = "panel.frame"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.timerNotifications: true,
            Key.timerSound: true,
            Key.timerSoundName: "Glass",
            Key.timerInMenuBar: true,
            Key.hideMarkdownMarkers: true,
        ])
    }

    /// Unchanged stack notes move to the trash after this period. Default: never.
    var noteExpiry: NoteRetention.Expiry {
        get { defaults.string(forKey: Key.noteExpiry).flatMap(NoteRetention.Expiry.init(rawValue:)) ?? .never }
        set { defaults.set(newValue.rawValue, forKey: Key.noteExpiry) }
    }

    /// The trash is emptied after this period. Default: 30 days.
    var trashPeriod: NoteRetention.TrashPeriod {
        get {
            guard defaults.object(forKey: Key.trashPeriod) != nil else { return .days30 }
            return NoteRetention.TrashPeriod(rawValue: defaults.integer(forKey: Key.trashPeriod)) ?? .days30
        }
        set { defaults.set(newValue.rawValue, forKey: Key.trashPeriod) }
    }

    /// ⌘1–⌘9 select slots also while in the stack.
    var slotShortcuts: Bool {
        get { defaults.bool(forKey: Key.slotShortcuts) }
        set { defaults.set(newValue, forKey: Key.slotShortcuts) }
    }

    var backupInterval: BackupManager.Interval {
        get { defaults.string(forKey: Key.backupInterval).flatMap(BackupManager.Interval.init(rawValue:)) ?? .daily }
        set { defaults.set(newValue.rawValue, forKey: Key.backupInterval) }
    }

    enum Theme: String, CaseIterable, Sendable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: "Wie System"
            case .light: "Hell"
            case .dark: "Dunkel"
            }
        }
    }

    var theme: Theme {
        get { defaults.string(forKey: Key.theme).flatMap(Theme.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.theme) }
    }

    static let defaultFontSize: Double = 14
    static let fontSizeRange: ClosedRange<Double> = 10...28

    /// Text size of the editor (⌘+ / ⌘− / ⌘0).
    var fontSize: Double {
        get {
            let value = defaults.double(forKey: Key.fontSize)
            return value == 0 ? Self.defaultFontSize : min(max(value, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        }
        set { defaults.set(min(max(newValue, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound), forKey: Key.fontSize) }
    }

    /// Hide `**`, `_`, `#` … except in the line with the cursor. On by default.
    var hideMarkdownMarkers: Bool {
        get { defaults.bool(forKey: Key.hideMarkdownMarkers) }
        set { defaults.set(newValue, forKey: Key.hideMarkdownMarkers) }
    }

    var transparentWindow: Bool {
        get { defaults.bool(forKey: Key.transparentWindow) }
        set { defaults.set(newValue, forKey: Key.transparentWindow) }
    }

    var currencyRates: CurrencyRates {
        get {
            guard let data = defaults.data(forKey: Key.currencyRates),
                  let rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
            else { return CurrencyRates() }
            return rates
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.currencyRates) }
    }

    /// Daily download of the ECB rates. Off by default: the only network access of Zettel.
    var currencyAutoUpdate: Bool {
        get { defaults.bool(forKey: Key.currencyAutoUpdate) }
        set { defaults.set(newValue, forKey: Key.currencyAutoUpdate) }
    }

    var unitConverter: UnitConverter {
        UnitConverter(rates: currencyRates.effective)
    }

    var timerNotifications: Bool {
        get { defaults.bool(forKey: Key.timerNotifications) }
        set { defaults.set(newValue, forKey: Key.timerNotifications) }
    }

    var timerSound: Bool {
        get { defaults.bool(forKey: Key.timerSound) }
        set { defaults.set(newValue, forKey: Key.timerSound) }
    }

    var timerSoundName: String {
        get { defaults.string(forKey: Key.timerSoundName) ?? "Glass" }
        set { defaults.set(newValue, forKey: Key.timerSoundName) }
    }

    /// Show the remaining time of the most urgent timer next to the menu bar icon.
    var timerInMenuBar: Bool {
        get { defaults.bool(forKey: Key.timerInMenuBar) }
        set { defaults.set(newValue, forKey: Key.timerInMenuBar) }
    }

    var toggleWindowHotKey: KeyCombo {
        get {
            guard let data = defaults.data(forKey: Key.toggleWindowHotKey),
                  let combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
            else { return .defaultToggleWindow }
            return combo
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.toggleWindowHotKey)
        }
    }

    /// Minutes without focus after which the window opens with a blank note; 0 = off.
    var newNoteAfterIdleMinutes: Int {
        get { max(0, defaults.integer(forKey: Key.newNoteAfterIdleMinutes)) }
        set { defaults.set(max(0, newValue), forKey: Key.newNoteAfterIdleMinutes) }
    }

    var checkedItemBehavior: CheckedItemBehavior {
        get { defaults.string(forKey: Key.checkedItemBehavior).flatMap(CheckedItemBehavior.init(rawValue:)) ?? .keep }
        set { defaults.set(newValue.rawValue, forKey: Key.checkedItemBehavior) }
    }

    /// Number format for `math` notes. Defaults follow the system region.
    var numberStyle: NumberStyle {
        let system = NumberStyle.system
        let decimals = defaults.object(forKey: Key.mathDecimals) as? Int ?? -1
        let decimal = defaults.string(forKey: Key.mathDecimalSeparator)?.first ?? system.decimalSeparator
        let grouping: Character? = switch defaults.string(forKey: Key.mathGroupingSeparator) {
        case nil: system.groupingSeparator
        case "none": nil
        case let value?: value.first
        }
        return NumberStyle(decimalSeparator: decimal, groupingSeparator: grouping, decimals: decimals < 0 ? nil : decimals)
    }

    var isPanelPinned: Bool {
        get { defaults.bool(forKey: Key.isPanelPinned) }
        set { defaults.set(newValue, forKey: Key.isPanelPinned) }
    }

    /// Last frame of the note window in screen coordinates, `nil` if never saved.
    var panelFrame: CGRect? {
        get {
            guard let values = defaults.array(forKey: Key.panelFrame) as? [Double], values.count == 4
            else { return nil }
            let frame = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            return frame.width > 0 && frame.height > 0 ? frame : nil
        }
        set {
            guard let frame = newValue else {
                defaults.removeObject(forKey: Key.panelFrame)
                return
            }
            defaults.set(
                [frame.origin.x, frame.origin.y, frame.width, frame.height].map(Double.init),
                forKey: Key.panelFrame
            )
        }
    }
}
