import AppKit

/// Content of the note window. Phase 1 shows a placeholder; the editor follows in Phase 2.
final class PanelContentViewController: NSViewController {
    override func loadView() {
        let root = NSView()

        let label = NSTextField(labelWithString: Strings.Panel.placeholder)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
        ])

        view = root
    }
}
