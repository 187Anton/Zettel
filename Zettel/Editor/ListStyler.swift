import AppKit

/// Applies display attributes after each edit: muted list markers, crossed-out
/// checked items, a hanging indent so wrapped lines align with the item text,
/// the keyword header and room on the right for `math` results.
///
/// Only attributes change here (never characters), so undo and saving are unaffected.
@MainActor
final class ListStyler: NSObject {
    static let tabWidth: CGFloat = 24

    var font: NSFont {
        didSet { markerWidths = [:] }
    }

    private var markerWidths: [String: CGFloat] = [:]

    /// Right-aligned results by line index; lines with one keep room for it.
    private(set) var annotations: [Int: LineAnnotation] = [:]

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

    /// Sets new annotations and restyles only the lines whose reserved width
    /// changed (a ticking timer usually keeps its width).
    func updateAnnotations(_ new: [Int: LineAnnotation], in storage: NSTextStorage) {
        let changed = Set(new.keys).union(annotations.keys).filter {
            new[$0].map(annotationWidth) != annotations[$0].map(annotationWidth)
        }
        annotations = new
        guard !changed.isEmpty else { return }

        let text = storage.string as NSString
        storage.beginEditing()
        var lineIndex = 0
        var location = 0
        while location <= text.length {
            let end = text.range(of: "\n", range: NSRange(location: location, length: text.length - location)).location
            if changed.contains(lineIndex), location < text.length {
                style(storage, in: NSRange(location: location, length: 0))
            }
            guard end != NSNotFound else { break }
            location = end + 1
            lineIndex += 1
        }
        storage.endEditing()
    }

    /// Restyles the paragraphs touched by `range`. Called from inside the text
    /// storage's edit processing, so it must not begin/end editing itself.
    func style(_ storage: NSTextStorage, in range: NSRange) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let paragraphs = text.paragraphRange(for: range)
        var lineIndex = Self.lineIndex(of: paragraphs.location, in: text)

        text.enumerateSubstrings(in: paragraphs, options: [.byParagraphs]) { substring, lineRange, enclosingRange, _ in
            defer { lineIndex += 1 }
            let line = substring ?? ""

            if lineIndex == 0, let header = KeywordHeader(line: line) {
                var attributes = self.headerAttributes
                if let annotation = self.annotations[0] {
                    attributes[.paragraphStyle] = self.paragraphStyle(headIndent: 0, tailIndent: -(self.annotationWidth(annotation) + 16))
                }
                storage.setAttributes(attributes, range: enclosingRange)
                let keywordLength = (line as NSString).range(of: header.keyword.rawValue, options: .caseInsensitive)
                if keywordLength.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: NSRange(
                        location: lineRange.location + keywordLength.location, length: keywordLength.length
                    ))
                }
                return
            }

            let item = ListLine(display: line)
            storage.setAttributes(self.attributes(for: item, annotation: self.annotations[lineIndex]), range: enclosingRange)

            // `//` comments are muted; they are left out of all calculations.
            if let start = CommentSyntax.commentStart(in: item.content) {
                let location = lineRange.location + item.displayMarkerLength + start
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(
                    location: location, length: NSMaxRange(lineRange) - location
                ))
            }
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

    private var headerAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: baseParagraphStyle,
        ]
    }

    private func attributes(for item: ListLine, annotation: LineAnnotation?) -> [NSAttributedString.Key: Any] {
        var headIndent: CGFloat = 0
        if let marker = item.marker {
            let width: CGFloat = if case .checkbox = marker {
                checkboxWidth + markerWidth(" ")
            } else {
                markerWidth(ListLine.displayText(for: marker))
            }
            headIndent = CGFloat(item.indent) * Self.tabWidth + width
        }
        // Keep the text clear of the right-aligned result.
        let tailIndent = annotation.map { -(annotationWidth($0) + 16) } ?? 0
        return [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle(headIndent: headIndent, tailIndent: tailIndent),
        ]
    }

    func annotationWidth(_ annotation: LineAnnotation) -> CGFloat {
        let attributes = NoteTextView.annotationAttributes(annotation.kind, pointSize: font.pointSize)
        return ceil((annotation.text as NSString).size(withAttributes: attributes).width)
    }

    static func lineIndex(of location: Int, in text: NSString) -> Int {
        var count = 0
        var position = 0
        while position < location {
            let found = text.range(of: "\n", range: NSRange(location: position, length: location - position))
            guard found.location != NSNotFound else { break }
            count += 1
            position = found.location + 1
        }
        return count
    }

    private func markerWidth(_ text: String) -> CGFloat {
        if let width = markerWidths[text] { return width }
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        markerWidths[text] = width
        return width
    }

    private func paragraphStyle(headIndent: CGFloat, tailIndent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = Self.tabWidth
        style.headIndent = headIndent
        style.tailIndent = tailIndent
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
