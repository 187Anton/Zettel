import AppKit
import Carbon.HIToolbox

/// Plain-text editor for a note with list editing (checklists, bullets, numbers).
///
/// Every list operation is a single `TextEdit`, applied as one undoable change.
final class NoteTextView: NSTextView {
    /// Reads the current "checked items" setting.
    var checkedItemBehavior: () -> CheckedItemBehavior = { .keep }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags)
        let key = Int(event.keyCode)

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
        super.insertText(insertString, replacementRange: replacementRange)

        let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        guard inserted == " ", !hasMarkedText(), selectedRange().length == 0,
              let edit = ListEditing.markdownShortcut(in: string, cursor: selectedRange().location)
        else { return }
        // Separate undo step: ⌘Z right after the conversion restores the typed "- ".
        // The space and the conversion happen in the same key event, which the undo
        // manager would group together, so close that group and start a new one.
        if let undoManager, undoManager.groupingLevel > 0 {
            undoManager.endUndoGrouping()
            undoManager.beginUndoGrouping()
        }
        apply(edit)
    }

    override func insertNewline(_ sender: Any?) {
        if let edit = ListEditing.newline(in: string, selection: selectedRange()) {
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

    override func mouseDown(with event: NSEvent) {
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
        insertText(NoteFormat.display(fromMarkdown: text), replacementRange: selectedRange())
    }

    // MARK: Applying edits

    /// Applies an edit as one undoable change and selects the result.
    func apply(_ edit: TextEdit) {
        guard let textStorage, shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        breakUndoCoalescing()
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
