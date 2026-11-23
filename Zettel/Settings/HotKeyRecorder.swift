import AppKit
import SwiftUI

/// Button that records a key combination: click, then press the keys (Esc cancels).
/// At least ⌘, ⌥ or ⌃ is required, so normal typing keys are never taken.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { combo = $0 }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.combo = combo
    }
}

final class RecorderButton: NSButton {
    var combo: KeyCombo? {
        didSet { if !isRecording { updateTitle() } }
    }
    var onRecord: ((KeyCombo) -> Void)?
    private(set) var isRecording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        target = self
        action = #selector(startRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    @objc func startRecording() {
        isRecording = true
        title = Strings.Settings.pressShortcut
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    /// ⌘-combinations arrive here before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    func record(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc
            stopRecording()
            return
        }
        let modifiers = KeyModifiers(event.modifierFlags)
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
            NSSound.beep()
            return
        }
        let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        self.combo = combo
        onRecord?(combo)
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        updateTitle()
    }

    private func updateTitle() {
        title = combo?.displayString ?? "–"
    }
}
