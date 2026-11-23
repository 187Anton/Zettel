import AppKit
import Carbon.HIToolbox
import Testing
@testable import Zettel

@MainActor
struct Phase9EditorTests {
    private let clock = TestClock()

    private func makeEditor(text: String? = nil, collector: PasteCollector? = nil, hideMarkers: Bool = false) throws -> (EditorViewController, NoteStore) {
        let store = try NoteStore.inMemory()
        if let text { try store.insert(Note(text: text, date: clock.now)) }
        // Automatic undo grouping stays on: these tests do not check single undo steps.
        let editor = EditorViewController(
            model: try makeModel(store: store, clock: clock),
            pasteCollector: collector,
            hidesMarkdownMarkers: { hideMarkers }
        )
        _ = editor.view
        return (editor, store)
    }

    private func type(_ text: String, in editor: EditorViewController) {
        for character in text {
            let undoManager = editor.currentUndoManager
            undoManager.beginUndoGrouping()
            if character == "\n" {
                editor.textView.insertNewline(nil)
            } else {
                editor.textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            undoManager.endUndoGrouping()
        }
    }

    // MARK: Formatting

    @Test func boldCommandAndStyling() throws {
        let (editor, store) = try makeEditor()
        type("ein Wort", in: editor)
        editor.textView.setSelectedRange(NSRange(location: 4, length: 4))
        editor.perform(.format(.bold))

        #expect(editor.textView.string == "ein **Wort**")
        let font = editor.textView.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        editor.flush()
        #expect(try store.stack().first?.text == "ein **Wort**")
    }

    @Test func headingIsLarger() throws {
        let (editor, _) = try makeEditor(text: "# Titel\nText")
        let storage = try #require(editor.textView.textStorage)
        let heading = try #require(storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
        let body = try #require(storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize > body.pointSize)
    }

    @Test func commentCommandUsesLanguagePrefixInCode() throws {
        let (editor, _) = try makeEditor(text: "code: py\nx = 1")
        editor.textView.setSelectedRange(NSRange(location: 12, length: 0))
        editor.perform(.toggleComment)
        #expect(editor.textView.string == "code: py\n# x = 1")
    }

    // MARK: Code

    @Test func codeNoteIsRawAndHighlighted() throws {
        let (editor, _) = try makeEditor(text: "code: swift\n- [ ] keine Liste\nlet x = 42")
        #expect(editor.textView.string == "code: swift\n- [ ] keine Liste\nlet x = 42")
        let storage = try #require(editor.textView.textStorage)
        let letLocation = (editor.textView.string as NSString).range(of: "let").location
        #expect(storage.attribute(.foregroundColor, at: letLocation, effectiveRange: nil) as? NSColor == .systemPink)
        let font = storage.attribute(.font, at: letLocation, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
    }

    @Test func codeNoteTypingHasNoListMagicButKeepsIndent() throws {
        let (editor, _) = try makeEditor(text: "code")
        editor.textView.setSelectedRange(NSRange(location: 4, length: 0))
        type("\n- a\n    b\nc", in: editor)
        #expect(editor.textView.string == "code\n- a\n    b\n    c")
    }

    // MARK: Paste mode

    @Test func pasteKeywordStartsAndEscapeStops() throws {
        let pasteboard = FakePasteboard()
        let scheduler = FakeTickScheduler()
        let collector = PasteCollector(pasteboard: pasteboard, scheduler: scheduler)
        let (editor, _) = try makeEditor(collector: collector)
        collector.onCollect = { noteID, text in editor.appendCollected(text, toNote: noteID) }

        type("paste", in: editor)
        #expect(collector.isCollecting(into: editor.model.current.id))
        #expect(editor.textView.annotations[0]?.text == Strings.Paste.active)

        pasteboard.copy("Erster Fund")
        scheduler.tick?()
        pasteboard.copy("Zweiter Fund")
        scheduler.tick?()
        #expect(editor.textView.string == "paste\nErster Fund\nZweiter Fund")

        // Esc ends the mode, the window stays.
        #expect(editor.textView.onEscape?() == true)
        #expect(!collector.isActive)
        #expect(editor.textView.annotations[0]?.text == Strings.Paste.inactive)
        #expect(editor.textView.onEscape?() == false) // next Esc closes the window again
    }

    // MARK: Lock & read-only

    @Test func lockHidesNoteUntilAuthenticated() async throws {
        let (editor, store) = try makeEditor(text: "Geheim")
        var allow = false
        editor.authenticate = { _ in allow }

        await editor.toggleLock()
        #expect(editor.isShowingLockedNote)
        #expect(editor.textView.isHidden)
        #expect(try store.stack().first?.isLocked == true)

        await editor.toggleLock() // denied
        #expect(editor.isShowingLockedNote)

        allow = true
        await editor.toggleLock() // unlock to view
        #expect(!editor.isShowingLockedNote)
        #expect(!editor.textView.isHidden)
        #expect(try store.stack().first?.isLocked == true) // still locked in general

        editor.relock()
        #expect(editor.isShowingLockedNote)

        await editor.toggleLock()
        await editor.toggleLock() // shown → remove lock
        #expect(try store.stack().first?.isLocked == false)
    }

    @Test func readOnlyDisablesEditing() throws {
        let (editor, _) = try makeEditor(text: "Fest")
        editor.perform(.toggleReadOnly)
        #expect(!editor.textView.isEditable)
        editor.perform(.format(.bold))
        #expect(editor.textView.string == "Fest")
        editor.perform(.toggleReadOnly)
        #expect(editor.textView.isEditable)
    }

    // MARK: Clipboard, links, text size

    @Test func copyWithoutSelectionCopiesWholeNote() throws {
        let (editor, _) = try makeEditor(text: "- [ ] Milch\nBrot")
        var notified = false
        editor.textView.onDidWritePasteboard = { notified = true }
        let previous = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let previous { NSPasteboard.general.setString(previous, forType: .string) }
        }
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        editor.textView.copy(nil)
        #expect(NSPasteboard.general.string(forType: .string) == "- [ ] Milch\nBrot")
        #expect(notified)
    }

    @Test func longLinksAreShortenedUnlessCursorInside() throws {
        let link = "https://github.com/organisation/repository/blob/main/Sources/Datei.swift"
        let (editor, _) = try makeEditor(text: "Link: \(link)\nweiter")
        let styler = try #require(editor.textView.layoutManager?.delegate as? ListStyler)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.updateLinkCollapsing()
        #expect(styler.hiddenLinkRanges.count == 1)

        editor.textView.setSelectedRange(NSRange(location: 20, length: 0))
        editor.textView.updateLinkCollapsing()
        #expect(styler.hiddenLinkRanges.isEmpty)
    }

    @Test func fontSizeChangesTextAndCheckboxes() throws {
        let (editor, _) = try makeEditor(text: "- [ ] a")
        let styler = try #require(editor.textView.layoutManager?.delegate as? ListStyler)
        let before = styler.checkboxWidth
        editor.setFontSize(20)
        #expect(editor.textView.font?.pointSize == 20)
        #expect(styler.checkboxWidth > before)
    }

    // MARK: Hidden markers

    @Test func markersHiddenExceptInCursorLine() throws {
        let (editor, _) = try makeEditor(text: "# Titel\nein **fettes** Wort\n_kursiv_", hideMarkers: true)
        let styler = try #require(editor.textView.layoutManager?.delegate as? ListStyler)
        let text = editor.textView.string as NSString

        editor.textView.setSelectedRange(NSRange(location: text.length, length: 0)) // in "_kursiv_"
        editor.textView.updateLinkCollapsing()
        let hidden = styler.hiddenMarkerRanges.map { text.substring(with: $0) }
        #expect(hidden == ["# ", "**", "**"])

        editor.textView.setSelectedRange(NSRange(location: 2, length: 0)) // in the heading
        editor.textView.updateLinkCollapsing()
        #expect(styler.hiddenMarkerRanges.map { text.substring(with: $0) } == ["**", "**", "_", "_"])
        #expect(editor.textView.string == "# Titel\nein **fettes** Wort\n_kursiv_") // text unchanged
    }

    @Test func markersStayWhenSettingIsOff() throws {
        let (editor, _) = try makeEditor(text: "**a**\nb", hideMarkers: false)
        let styler = try #require(editor.textView.layoutManager?.delegate as? ListStyler)
        editor.textView.setSelectedRange(NSRange(location: 7, length: 0))
        editor.textView.updateLinkCollapsing()
        #expect(styler.hiddenMarkerRanges.isEmpty)
    }

    @MainActor
    @Test func hideMarkersIsOnByDefault() {
        let storage = TemporaryDefaults()
        #expect(AppPreferences(defaults: storage.defaults).hideMarkdownMarkers)
    }

    @Test func snapshotHiddenMarkers() throws {
        guard ProcessInfo.processInfo.environment["ZETTEL_SNAPSHOT"] == "1" else { return }
        let (editor, _) = try makeEditor(
            text: "# Wochenplan\nHeute **wichtig**: _Bericht_ fertig, <u>Termin</u> um 14 Uhr, ~~Friseur~~.\n## Links\nBefehl: `git status`\nHier steht der Cursor: **sichtbar**",
            hideMarkers: true
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = editor
        window.appearance = NSAppearance(named: .aqua)
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
        editor.textView.updateLinkCollapsing()
        editor.view.layoutSubtreeIfNeeded()
        let view = editor.view
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("editor-hidden-markers.png")
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print("SNAPSHOT \(url.path)")
    }
}
