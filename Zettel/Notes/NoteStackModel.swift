import Foundation

/// The note stack and the current note. UI-independent.
///
/// The order is a snapshot sorted by `touchedAt` (newest first). It is refreshed
/// when the window opens and by "newest" (⌘1), but *not* while typing, so the
/// current note does not jump around during navigation.
///
/// Blank notes are never kept: leaving or trashing a blank note deletes it.
@MainActor
final class NoteStackModel {
    private let store: NoteStore
    private let now: () -> Date

    private(set) var notes: [Note] = []
    private(set) var currentIndex = 0
    private(set) var hasUnsavedChanges = false

    init(store: NoteStore, now: @escaping () -> Date = Date.init) throws {
        self.store = store
        self.now = now
        try store.deleteBlankNotes()
        notes = try store.stack()
        if notes.isEmpty {
            try insertNewNote()
        }
    }

    var current: Note { notes[currentIndex] }
    var count: Int { notes.count }

    /// "2/5" for the window title area.
    var positionDescription: String { "\(currentIndex + 1)/\(notes.count)" }

    // MARK: Editing

    func updateCurrentText(_ text: String) {
        guard text != notes[currentIndex].text else { return }
        let date = now()
        notes[currentIndex].text = text
        notes[currentIndex].updatedAt = date
        notes[currentIndex].touchedAt = date
        hasUnsavedChanges = true
    }

    func save() throws {
        guard hasUnsavedChanges else { return }
        try store.save(notes[currentIndex])
        hasUnsavedChanges = false
    }

    // MARK: Navigation

    /// ⌘N. A blank current note is reused instead of creating another one.
    func createNote() throws {
        if current.isBlank {
            if currentIndex != 0 { try bringCurrentToFront() }
            return
        }
        try save()
        try insertNewNote()
    }

    /// ⌘[ – one step down the stack.
    func showOlder() throws {
        guard currentIndex < notes.count - 1 else { return }
        if try leaveCurrent() == .removed {
            return // the older note slid into the current position
        }
        currentIndex += 1
    }

    /// ⌘] – one step up the stack.
    func showNewer() throws {
        guard currentIndex > 0 else { return }
        _ = try leaveCurrent()
        currentIndex -= 1
    }

    /// ⌘1 – re-sorts the stack and shows the most recently touched note.
    func showNewest() throws {
        try save()
        try reloadSnapshot()
        guard currentIndex != 0 else { return }
        _ = try leaveCurrent()
        currentIndex = 0
    }

    /// ⌘⇧1 – moves the current note to the top of the stack.
    func bringCurrentToFront() throws {
        notes[currentIndex].touchedAt = now()
        hasUnsavedChanges = true
        try save()
        let note = notes.remove(at: currentIndex)
        notes.insert(note, at: 0)
        currentIndex = 0
    }

    /// ⌘D – moves the current note to the trash and shows the next older one.
    /// Returns the id of the removed note.
    @discardableResult
    func trashCurrent() throws -> String {
        let note = current
        if note.isBlank {
            try store.deleteBlank(id: note.id)
        } else {
            try store.trash(note, at: now())
        }
        hasUnsavedChanges = false
        notes.remove(at: currentIndex)

        if notes.isEmpty {
            try insertNewNote()
        } else {
            currentIndex = min(currentIndex, notes.count - 1)
        }
        return note.id
    }

    /// Called whenever the window is shown: re-sorts the stack and, if requested,
    /// starts with a fresh blank note.
    func prepareForShow(startFresh: Bool) throws {
        try save()
        try reloadSnapshot()
        if startFresh {
            try createNote()
        }
    }

    // MARK: Private

    private enum LeaveResult { case kept, removed }

    private func leaveCurrent() throws -> LeaveResult {
        try save()
        guard current.isBlank, notes.count > 1 else { return .kept }
        try store.deleteBlank(id: current.id)
        notes.remove(at: currentIndex)
        return .removed
    }

    private func insertNewNote() throws {
        let note = Note(date: now())
        try store.insert(note)
        notes.insert(note, at: 0)
        currentIndex = 0
    }

    private func reloadSnapshot() throws {
        let currentID = notes.isEmpty ? nil : current.id
        notes = try store.stack()
        if notes.isEmpty {
            try insertNewNote()
        } else {
            currentIndex = notes.firstIndex { $0.id == currentID } ?? 0
        }
    }
}
