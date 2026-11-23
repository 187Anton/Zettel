import AppKit

/// Small list of keywords shown below the cursor after typing `/` at a line start.
/// It lives inside the text view (no extra window), so the non-activating panel
/// keeps keyboard focus; `NoteTextView` forwards keys to it.
final class KeywordPickerView: NSVisualEffectView {
    let keywords: [Keyword]
    private(set) var selectedIndex = 0
    var onChoose: ((Keyword) -> Void)?

    private var rows: [NSView] = []

    init(keywords: [Keyword] = Keyword.allCases, font: NSFont) {
        self.keywords = keywords
        super.init(frame: .zero)
        material = .menu
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, keyword) in keywords.enumerated() {
            let row = makeRow(number: index + 1, keyword: keyword, font: font)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
            rows.append(row)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        updateSelection()
        setFrameSize(fittingSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Keys

    /// Handles a key press. Returns `false` if the picker does not use the key
    /// (the caller then closes it and processes the key normally).
    func handleKey(keyCode: Int, characters: String?) -> Bool {
        if let digit = characters.flatMap(Int.init), (1...keywords.count).contains(digit) {
            onChoose?(keywords[digit - 1])
            return true
        }
        switch keyCode {
        case 126: // ↑
            selectedIndex = (selectedIndex - 1 + keywords.count) % keywords.count
            updateSelection()
            return true
        case 125: // ↓
            selectedIndex = (selectedIndex + 1) % keywords.count
            updateSelection()
            return true
        case 36, 76: // Return, Enter
            onChoose?(keywords[selectedIndex])
            return true
        default:
            return false
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = rows.firstIndex(where: { $0.frame.contains(convert(point, to: $0.superview)) }) {
            onChoose?(keywords[index])
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // MARK: Private

    private func makeRow(number: Int, keyword: Keyword, font: NSFont) -> NSView {
        let numberLabel = NSTextField(labelWithString: "\(number)")
        numberLabel.font = .monospacedDigitSystemFont(ofSize: font.pointSize - 1, weight: .regular)
        numberLabel.textColor = .tertiaryLabelColor
        let nameLabel = NSTextField(labelWithString: keyword.rawValue)
        nameLabel.font = .systemFont(ofSize: font.pointSize, weight: .semibold)
        let summaryLabel = NSTextField(labelWithString: keyword.summary)
        summaryLabel.font = .systemFont(ofSize: font.pointSize - 2)
        summaryLabel.textColor = .secondaryLabelColor

        let row = NSStackView(views: [numberLabel, nameLabel, summaryLabel])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 10)
        row.wantsLayer = true
        row.layer?.cornerRadius = 5
        return row
    }

    private func updateSelection() {
        for (index, row) in rows.enumerated() {
            row.layer?.backgroundColor = index == selectedIndex
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor
                : NSColor.clear.cgColor
        }
    }
}
