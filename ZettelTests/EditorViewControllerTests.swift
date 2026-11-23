import AppKit
import Testing
@testable import Zettel

/// Runs the real text view inside the test host.
@MainActor
struct EditorViewControllerTests {
    private let clock = TestClock()

    private func makeEditor(store: NoteStore? = nil) throws -> (EditorViewController, NoteStore) {
        let store = try store ?? NoteStore.inMemory()
        let editor = EditorViewController(model: try makeModel(store: store, clock: clock))
        _ = editor.view
        return (editor, store)
    }

    /// Simulates typing, including undo registration and delegate callbacks.
    private func type(_ text: String, in editor: EditorViewController) {
        editor.textView.insertText(text, replacementRange: editor.textView.selectedRange())
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
}
