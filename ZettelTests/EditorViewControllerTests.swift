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
            // Like the keyboard: no explicit replacement range.
            editor.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
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

    // Undo right after the auto-conversion: see RealEventTests (needs real key events).

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

    @Test func arrowCursorOnlyOverCheckbox() throws {
        let (editor, _) = try makeEditor()
        typeKeys("[] Milch", in: editor)
        let textView = editor.textView!
        let layoutManager = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let origin = textView.textContainerOrigin

        func center(ofCharacter index: Int) -> NSPoint {
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            return NSPoint(x: rect.midX + origin.x, y: rect.midY + origin.y)
        }

        #expect(textView.cursor(at: center(ofCharacter: 0)) === NoteTextView.checkboxCursor)
        #expect(textView.cursor(at: center(ofCharacter: 4)) == nil) // inside "Milch"
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

    // MARK: Keywords & math

    @Test func mathNoteShowsResultsAndUpdatesLive() throws {
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: "math: Budget\npreis : 25\npreis * 3 =", date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        #expect(editor.textView.annotations[2]?.text == "75")

        editor.textView.setSelectedRange(NSRange(location: 23, length: 0)) // after "25"
        typeKeys("0", in: editor)
        #expect(editor.textView.annotations[2]?.text == "750")
    }

    @Test func plainNoteHasNoResults() throws {
        let (editor, _) = try makeEditor()
        typeKeys("1 + 1 =", in: editor)
        #expect(editor.textView.annotations.isEmpty)
    }

    @Test func slashAtLineStartOpensPickerAndDigitChooses() throws {
        let (editor, store) = try makeEditor()
        typeKeys("/", in: editor)
        let picker = try #require(editor.textView.keywordPicker)

        asEvent(editor) { _ = picker.handleKey(keyCode: 19, characters: "2") }

        #expect(!editor.textView.isShowingKeywordPicker)
        #expect(editor.textView.string == "math")
        typeKeys("\n2 * 21 =", in: editor)
        #expect(editor.textView.annotations[1]?.text == "42")
        editor.flush()
        #expect(try store.note(id: editor.model.current.id)?.text == "math\n2 * 21 =")
    }

    @Test func slashInsideTextOpensNoPicker() throws {
        let (editor, _) = try makeEditor()
        typeKeys("a/b", in: editor)
        #expect(!editor.textView.isShowingKeywordPicker)
        #expect(editor.textView.string == "a/b")
    }

    @Test func secondSlashClosesPickerForComments() throws {
        let (editor, _) = try makeEditor()
        typeKeys("/", in: editor)
        #expect(editor.textView.isShowingKeywordPicker)
        editor.textView.closeKeywordPicker() // what keyDown does for any other key
        typeKeys("/ Kommentar", in: editor)
        #expect(editor.textView.string == "// Kommentar")
    }

    @Test func listNoteMakesEveryLineACheckbox() throws {
        let (editor, store) = try makeEditor()
        typeKeys("/", in: editor)
        asEvent(editor) { _ = editor.textView.keywordPicker?.handleKey(keyCode: 18, characters: "1") }
        typeKeys("\nMilch\nBrot /x", in: editor)

        #expect(editor.textView.string == "list\n☐ Milch\n☑ Brot")
        editor.flush()
        #expect(try store.note(id: editor.model.current.id)?.text == "list\n- [ ] Milch\n- [x] Brot")
    }

    @Test func listNoteEmptyLineTyping() throws {
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: "list\n- [ ] a\n", date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        typeKeys("b", in: editor)
        #expect(editor.textView.string == "list\n☐ a\n☐ b")
    }

    @Test func headerIsStyled() throws {
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: "math: Budget\n1 =", date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        let storage = try #require(editor.textView.textStorage)
        let font = storage.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.controlAccentColor)
    }

    @Test func resultLinesKeepRoomOnTheRight() throws {
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: "math\n1000 * 1000 =\nText", date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        let storage = try #require(editor.textView.textStorage)
        let resultStyle = storage.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle
        let textStyle = storage.attribute(.paragraphStyle, at: storage.length - 1, effectiveRange: nil) as? NSParagraphStyle
        #expect((resultStyle?.tailIndent ?? 0) < -20)
        #expect(textStyle?.tailIndent == 0)
    }

    @Test func sumNoteShowsTotalOnHeaderAndUpdates() throws {
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: "sum: Einkauf\nBrot 2,50\nMilch 1,20", date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        #expect(editor.textView.annotations[0]?.text == "3,7")

        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        typeKeys("\nKäse 4", in: editor)
        #expect(editor.textView.annotations[0]?.text == "7,7")

        let storage = try #require(editor.textView.textStorage)
        let header = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((header?.tailIndent ?? 0) < -20)
    }

    @Test func commentsAreMuted() throws {
        let (editor, _) = try makeEditor()
        typeKeys("// Hinweis", in: editor)
        let color = editor.textView.textStorage?.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.secondaryLabelColor)
    }

    @Test func pickerChoosesCountWithDigitFive() throws {
        let (editor, _) = try makeEditor()
        typeKeys("/", in: editor)
        asEvent(editor) { _ = editor.textView.keywordPicker?.handleKey(keyCode: 23, characters: "5") }
        #expect(editor.textView.string == "count")
        #expect(editor.textView.annotations[0]?.text == "0 Einträge · 0 Zeilen · 0 Wörter · 0 Zeichen")
    }

    /// Renders sum, avg and count notes (see `snapshot`).
    @Test func snapshotAggregates() throws {
        guard ProcessInfo.processInfo.environment["ZETTEL_SNAPSHOT"] == "1" else { return }
        for (name, text) in [
            ("editor-sum.png", "sum: Einkauf\n- [ ] Brot 2,50\n- [x] Milch 1,20\nKäse 3 * 1,99 =\n// Pfand 0,25\nNotiz ohne Zahl"),
            ("editor-count.png", "count: Text\nEin kurzer Absatz mit ein paar Wörtern.\n\n- Punkt eins\n- Punkt zwei"),
        ] {
            let store = try NoteStore.inMemory()
            try store.insert(Note(text: text, date: clock.now))
            let (editor, _) = try makeEditor(store: store)
            try renderSnapshot(editor, name: name)
        }
    }

    /// Renders a math note (see `snapshot`).
    @Test func snapshotMath() throws {
        guard ProcessInfo.processInfo.environment["ZETTEL_SNAPSHOT"] == "1" else { return }
        let store = try NoteStore.inMemory()
        try store.insert(Note(text: """
        math: Urlaub
        flug : 420
        hotel : 7 * 95
        flug + hotel =
        Essen pro Tag mal sieben Tage, großzügig gerechnet = 
        35 * 7 =
        ans + 10% =
        total =
        1 / 0 =
        // Notiz
        """, date: clock.now))
        let (editor, _) = try makeEditor(store: store)
        try renderSnapshot(editor, name: "editor-math.png")
    }

    private func renderSnapshot(_ editor: EditorViewController, name: String) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 420, height: 300))
        window.appearance = NSAppearance(named: .aqua)
        editor.view.layoutSubtreeIfNeeded()
        let view = editor.view
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        print("SNAPSHOT \(url.path)")
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
