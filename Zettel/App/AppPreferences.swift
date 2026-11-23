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
        static let toggleWindowHotKey = "hotKey.toggleWindow"
        static let isPanelPinned = "panel.isPinned"
        static let panelFrame = "panel.frame"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
