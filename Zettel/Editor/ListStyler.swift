import AppKit

/// Applies display attributes for lists after each edit: muted markers, crossed-out
/// checked items and a hanging indent so wrapped lines align with the item text.
///
/// Only attributes change here (never characters), so undo and saving are unaffected.
@MainActor
final class ListStyler: NSObject {
    static let tabWidth: CGFloat = 24

    var font: NSFont {
        didSet { markerWidths = [:] }
    }

    private var markerWidths: [String: CGFloat] = [:]

    init(font: NSFont) {
        self.font = font
    }

    /// Space reserved for a checkbox symbol; it is drawn by `NoteTextView`.
    var checkboxWidth: CGFloat {
        (font.pointSize * 1.3).rounded()
    }

    var baseParagraphStyle: NSParagraphStyle {
        paragraphStyle(headIndent: 0)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: baseParagraphStyle]
    }

    func styleAll(_ storage: NSTextStorage) {
        storage.beginEditing()
        style(storage, in: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    /// Restyles the paragraphs touched by `range`. Called from inside the text
    /// storage's edit processing, so it must not begin/end editing itself.
    func style(_ storage: NSTextStorage, in range: NSRange) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let paragraphs = text.paragraphRange(for: range)

        text.enumerateSubstrings(in: paragraphs, options: [.byParagraphs]) { substring, lineRange, enclosingRange, _ in
            let item = ListLine(display: substring ?? "")
            storage.setAttributes(self.attributes(for: item), range: enclosingRange)
            guard let marker = item.marker else { return }

            let markerRange = NSRange(location: lineRange.location + item.indent, length: item.displayMarkerLength - item.indent)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: markerRange)
            _ = marker
            if item.isChecked {
                let contentRange = NSRange(location: lineRange.location + item.displayMarkerLength, length: lineRange.length - item.displayMarkerLength)
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.tertiaryLabelColor,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ], range: contentRange)
            }
        }
    }

    private func attributes(for item: ListLine) -> [NSAttributedString.Key: Any] {
        guard let marker = item.marker else { return baseAttributes }
        let width: CGFloat = if case .checkbox = marker {
            checkboxWidth + markerWidth(" ")
        } else {
            markerWidth(ListLine.displayText(for: marker))
        }
        let headIndent = CGFloat(item.indent) * Self.tabWidth + width
        return [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle(headIndent: headIndent)]
    }

    private func markerWidth(_ text: String) -> CGFloat {
        if let width = markerWidths[text] { return width }
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        markerWidths[text] = width
        return width
    }

    private func paragraphStyle(headIndent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = Self.tabWidth
        style.headIndent = headIndent
        style.lineSpacing = 2
        return style
    }
}

extension ListStyler: @preconcurrency NSTextStorageDelegate {
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        style(textStorage, in: editedRange)
    }
}

/// Reserves a fixed-width blank glyph for each checkbox symbol, so the layout does
/// not depend on which font happens to contain ☐/☑.
extension ListStyler: @preconcurrency NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let text = layoutManager.textStorage?.string as NSString? else { return 0 }
        var adjusted: [NSLayoutManager.GlyphProperty]?
        for i in 0..<glyphRange.length where ListLine.isCheckboxMarker(in: text, at: characterIndexes[i]) {
            if adjusted == nil {
                adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
            }
            adjusted?[i] = .controlCharacter
        }
        guard let adjusted else { return 0 }
        layoutManager.setGlyphs(glyphs, properties: adjusted, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt characterIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let text = layoutManager.textStorage?.string as NSString?,
              ListLine.isCheckboxMarker(in: text, at: characterIndex)
        else { return action }
        return .whitespace
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: NSRect,
        glyphPosition: NSPoint,
        characterIndex: Int
    ) -> NSRect {
        NSRect(x: glyphPosition.x, y: 0, width: checkboxWidth, height: proposedRect.height)
    }
}
