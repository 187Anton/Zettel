import AppKit

/// Floating, non-activating panel for the notes.
///
/// Non-activating means the app the user is working in stays active while the
/// panel takes keyboard focus (like Spotlight). That is also what lets the panel
/// appear over full-screen apps without switching Spaces.
final class NotePanel: NSPanel {
    var onCommand: ((PanelCommand) -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        minSize = PanelFramePlacement.minimumSize
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let command = PanelShortcuts.command(for: event) {
            onCommand?(command)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let command = PanelShortcuts.command(for: event) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    /// Esc when a control (later: the text view) forwards `cancelOperation:`.
    override func cancelOperation(_ sender: Any?) {
        onCommand?(.close)
    }
}

extension PanelShortcuts {
    static func command(for event: NSEvent) -> PanelCommand? {
        guard event.type == .keyDown else { return nil }
        return command(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: KeyModifiers(event.modifierFlags)
        )
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: KeyModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }
}
