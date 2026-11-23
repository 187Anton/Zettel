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

    /// Keyword of the note, from its first line.
    var keyword: Keyword? {
        KeywordHeader(text: string)?.keyword
    }

    // MARK: Keyword picker

    private(set) var keywordPicker: KeywordPickerView?
    private var keywordSlashLocation: Int?

    var isShowingKeywordPicker: Bool { keywordPicker != nil }

    /// Opens the picker for a `/` just typed at `slashLocation`.
    func showKeywordPicker(slashLocation: Int) {
        closeKeywordPicker()
        guard let layoutManager, let textContainer else { return }
        let picker = KeywordPickerView(font: font ?? .systemFont(ofSize: 14))
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

    func chooseKeyword(_ keyword: Keyword) {
        let slash = keywordSlashLocation
        closeKeywordPicker()
        guard let slash, let edit = KeywordEditing.apply(keyword, in: string, slashLocation: slash) else { return }
        apply(edit)
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
            closeKeywordPicker()
        }

        // Esc closes the window, unless an input method is composing text.
        if key == kVK_Escape, modifiers.isEmpty, !hasMarkedText() {
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
        window?.cancelOperation(sender)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        let isTyping = replacementRange.location == NSNotFound && !hasMarkedText()

        // list note: the first character in an empty line starts a checkbox.
        if isTyping, let inserted, keyword == .list,
           let edit = ListEditing.listModeInsertion(in: string, selection: selectedRange(), inserted: inserted) {
            apply(edit)
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
        guard isTyping, let inserted, selectedRange().length == 0 else { return }
        let cursor = selectedRange().location

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
        if let edit = ListEditing.newline(in: string, selection: selectedRange(), listMode: keyword == .list) {
            apply(edit)
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
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
        drawAnnotations(in: rect)
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

    /// Copies and cuts as Markdown (`- [ ] …`), so lists survive in other apps.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let text = string as NSString
        let selected = selectedRanges
            .map { text.substring(with: $0.rangeValue) }
            .joined(separator: "\n")
        guard !selected.isEmpty else { return false }
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(NoteFormat.markdown(fromDisplay: selected), forType: .string)
    }

    /// Pastes plain text; Markdown lists are shown as lists.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
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
