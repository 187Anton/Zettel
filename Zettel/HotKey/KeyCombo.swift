import Carbon.HIToolbox

/// Modifier keys of a shortcut, independent of AppKit and Carbon representations.
struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    static let control = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)

    /// Flags as expected by Carbon's `RegisterEventHotKey`.
    var carbonFlags: UInt32 {
        var flags = 0
        if contains(.control) { flags |= controlKey }
        if contains(.option) { flags |= optionKey }
        if contains(.shift) { flags |= shiftKey }
        if contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    /// Symbols in the order macOS displays them: ⌃⌥⇧⌘.
    var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

/// A keyboard shortcut identified by its physical key code (layout-independent).
struct KeyCombo: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: KeyModifiers

    /// Default shortcut to show/hide the note window: ⌥A.
    static let defaultToggleWindow = KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: .option)

    /// Printable key name for letters, digits and space; `nil` for other keys.
    /// Uses the ANSI position names. A layout-aware recorder follows with the
    /// hotkey setting in the preferences window.
    var keyName: String? {
        Self.keyNames[keyCode]
    }

    var displayString: String {
        modifiers.symbols + (keyName ?? "#\(keyCode)")
    }

    private static let keyNames: [UInt32: String] = {
        let pairs: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_Space, "Space"),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (UInt32($0.0), $0.1) })
    }()
}
