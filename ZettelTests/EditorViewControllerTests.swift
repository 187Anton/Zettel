import AppKit
import Testing
@testable import Zettel

/// Runs the real text view inside the test host.
@MainActor
struct EditorViewControllerTests {
    private let clock = TestClock()

    private func makeEditor(
        store: NoteStore? = nil,
        behavior: CheckedItemBehavior = .keep
    ) throws -> (EditorViewController, NoteStore) {
        let store = try store ?? NoteStore.inMemory()
        let editor = EditorViewController(model: try makeModel(store: store, clock: clock)) { behavior }
        editor.undoGroupsByEvent = false
        _ = editor.view
        return (editor, store)
    }

    /// Simulates typing, including undo registration and delegate callbacks.
    /// Each call is one "event" with its own undo group.
    private func type(_ text: String, in editor: EditorViewController) {
        asEvent(editor) {
            editor.textView.insertText(text, replacementRange: editor.textView.selectedRange())
        }
    }

    /// Wraps an action in an undo group, as AppKit does for each real event.
    private func asEvent(_ editor: EditorViewController, _ action: () -> Void) {
        let undoManager = editor.currentUndoManager
        undoManager.beginUndoGrouping()
        action()
        // The action may have switched notes; close the group it was opened on.
        undoManager.endUndoGrouping()
    }

    @Test func typingUpdatesModelAndFlushSaves() throws {
        let (editor, store) = try makeEditor()
        type("Hallo Welt", in: editor)

        #expect(editor.model.current.text == "Hallo Welt")
        editor.flush()
        #expect(try store.note(id: editor.model.current.id)?.text == "Hallo Welt")
    }

    @Test func autosaveAfterPause() async throws {
        let (editor, store) = try makeEditor()
        type("Autosave", in: editor)
        #expect(try store.note(id: editor.model.current.id)?.text == "")

        try await Task.sleep(for: .milliseconds(800))
        #expect(try store.note(id: editor.model.current.id)?.text == "Autosave")
    }

    @Test func navigationShowsNoteTextAndSavesBeforeSwitching() throws {
        let (editor, store) = try makeEditor()
        type("Erste", in: editor)
        editor.perform(.newNote)
        #expect(editor.textView.string == "")

        type("Zweite", in: editor)
        editor.perform(.showOlder)

        #expect(editor.textView.string == "Erste")
        #expect(try store.stack().map(\.text).contains("Zweite"))
    }

    @Test func undoIsSeparatePerNote() throws {
        let (editor, _) = try makeEditor()
        type("Eins", in: editor)
        let firstManager = editor.currentUndoManager

        editor.perform(.newNote)
        let secondManager = editor.currentUndoManager
        #expect(firstManager !== secondManager)
        #expect(!secondManager.canUndo)

        type("Zwei", in: editor)
        #expect(secondManager.canUndo)

        editor.perform(.showOlder)
        #expect(editor.currentUndoManager === firstManager)
        firstManager.undo()
        #expect(editor.textView.string == "")
        #expect(editor.model.current.text == "")
    }

    @Test func trashShowsNextNote() throws {
        let (editor, store) = try makeEditor()
        type("Alt", in: editor)
        editor.perform(.newNote)
        type("Neu", in: editor)

        editor.perform(.trash)

        #expect(editor.textView.string == "Alt")
        #expect(try store.trashed().map(\.text) == ["Neu"])
    }

    @Test func restoresCursorPositionPerNote() throws {
        let (editor, _) = try makeEditor()
        type("Hallo Welt", in: editor)
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.perform(.newNote)
        type("x", in: editor)

        editor.perform(.showOlder)

        #expect(editor.textView.selectedRange() == NSRange(location: 5, length: 0))
    }

    // MARK: Lists

    /// Types character by character, like the keyboard does (Return via insertNewline).
    private func typeKeys(_ text: String, in editor: EditorViewController) {
        for character in text {
            if character == "\n" {
                asEvent(editor) { editor.textView.insertNewline(nil) }
            } else {
                type(String(character), in: editor)
            }
        }
    }

    @Test func typingChecklistStoresMarkdown() throws {
        let (editor, store) = try makeEditor()
        // The second Return on the empty item ends the list.
        typeKeys("Einkauf\n[] Milch\nBrot\n\nEnde", in: editor)

        #expect(editor.textView.string == "Einkauf\n☐ Milch\n☐ Brot\nEnde")
        editor.flush()
        #expect(try store.note(id: editor.model.current.id)?.text == "Einkauf\n- [ ] Milch\n- [ ] Brot\nEnde")
    }

    @Test func undoAfterAutoConversionRestoresTypedText() throws {
        let (editor, _) = try makeEditor()
        typeKeys("- ", in: editor)
        #expect(editor.textView.string == "• ")

        editor.currentUndoManager.undo()
        #expect(editor.textView.string == "- ")
        editor.currentUndoManager.undo()
        #expect(editor.textView.string == "-") // the space was its own key press
    }

    @Test func storedMarkdownIsShownAsList() throws {
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: "- [x] erledigt\n\t- Punkt", date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        #expect(editor.textView.string == "☑ erledigt\n\t• Punkt")
    }

    @Test func toggleCommandWithMoveToBottom() throws {
        let (editor, store) = try makeEditor(behavior: .moveToBottom)
        typeKeys("[] a\nb\nc", in: editor)
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))

        asEvent(editor) { editor.perform(.toggleCheckbox) }

        #expect(editor.textView.string == "☐ b\n☐ c\n☑ a")
        editor.flush()
        #expect(try store.note(id: editor.model.current.id)?.text == "- [ ] b\n- [ ] c\n- [x] a")
        editor.currentUndoManager.undo()
        #expect(editor.textView.string == "☐ a\n☐ b\n☐ c")
    }

    @Test func clickOnCheckboxSymbolToggles() throws {
        let (editor, _) = try makeEditor()
        typeKeys("[] Milch", in: editor)
        asEvent(editor) { editor.textView.toggleCheckbox(atCharacterIndex: 0) }
        #expect(editor.textView.string == "☑ Milch")
    }

    @Test func copyWritesMarkdown() throws {
        let (editor, _) = try makeEditor()
        typeKeys("[] Milch\n[x] Brot", in: editor)
        editor.textView.selectAll(nil)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.zettel.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        #expect(editor.textView.writeSelection(to: pasteboard, types: [.string]))
        #expect(pasteboard.string(forType: .string) == "- [ ] Milch\n- [x] Brot")
    }

    @Test func checkedItemsAreCrossedOut() throws {
        let (editor, _) = try makeEditor()
        typeKeys("[x] Erledigt\nOffen", in: editor)
        let storage = try #require(editor.textView.textStorage)

        let checked = storage.attribute(.strikethroughStyle, at: 3, effectiveRange: nil) as? Int
        let plain = storage.attribute(.strikethroughStyle, at: storage.length - 1, effectiveRange: nil) as? Int
        #expect(checked == NSUnderlineStyle.single.rawValue)
        #expect(plain == nil || plain == 0)
    }

    /// Renders the editor to a PNG in the test host's temporary directory when
    /// `ZETTEL_SNAPSHOT=1` is set (`TEST_RUNNER_ZETTEL_SNAPSHOT=1 xcodebuild test`).
    /// Visual check only; the path is printed.
    @Test func snapshot() throws {
        guard ProcessInfo.processInfo.environment["ZETTEL_SNAPSHOT"] == "1" else { return }
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: """
        Einkauf
        - [ ] Hafermilch
        - [x] Brot vom Bäcker
        	- [ ] Vollkorn, nicht zu dunkel und bitte mit Kürbiskernen, falls es die heute gibt
        - Notiz am Rand
        1. Erster Schritt
        2. Zweiter Schritt
        	1. Unterpunkt

        Normaler Text danach.
        """, date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 420, height: 320))
        window.appearance = NSAppearance(named: .aqua)
        editor.view.layoutSubtreeIfNeeded()

        let view = editor.view
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("editor-lists.png")
        try data.write(to: url)
        print("SNAPSHOT \(url.path)")
    }
}
