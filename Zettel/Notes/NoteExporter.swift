import AppKit
import UniformTypeIdentifiers

/// Export of single notes (.md, .txt, PDF) and of all notes as ZIP.
enum NoteExporter {
    enum Format: String, CaseIterable, Sendable {
        case markdown, text, pdf

        var title: String {
            switch self {
            case .markdown: "Markdown (.md)"
            case .text: "Text (.txt)"
            case .pdf: "PDF"
            }
        }

        var contentType: UTType {
            switch self {
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            case .text: .plainText
            case .pdf: .pdf
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .text: "txt"
            case .pdf: "pdf"
            }
        }
    }

    /// File name from the note's title, without characters file systems dislike.
    static func suggestedName(for note: Note) -> String {
        let title = NoteSearch.title(of: note.text)
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\t"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let short = String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? "Notiz" : short
    }

    /// Markdown as stored, or plain text as shown in the editor (☐ ☑ •).
    static func content(of note: Note, as format: Format) -> String {
        switch format {
        case .markdown, .pdf: note.text
        case .text: NoteFormat.display(fromMarkdown: note.text)
        }
    }

    /// A4 PDF with automatic page breaks.
    @MainActor
    static func pdfData(of note: Note, fontSize: CGFloat = 12) -> Data {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 56
        info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: NoteFormat.display(fromMarkdown: note.text),
            attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black]
        ))
        textView.sizeToFit()

        // A print job saved to a file paginates (pdfOperation would make one long page).
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zettel-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
        return (try? Data(contentsOf: url)) ?? Data()
    }

    /// Writes all notes except trashed and locked ones as Markdown files into a ZIP
    /// (folders Stapel, Plätze, Archiv). Returns the number of exported notes.
    @discardableResult
    static func exportAll(_ notes: [Note], to destination: URL) throws -> Int {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("Zettel-Export-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Zettel")
        defer { try? fileManager.removeItem(at: root) }

        var count = 0
        var usedNames: Set<String> = []
        for note in notes where !note.isBlank && !note.isLocked && note.trashedAt == nil {
            let (subfolder, prefix): (String, String) = switch note.location {
            case .stack: ("Stapel", "")
            case .slot(let slot): ("Plätze", "Platz \(slot) – ")
            case .archive: ("Archiv", "")
            case .trash: ("Papierkorb", "")
            }
            let directory = folder.appendingPathComponent(subfolder)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var name = prefix + suggestedName(for: note)
            var counter = 2
            while usedNames.contains(subfolder + "/" + name) {
                name = prefix + suggestedName(for: note) + " \(counter)"
                counter += 1
            }
            usedNames.insert(subfolder + "/" + name)
            try note.text.write(to: directory.appendingPathComponent(name).appendingPathExtension("md"), atomically: true, encoding: .utf8)
            count += 1
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // The system zips a folder for "uploading"; no ZIP library needed.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinationError) { zipURL in
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return count
    }
}
