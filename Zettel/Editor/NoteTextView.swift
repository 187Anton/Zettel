import AppKit
import Carbon.HIToolbox

/// Plain-text editor for a note with list editing (checklists, bullets, numbers).
///
/// Every list operation is a single `TextEdit`, applied as one undoable change.
final class NoteTextView: NSTextView {
    /// Reads the current "checked items" setting.
    var checkedItemBehavior: () -> CheckedItemBehavior = { .keep }

    /// Right-aligned texts per line index (results of a `math` note).
    var annotations: [Int: LineAnnotation] = [:] {
        didSet {
            if annotations != oldValue { needsDisplay = true }
        }
    }

    enum ReturnAction {
        /// Insert the newline as usual.
        case normal
        /// The line was a command that has been executed: empty the line instead.
        case clearLine
    }

    /// Esc in the text; return `true` if handled (the window then stays open).
    var onEscape: (() -> Bool)?
    /// A keyword was chosen in the picker.
    var onKeywordChosen: ((Keyword) -> Void)?

    /// Called for Return at the end of a line, with that line and all lines above.
    var onReturn: ((_ line: String, _ linesAbove: [String]) -> ReturnAction)?

    /// Keyword of the note, from its first line.
    var keyword: Keyword? {
        KeywordHeader(text: string)?.keyword
    }

    // MARK: Keyword picker

    private(set) var keywordPicker: KeywordPickerView?
    private var keywordSlashLocation: Int?

    var isShowingKeywordPicker: Bool { keywordPicker != nil }

    // MARK: Long links

    /// Setting: hide Markdown markers outside the cursor line.
    var hidesMarkdownMarkers: () -> Bool = { false }

    /// Markers to hide: all lines except those touched by the selection; none in code notes.
    func hiddenMarkerRanges() -> [NSRange] {
        guard hidesMarkdownMarkers(), keyword != .code else { return [] }
        let text = string as NSString
        let selection = selectedRange()
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs]) { line, lineRange, enclosingRange, _ in
            let touched = NSIntersectionRange(enclosingRange, selection).length > 0
                || NSLocationInRange(selection.location, enclosingRange)
                || (NSMaxRange(lineRange) == selection.location)
            guard !touched, let line else { return }
            let item = ListLine(display: line)
            let offset = lineRange.location + item.displayMarkerLength
            for span in InlineMarkup.spans(in: item.content) {
                if case .heading = span.kind, item.isListItem { continue }
                for marker in span.markers {
                    ranges.append(NSRange(location: offset + marker.location, length: marker.length))
                }
            }
        }
        return ranges
    }

    /// Shortens long links to "start…end" unless the cursor is inside them, and hides
    /// Markdown markers (setting). Only the display changes; the text stays complete.
    func updateLinkCollapsing() {
        guard let styler = layoutManager?.delegate as? ListStyler else { return }
        let selection = selectedRange()
        let hidden = LinkDetection.links(in: string).compactMap { link -> NSRange? in
            let touchesSelection = NSIntersectionRange(link.range, selection).length > 0
                || NSLocationInRange(selection.location, link.range) || NSMaxRange(link.range) == selection.location
            return touchesSelection ? nil : LinkDetection.hiddenRange(of: link)
        }
        let markers = hiddenMarkerRanges()
        guard hidden != styler.hiddenLinkRanges || markers != styler.hiddenMarkerRanges else { return }
        let changed = styler.hiddenLinkRanges + hidden + styler.hiddenMarkerRanges + markers
        styler.hiddenLinkRanges = hidden
        styler.hiddenMarkerRanges = markers
        guard let layoutManager else { return }
        for range in changed where NSMaxRange(range) <= (string as NSString).length {
            layoutManager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }
        needsDisplay = true
    }

    /// Opens the picker for a `/` just typed at `slashLocation`, showing the
    /// keywords that match what was typed after the slash.
    func showKeywordPicker(slashLocation: Int, keywords: [Keyword] = Keyword.allCases) {
        closeKeywordPicker()
        guard let layoutManager, let textContainer, !keywords.isEmpty else { return }
        let picker = KeywordPickerView(keywords: keywords, font: font ?? .systemFont(ofSize: 14))
        picker.onChoose = { [weak self] keyword in self?.chooseKeyword(keyword) }

        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: slashLocation, length: 1), actualCharacterRange: nil)
        let caret = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        var origin = NSPoint(x: caret.minX, y: caret.maxY + 4)
        origin.x = max(4, min(origin.x, bounds.width - picker.frame.width - 4))
        picker.setFrameOrigin(origin)
        addSubview(picker)
        keywordPicker = picker
        keywordSlashLocation = slashLocation
        picker.scrollToVisible(picker.bounds)
    }

    func closeKeywordPicker() {
        keywordPicker?.removeFromSuperview()
        keywordPicker = nil
        keywordSlashLocation = nil
    }

    /// Letters typed after the `/` while the picker is open (`/pa` → "pa").
    private var keywordQuery: String {
        guard let slash = keywordSlashLocation else { return "" }
        let text = string as NSString
        let end = selectedRange().location
        guard end > slash, end <= text.length else { return "" }
        return text.substring(with: NSRange(location: slash + 1, length: end - slash - 1))
    }

    /// Filters the picker after typing; closes it when nothing matches.
    private func refilterKeywordPicker() {
        guard let slash = keywordSlashLocation else { return }
        let query = keywordQuery
        guard selectedRange().location > slash, query.allSatisfy(\.isLetter) else {
            closeKeywordPicker()
            return
        }
        let matches = Keyword.matching(query)
        if matches.isEmpty {
            closeKeywordPicker()
        } else if matches != keywordPicker?.keywords {
            showKeywordPicker(slashLocation: slash, keywords: matches)
        }
    }

    func chooseKeyword(_ keyword: Keyword) {
        let slash = keywordSlashLocation
        let typedLength = 1 + (keywordQuery as NSString).length
        closeKeywordPicker()
        guard let slash, let edit = KeywordEditing.apply(keyword, in: string, slashLocation: slash, typedLength: typedLength) else { return }
        apply(edit)
        onKeywordChosen?(keyword)
    }

    /// Closes the picker when the text changes in a way that removes its `/`.
    override func didChangeText() {
        super.didChangeText()
        if let slash = keywordSlashLocation {
            let text = string as NSString
            if slash >= text.length || text.character(at: slash) != 0x2F {
                closeKeywordPicker()
            }
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags)
        let key = Int(event.keyCode)

        if let picker = keywordPicker {
            if key == kVK_Escape, modifiers.isEmpty {
                closeKeywordPicker() // keep the "/" and the window open
                return
            }
            if modifiers.isEmpty, picker.handleKey(keyCode: key, characters: event.charactersIgnoringModifiers) {
                return
            }
            // Letters filter the list ("/pa" → paste), Backspace widens it again.
            let isLetter = event.characters?.count == 1 && event.characters?.first?.isLetter == true
            if (isLetter && modifiers.isSubset(of: .shift)) || (key == kVK_Delete && modifiers.isEmpty) {
                super.keyDown(with: event)
                refilterKeywordPicker()
                return
            }
            closeKeywordPicker()
        }

        // Esc closes the window, unless an input method is composing text
        // or the note wants it (ends the paste mode).
        if key == kVK_Escape, modifiers.isEmpty, !hasMarkedText() {
            if onEscape?() == true { return }
            window?.cancelOperation(nil)
            return
        }
        // ⌥↑ / ⌥↓ move lines.
        if modifiers == .option, key == kVK_UpArrow || key == kVK_DownArrow {
            if let edit = ListEditing.moveLines(in: string, selection: selectedRange(), up: key == kVK_UpArrow) {
                apply(edit)
            }
            return
        }
        super.keyDown(with: event)
    }

    /// NSTextView maps Esc to completion by default; we use Esc for closing.
    override func complete(_ sender: Any?) {
        if onEscape?() == true { return }
        window?.cancelOperation(sender)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        let isTyping = replacementRange.location == NSNotFound && !hasMarkedText()

        let keyword = self.keyword
        // list note: the first character in an empty line starts a checkbox.
        if isTyping, let inserted, keyword == .list,
           let edit = ListEditing.listModeInsertion(in: string, selection: selectedRange(), inserted: inserted) {
            apply(edit)
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
        guard isTyping, let inserted, selectedRange().length == 0 else { return }
        let cursor = selectedRange().location

        // Code is typed as is: no list shortcuts; the keyword picker only in the first line.
        if keyword == .code {
            if inserted == "/", LineDocument(string).location(ofOffset: cursor - 1).line == 0,
               Self.isAtContentStart(string, slashLocation: cursor - 1) {
                showKeywordPicker(slashLocation: cursor - 1)
            }
            return
        }

        switch inserted {
        case " ":
            // Separate undo step (see `apply`): ⌘Z right after the conversion restores "- ".
            if let edit = ListEditing.markdownShortcut(in: string, cursor: cursor) {
                apply(edit)
            }
        case "x", "X":
            if keyword == .list,
               let edit = ListEditing.slashToggle(in: string, cursor: cursor, behavior: checkedItemBehavior()) {
                apply(edit)
            }
        case "/":
            if let edit = ListEditing.commentShortcut(in: string, cursor: cursor) {
                apply(edit) // "☐ //" → "//": a comment, not a list item
            } else if Self.isAtContentStart(string, slashLocation: cursor - 1) {
                showKeywordPicker(slashLocation: cursor - 1)
            }
        default:
            break
        }
    }

    /// `true` if the `/` stands at the start of its line (after tabs or a list marker).
    static func isAtContentStart(_ text: String, slashLocation: Int) -> Bool {
        let document = LineDocument(text)
        let (index, column) = document.location(ofOffset: slashLocation)
        let item = ListLine(display: document.originalLines[index])
        let prefix = (document.originalLines[index] as NSString).substring(to: column)
        return prefix.allSatisfy { $0 == "\t" } || column == item.displayMarkerLength && item.isListItem
    }

    override func insertNewline(_ sender: Any?) {
        if keyword == .code {
            // Keep the indentation of the current line.
            let document = LineDocument(string)
            let (index, _) = document.location(ofOffset: selectedRange().location)
            let indentation = document.originalLines[index].prefix { $0 == " " || $0 == "\t" }
            insertText("\n" + indentation, replacementRange: selectedRange())
            return
        }
        if let onReturn, selectedRange().length == 0 {
            let document = LineDocument(string)
            let (index, column) = document.location(ofOffset: selectedRange().location)
            let line = document.originalLines[index]
            if column == line.utf16.count,
               onReturn(line, Array(document.originalLines[..<index])) == .clearLine {
                if let edit = ListEditing.clearLine(in: string, cursor: selectedRange().location) {
                    apply(edit)
                }
                return
            }
        }
        if let edit = ListEditing.newline(in: string, selection: selectedRange(), listMode: keyword == .list) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if keyword == .code {
            super.insertTab(sender)
            return
        }
        if let edit = ListEditing.indent(in: string, selection: selectedRange(), outdent: false) {
            apply(edit)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let edit = ListEditing.indent(in: string, selection: selectedRange(), outdent: true) {
            apply(edit)
        }
    }

    override func deleteBackward(_ sender: Any?) {
        if keyword == .code {
            super.deleteBackward(sender)
            return
        }
        if let edit = ListEditing.deleteBackward(in: string, selection: selectedRange()) {
            apply(edit)
        } else {
            super.deleteBackward(sender)
        }
    }

    // MARK: Commands

    /// ⌘⇧K
    func toggleCheckbox() {
        if let edit = ListEditing.toggleCheck(in: string, selection: selectedRange(), behavior: checkedItemBehavior()) {
            apply(edit)
        }
    }

    /// ⌘B, ⌘I, ⌘U, ⌘⇧X
    func toggleFormat(_ style: InlineFormatting.Style) {
        guard isEditable, keyword != .code else { return }
        apply(InlineFormatting.toggle(style, in: string, selection: selectedRange()))
    }

    /// ⌘/ – `//` (or the language's comment in code notes) for the selected lines.
    func toggleComment(prefix: String) {
        guard isEditable, let edit = InlineFormatting.toggleComment(in: string, selection: selectedRange(), prefix: prefix) else { return }
        apply(edit)
    }

    /// ⌘↩ – opens the link at the cursor, or the first link of the line.
    @discardableResult
    func openLinkAtCursor() -> Bool {
        guard let url = Self.link(in: string, near: selectedRange().location) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    static func link(in text: String, near location: Int) -> URL? {
        let ns = text as NSString
        let line = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
        let links = LinkDetection.links(in: text, range: line)
        let hit = links.first { NSLocationInRange(location, $0.range) || NSMaxRange($0.range) == location } ?? links.first
        return hit?.url
    }

    /// ⌘⇧M
    func cycleListType() {
        if let edit = ListEditing.cycleListType(in: string, selection: selectedRange()) {
            apply(edit)
        }
    }

    // MARK: Drawing

    /// Draws the checkbox symbols into the space the layout reserved for ☐/☑.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer else { return }
        let text = string as NSString
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let pointSize = (font?.pointSize ?? 14) * 0.95

        text.enumerateSubstrings(in: characters, options: [.byParagraphs, .substringNotRequired]) { _, lineRange, _, _ in
            var index = lineRange.location
            while index < NSMaxRange(lineRange), text.character(at: index) == 0x09 { index += 1 }
            guard ListLine.isCheckboxMarker(in: text, at: index) else { return }

            let checked = text.character(at: index) == 0x2611
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            var box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            box = box.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            let lineFragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                .offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            Self.drawCheckbox(checked: checked, pointSize: pointSize, in: NSRect(
                x: box.minX, y: lineFragment.minY, width: box.width, height: lineFragment.height
            ))
        }
        drawLinkEllipses()
        drawAnnotations(in: rect)
    }

    private func drawLinkEllipses() {
        guard let styler = layoutManager?.delegate as? ListStyler, !styler.hiddenLinkRanges.isEmpty,
              let layoutManager, let textContainer else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor]
        for range in styler.hiddenLinkRanges where range.location < (string as NSString).length {
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let baseline = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                + textContainerOrigin.y + layoutManager.location(forGlyphAt: glyph).y
            let width = ("…" as NSString).size(withAttributes: attributes).width
            ("…" as NSString).draw(at: NSPoint(x: box.midX - width / 2, y: baseline - (font?.ascender ?? 12)), withAttributes: attributes)
        }
    }

    /// Draws results right-aligned on the last line fragment of their line.
    private func drawAnnotations(in rect: NSRect) {
        guard !annotations.isEmpty, let layoutManager, let textContainer else { return }
        let text = string as NSString
        let right = textContainerOrigin.x + textContainer.size.width - textContainer.lineFragmentPadding
        var lineIndex = 0
        var location = 0
        while location <= text.length {
            let end = text.range(of: "\n", range: NSRange(location: location, length: text.length - location)).location
            let lineEnd = end == NSNotFound ? text.length : end
            if let annotation = annotations[lineIndex], lineEnd > location {
                let glyph = layoutManager.glyphIndexForCharacter(at: lineEnd - 1)
                let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                if fragment.intersects(rect) {
                    let baseline = fragment.minY + layoutManager.location(forGlyphAt: glyph).y
                    let attributes = Self.annotationAttributes(annotation.kind, pointSize: font?.pointSize ?? 14)
                    let string = annotation.text as NSString
                    let size = string.size(withAttributes: attributes)
                    let font = attributes[.font] as? NSFont
                    string.draw(at: NSPoint(x: right - size.width, y: baseline - (font?.ascender ?? size.height)), withAttributes: attributes)
                }
            }
            guard end != NSNotFound else { break }
            location = end + 1
            lineIndex += 1
        }
    }

    static func annotationAttributes(_ kind: LineAnnotation.Kind, pointSize: CGFloat) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .result:
            [.font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular), .foregroundColor: NSColor.controlAccentColor]
        case .total:
            [.font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold), .foregroundColor: NSColor.controlAccentColor]
        case .error:
            [.font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
        case .info:
            [.font: NSFont.monospacedDigitSystemFont(ofSize: pointSize - 1, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        }
    }

    private static func drawCheckbox(checked: Bool, pointSize: CGFloat, in rect: NSRect) {
        let color: NSColor = checked ? .controlAccentColor : .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: checked ? [.white, color] : [color]))
        guard let image = NSImage(
            systemSymbolName: checked ? "checkmark.square.fill" : "square",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else { return }

        let size = image.size
        let origin = NSPoint(x: rect.minX + (rect.width - size.width) / 2 - 1, y: rect.midY - size.height / 2)
        image.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    // MARK: Mouse

    /// Cursor shown over a checkbox, so it is clear that it can be clicked.
    static let checkboxCursor = NSCursor.arrow

    private var checkboxTrackingArea: NSTrackingArea?
    private var isShowingCheckboxCursor = false

    /// The cursor for a point in view coordinates, or `nil` for the text view's default.
    func cursor(at point: NSPoint) -> NSCursor? {
        checkboxCharacterIndex(at: point) == nil ? nil : Self.checkboxCursor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard checkboxTrackingArea == nil else { return }
        // `.activeAlways`: the panel does not activate the app.
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        checkboxTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCheckboxCursor(for: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        if cursor(at: convert(event.locationInWindow, from: nil)) == nil {
            super.cursorUpdate(with: event)
        }
        updateCheckboxCursor(for: event)
    }

    private func updateCheckboxCursor(for event: NSEvent) {
        if let cursor = cursor(at: convert(event.locationInWindow, from: nil)) {
            cursor.set()
            isShowingCheckboxCursor = true
        } else if isShowingCheckboxCursor {
            NSCursor.iBeam.set()
            isShowingCheckboxCursor = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        closeKeywordPicker()
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, let index = checkboxCharacterIndex(at: point) {
            toggleCheckbox(atCharacterIndex: index)
            return
        }
        super.mouseDown(with: event)
    }

    func toggleCheckbox(atCharacterIndex index: Int) {
        if let edit = ListEditing.toggleCheck(
            in: string,
            lineContaining: index,
            selection: selectedRange(),
            behavior: checkedItemBehavior()
        ) {
            apply(edit)
        }
    }

    /// Character index of a ☐/☑ symbol under the point, if any.
    func checkboxCharacterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: location, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -3, dy: -2).contains(location) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return ListEditing.isCheckboxSymbol(in: string, at: index) ? index : nil
    }

    // MARK: Clipboard

    /// Called after Zettel itself wrote to the clipboard (the paste mode ignores that).
    var onDidWritePasteboard: (() -> Void)?

    /// Copies and cuts as Markdown (`- [ ] …`), so lists survive in other apps.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let text = string as NSString
        let selected = selectedRanges
            .map { text.substring(with: $0.rangeValue) }
            .joined(separator: "\n")
        guard !selected.isEmpty else { return false }
        pboard.declareTypes([.string], owner: nil)
        let written = pboard.setString(keyword == .code ? selected : NoteFormat.markdown(fromDisplay: selected), forType: .string)
        if pboard == .general { onDidWritePasteboard?() }
        return written
    }

    /// ⌘C without a selection copies the whole note.
    override func copy(_ sender: Any?) {
        guard selectedRange().length == 0 else {
            super.copy(sender)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(NoteFormat.markdown(fromDisplay: string), forType: .string)
        onDidWritePasteboard?()
    }

    /// Pastes plain text; Markdown lists are shown as lists.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if keyword == .code {
            insertText(text, replacementRange: selectedRange())
            return
        }
        var display = NoteFormat.display(fromMarkdown: text)
        if keyword == .list {
            // In a list note, pasted lines become checkboxes too.
            display = display.components(separatedBy: "\n").map { line in
                let item = ListLine(display: line)
                guard !item.isListItem, !item.isContentBlank, !line.hasPrefix("//") else { return line }
                return ListLine(marker: .checkbox(checked: false), content: line).display
            }.joined(separator: "\n")
        }
        insertText(display, replacementRange: selectedRange())
    }

    // MARK: Applying edits

    /// Applies an edit as one undoable change and selects the result.
    func apply(_ edit: TextEdit) {
        // Must happen *before* shouldChangeText: otherwise the edit is merged into
        // the running typing action, and one ⌘Z would also remove what was typed.
        breakUndoCoalescing()
        guard let textStorage, shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        breakUndoCoalescing()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }
}

/// Scroll view that turns two-finger horizontal swipes into navigation.
final class NoteScrollView: NSScrollView {
    var onSwipe: ((HorizontalSwipeTracker.Direction) -> Void)?
    private var tracker = HorizontalSwipeTracker()

    override func scrollWheel(with event: NSEvent) {
        let phase: HorizontalSwipeTracker.Phase
        if !event.momentumPhase.isEmpty {
            phase = .other
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else if event.phase.contains(.ended) {
            phase = .ended
        } else if event.phase.contains(.cancelled) {
            phase = .cancelled
        } else {
            phase = .other
        }

        if let direction = tracker.handle(
            phase: phase,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isDirectionInverted: event.isDirectionInvertedFromDevice
        ) {
            onSwipe?(direction)
        }

        if !tracker.isTrackingHorizontalSwipe {
            super.scrollWheel(with: event)
        }
    }
}
