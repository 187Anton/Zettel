import AppKit
import Testing
@testable import Zettel

/// Notation as in ListEditingTests: `|` cursor, `«…»` selection.
private func marked(_ text: String) -> (String, NSRange) {
    var string = text
    if let caret = string.range(of: "|") {
        let location = string.utf16.distance(from: string.startIndex, to: caret.lowerBound)
        string.removeSubrange(caret)
        return (string, NSRange(location: location, length: 0))
    }
    let open = string.range(of: "«")!
    let start = string.utf16.distance(from: string.startIndex, to: open.lowerBound)
    string.removeSubrange(open)
    let close = string.range(of: "»")!
    let end = string.utf16.distance(from: string.startIndex, to: close.lowerBound)
    string.removeSubrange(close)
    return (string, NSRange(location: start, length: end - start))
}

private func show(_ text: String, _ selection: NSRange) -> String {
    let ns = NSMutableString(string: text)
    if selection.length == 0 {
        ns.insert("|", at: selection.location)
    } else {
        ns.insert("»", at: selection.upperBound)
        ns.insert("«", at: selection.location)
    }
    return ns as String
}

struct InlineMarkupTests {
    private func kinds(_ line: String) -> [InlineMarkup.Kind] {
        InlineMarkup.spans(in: line).map(\.kind)
    }

    @Test func recognizesFormats() {
        #expect(kinds("**fett**") == [.bold])
        #expect(kinds("_kursiv_ und *auch*") == [.italic, .italic])
        #expect(kinds("<u>unter</u>") == [.underline])
        #expect(kinds("~~weg~~") == [.strikethrough])
        #expect(kinds("`code`") == [.code])
        #expect(kinds("## Titel") == [.heading(2)])
    }

    @Test func ignoresNonFormatting() {
        #expect(kinds("snake_case_name").isEmpty)
        #expect(kinds("2 * 3 * 4").isEmpty)
        #expect(kinds("#hashtag").isEmpty)
        #expect(kinds("** leer **").isEmpty)
        #expect(kinds("`**nicht fett**`") == [.code])
    }

    @Test func spanRanges() throws {
        let span = try #require(InlineMarkup.spans(in: "ab **cd** ef").first)
        #expect(span.content == NSRange(location: 5, length: 2))
        #expect(span.markers == [NSRange(location: 3, length: 2), NSRange(location: 7, length: 2)])
    }
}

struct InlineFormattingTests {
    private func toggle(_ style: InlineFormatting.Style, _ input: String) -> String {
        let (text, selection) = marked(input)
        let edit = InlineFormatting.toggle(style, in: text, selection: selection)
        return show(edit.applied(to: text), edit.selection)
    }

    @Test func wrapsAndUnwrapsSelection() {
        #expect(toggle(.bold, "ein «Wort» hier") == "ein **«Wort»** hier")
        #expect(toggle(.bold, "ein **«Wort»** hier") == "ein «Wort» hier")
        #expect(toggle(.bold, "ein «**Wort**» hier") == "ein «Wort» hier")
        #expect(toggle(.italic, "«x»") == "_«x»_")
        #expect(toggle(.underline, "«x»") == "<u>«x»</u>")
        #expect(toggle(.strikethrough, "«x»") == "~~«x»~~")
    }

    @Test func insertsEmptyPairAtCursorAndRemovesIt() {
        #expect(toggle(.bold, "a |b") == "a **|**b")
        #expect(toggle(.bold, "a **|**b") == "a |b")
    }

    private func comment(_ input: String, prefix: String = "//") -> String? {
        let (text, selection) = marked(input)
        return InlineFormatting.toggleComment(in: text, selection: selection, prefix: prefix).map {
            show($0.applied(to: text), $0.selection)
        }
    }

    @Test func togglesComments() {
        #expect(comment("Zei|le") == "// Zei|le")
        #expect(comment("// Zei|le") == "Zei|le")
        #expect(comment("«a\nb»") == "«// a\n// b»")
        #expect(comment("☐ Mil|ch") == "☐ // Mil|ch")
        #expect(comment("x = 1|", prefix: "#") == "# x = 1|")
    }
}

struct SyntaxHighlighterTests {
    private func tokens(_ line: String, _ language: String) -> [String] {
        var state = SyntaxHighlighter.State()
        let ns = line as NSString
        return SyntaxHighlighter.tokens(in: line, language: SyntaxHighlighter.language(named: language), state: &state)
            .map { "\($0.1):\(ns.substring(with: $0.0))" }
    }

    @Test func python() {
        #expect(tokens("def f(x): return x + 42  # Antwort", "py") == [
            "keyword:def", "keyword:return", "number:42", "comment:# Antwort",
        ])
        #expect(tokens("s = 'a \\' b'", "python") == ["string:'a \\' b'"])
    }

    @Test func swiftAndBlockComments() {
        var state = SyntaxHighlighter.State()
        let swift = SyntaxHighlighter.language(named: "swift")
        _ = SyntaxHighlighter.tokens(in: "let a = 1 /* Start", language: swift, state: &state)
        #expect(state.inBlockComment)
        let next = SyntaxHighlighter.tokens(in: "noch Kommentar */ let b", language: swift, state: &state)
        #expect(next.map(\.1) == [.comment, .keyword])
        #expect(!state.inBlockComment)
    }

    @Test func languagesAndComments() {
        #expect(SyntaxHighlighter.language(named: "PY").commentPrefix == "#")
        #expect(SyntaxHighlighter.language(named: "sql").commentPrefix == "--")
        #expect(SyntaxHighlighter.language(named: "unbekannt").name == "text")
        #expect(SyntaxHighlighter.language(named: nil).commentPrefix == "//")
    }
}

struct CodeNoteFormatTests {
    @Test func codeNotesAreNotConverted() {
        let text = "code: yaml\n- name: test\n* x"
        #expect(NoteFormat.display(fromMarkdown: text) == text)
        #expect(NoteFormat.markdown(fromDisplay: text) == text)
    }

    @Test func choosingCodeRestoresMarkdown() throws {
        let text = "/\n☐ Aufgabe\n• Punkt"
        let edit = try #require(KeywordEditing.apply(.code, in: text, slashLocation: 0))
        #expect(edit.applied(to: text) == "code\n- [ ] Aufgabe\n- Punkt")
    }
}

@MainActor
final class FakePasteboard: PasteboardReading {
    var changeCount = 0
    var contents: String?

    func copy(_ text: String?) {
        changeCount += 1
        contents = text
    }

    func collectableString() -> String? { contents }
}

@MainActor
struct PasteCollectorTests {
    @Test func collectsOnlyNewTextWhileActive() {
        let pasteboard = FakePasteboard()
        let scheduler = FakeTickScheduler()
        let collector = PasteCollector(pasteboard: pasteboard, scheduler: scheduler)
        var collected: [String] = []
        collector.onCollect = { _, text in collected.append(text) }

        pasteboard.copy("vorher")
        collector.start(noteID: "n")
        #expect(scheduler.isRunning)
        scheduler.tick?()
        #expect(collected.isEmpty) // what was there before is not taken

        pasteboard.copy("eins")
        scheduler.tick?()
        scheduler.tick?() // no change
        pasteboard.copy("  ")
        scheduler.tick?() // blank is ignored
        pasteboard.copy(nil)
        scheduler.tick?() // concealed (password manager) is ignored
        pasteboard.copy("zwei")
        scheduler.tick?()
        #expect(collected == ["eins", "zwei"])

        collector.stop()
        #expect(!scheduler.isRunning)
        pasteboard.copy("drei")
        scheduler.tick?()
        #expect(collected == ["eins", "zwei"])
    }

    @Test func ignoresOwnCopies() {
        let pasteboard = FakePasteboard()
        let scheduler = FakeTickScheduler()
        let collector = PasteCollector(pasteboard: pasteboard, scheduler: scheduler)
        var collected: [String] = []
        collector.onCollect = { _, text in collected.append(text) }
        collector.start(noteID: "n")

        pasteboard.copy("von Zettel selbst")
        collector.ignoreCurrentContents()
        scheduler.tick?()
        #expect(collected.isEmpty)
    }

    @Test func appendsOnNewLine() {
        #expect(PasteCollector.append("b\n", to: "a") == "a\nb")
        #expect(PasteCollector.append("b", to: "a\n") == "a\nb")
        #expect(PasteCollector.append("b", to: "") == "b")
    }
}

struct LinkDetectionTests {
    @Test func findsWebLinksOnly() {
        let links = LinkDetection.links(in: "Siehe https://example.com/a und mail@test.de oder www.apple.com")
        #expect(links.map(\.url.absoluteString) == ["https://example.com/a", "https://www.apple.com"])
    }

    @Test func shortensLongLinksOnly() throws {
        let short = try #require(LinkDetection.links(in: "https://kurz.de").first)
        #expect(LinkDetection.hiddenRange(of: short) == nil)
        let text = "x https://github.com/organisation/repository/blob/main/Sources/Datei.swift"
        let long = try #require(LinkDetection.links(in: text).first)
        let hidden = try #require(LinkDetection.hiddenRange(of: long))
        #expect(hidden.location == 2 + LinkDetection.keepStart)
        #expect(NSMaxRange(hidden) == NSMaxRange(long.range) - LinkDetection.keepEnd)
    }

    @MainActor
    @Test func linkAtCursor() {
        let text = "a https://eins.de b https://zwei.de"
        #expect(NoteTextView.link(in: text, near: 25)?.absoluteString == "https://zwei.de")
        #expect(NoteTextView.link(in: text, near: 0)?.absoluteString == "https://eins.de")
        #expect(NoteTextView.link(in: "kein Link", near: 0) == nil)
    }
}

struct ExportTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func fileNames() {
        #expect(NoteExporter.suggestedName(for: Note(text: "Einkauf: Mo/Di?\nText", date: date)) == "Einkauf- Mo-Di-")
        #expect(NoteExporter.suggestedName(for: Note(text: "math: Budget\n1", date: date)) == "Budget")
        #expect(NoteExporter.suggestedName(for: Note(text: "   ", date: date)) == "Notiz")
    }

    @Test func formats() {
        let note = Note(text: "- [ ] Milch\n- Brot", date: date)
        #expect(NoteExporter.content(of: note, as: .markdown) == "- [ ] Milch\n- Brot")
        #expect(NoteExporter.content(of: note, as: .text) == "☐ Milch\n• Brot")
    }

    @MainActor
    @Test func pdfIsCreated() {
        let data = NoteExporter.pdfData(of: Note(text: String(repeating: "Zeile mit Text\n", count: 120), date: date))
        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(PDFPageCounter.count(data) >= 2) // long notes span pages
    }

    @Test func zipContainsNotesButNotLockedOrTrashed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var locked = Note(text: "Geheim", date: date)
        locked.isLocked = true
        var trashed = Note(text: "Weg", date: date)
        trashed.trashedAt = date
        let notes = [Note(text: "Eins", date: date), Note(text: "Eins", date: date), Note(text: "Platz", date: date, slot: 2), locked, trashed]

        let zip = directory.appendingPathComponent("export.zip")
        let count = try NoteExporter.exportAll(notes, to: zip)

        #expect(count == 3)
        let data = try Data(contentsOf: zip)
        #expect(data.starts(with: Data([0x50, 0x4B]))) // "PK"
        let listing = String(decoding: data, as: UTF8.self)
        #expect(listing.contains("Stapel/Eins.md"))
        #expect(listing.contains("Stapel/Eins 2.md"))
        #expect(listing.contains("Platz 2 – Platz.md"))
        #expect(!listing.contains("Geheim"))
    }
}

enum PDFPageCounter {
    static func count(_ data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }
}

struct LockSearchTests {
    @Test func lockedNotesAreNeverSearchedOrShown() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var locked = Note(text: "Geheimes Passwort-Hinweis", date: date)
        locked.isLocked = true
        let notes = [locked, Note(text: "Offen", date: date)]

        #expect(NoteSearch.search(notes, query: "geheim", filter: .all).isEmpty)
        let all = NoteSearch.search(notes, query: "", filter: .all)
        #expect(all.map(\.title).contains(NoteSearch.lockedTitle))
        #expect(all.first { $0.note.isLocked }?.snippet == "")
    }
}

struct Phase9ShortcutTests {
    private func command(_ keyCode: Int, _ characters: String, _ modifiers: KeyModifiers) -> PanelCommand? {
        PanelShortcuts.command(keyCode: UInt16(keyCode), characters: characters, charactersIgnoringModifiers: characters, modifiers: modifiers)
    }

    @Test func formattingShortcuts() {
        #expect(command(11, "b", .command) == .format(.bold))
        #expect(command(34, "i", .command) == .format(.italic))
        #expect(command(32, "u", .command) == .format(.underline))
        #expect(command(7, "X", [.command, .shift]) == .format(.strikethrough))
        #expect(command(44, "/", .command) == .toggleComment)           // US
        #expect(command(26, "/", [.command, .shift]) == .toggleComment) // German ⇧7
    }

    @Test func otherShortcuts() {
        #expect(command(36, "\r", .command) == .openLink)
        #expect(command(30, "+", .command) == .textBigger)       // German "+" key
        #expect(command(24, "=", .command) == .textBigger)       // US "=" key
        #expect(command(27, "-", .command) == .textSmaller)
        #expect(command(29, "0", .command) == .textSizeReset)
        #expect(command(37, "L", [.command, .shift]) == .toggleLock)
        #expect(command(15, "R", [.command, .shift]) == .toggleReadOnly)
        #expect(command(14, "E", [.command, .shift]) == .export)
    }
}

@MainActor
struct Phase9PreferencesTests {
    @Test func appearanceDefaultsAndClamping() {
        let storage = TemporaryDefaults()
        let preferences = AppPreferences(defaults: storage.defaults)
        #expect(preferences.theme == .system)
        #expect(preferences.fontSize == 14)
        #expect(!preferences.transparentWindow)
        preferences.fontSize = 100
        #expect(preferences.fontSize == 28)
        preferences.fontSize = 2
        #expect(preferences.fontSize == 10)
    }

    @Test func storeKeepsLockAndReadOnly() throws {
        let store = try NoteStore.inMemory()
        var note = Note(text: "x", date: Date())
        note.isLocked = true
        note.isReadOnly = true
        try store.insert(note)
        let loaded = try #require(try store.note(id: note.id))
        #expect(loaded.isLocked && loaded.isReadOnly)
    }
}
