import Foundation

/// The note stack, the nine fixed slots and the current note. UI-independent.
///
/// The stack order is a snapshot sorted by `touchedAt` (newest first). It is
/// refreshed when the window opens and by "newest" (⌘1), but *not* while typing,
/// so the current note does not jump around during navigation.
///
/// In slot mode the current note is the note of one of the slots 1–9. An empty
/// slot shows a blank note. Blank notes are never kept: leaving or trashing a
/// blank note deletes it.
@MainActor
final class NoteStackModel {
    enum Mode: Equatable {
        case stack
        case slot(Int)
    }

    static let slotCount = 9

    private let store: NoteStore
    private let now: () -> Date

    private(set) var notes: [Note] = []
    private(set) var currentIndex = 0
    private(set) var hasUnsavedChanges = false
    private(set) var mode: Mode = .stack
    /// The slot shown when switching to slot mode (⌘T).
    private(set) var lastSlot = 1
    private var slotNote: Note?

    init(store: NoteStore, now: @escaping () -> Date = Date.init) throws {
        self.store = store
        self.now = now
        try store.deleteBlankNotes()
        notes = try store.stack()
        if notes.isEmpty {
            try insertNewNote()
        }
    }

    var current: Note {
        if case .slot = mode, let slotNote { return slotNote }
        return notes[currentIndex]
    }

    var count: Int { notes.count }

    var isInSlotMode: Bool {
        if case .slot = mode { return true }
        return false
    }

    /// "2/5" in the stack, "Platz 3" in slot mode.
    var positionDescription: String {
        switch mode {
        case .stack: "\(currentIndex + 1)/\(notes.count)"
        case .slot(let slot): "Platz \(slot)"
        }
    }

    // MARK: Editing

    func updateCurrentText(_ text: String) {
        guard text != current.text else { return }
        let date = now()
        modifyCurrent {
            $0.text = text
            $0.updatedAt = date
            $0.touchedAt = date
        }
        hasUnsavedChanges = true
    }

    func save() throws {
        guard hasUnsavedChanges else { return }
        try store.save(current)
        hasUnsavedChanges = false
    }

    // MARK: Stack navigation

    /// ⌘N. Always in the stack. A blank current stack note is reused.
    func createNote() throws {
        if isInSlotMode {
            try leaveSlot()
        } else if current.isBlank {
            if currentIndex != 0 { try bringCurrentToFront() }
            return
        }
        try save()
        if notes.first?.isBlank == true {
            currentIndex = 0
            return
        }
        try insertNewNote()
    }

    /// ⌘[ – one step down the stack, or to the next slot.
    func showOlder() throws {
        if case .slot(let slot) = mode {
            if slot < Self.slotCount { try selectSlot(slot + 1) }
            return
        }
        guard currentIndex < notes.count - 1 else { return }
        if try leaveCurrent() == .removed {
            return // the older note slid into the current position
        }
        currentIndex += 1
    }

    /// ⌘] – one step up the stack, or to the previous slot.
    func showNewer() throws {
        if case .slot(let slot) = mode {
            if slot > 1 { try selectSlot(slot - 1) }
            return
        }
        guard currentIndex > 0 else { return }
        _ = try leaveCurrent()
        currentIndex -= 1
    }

    /// ⌘1 in the stack – re-sorts the stack and shows the most recently touched note.
    func showNewest() throws {
        if isInSlotMode { try leaveSlot() }
        try save()
        try reloadSnapshot()
        guard currentIndex != 0 else { return }
        _ = try leaveCurrent()
        currentIndex = 0
    }

    /// ⌘⇧1 – moves the current stack note to the top. Does nothing in slot mode.
    func bringCurrentToFront() throws {
        guard !isInSlotMode else { return }
        notes[currentIndex].touchedAt = now()
        hasUnsavedChanges = true
        try save()
        let note = notes.remove(at: currentIndex)
        notes.insert(note, at: 0)
        currentIndex = 0
    }

    // MARK: Slots

    /// ⌘T – switches between the stack and the slots.
    func toggleMode() throws {
        if isInSlotMode {
            try leaveSlot()
        } else {
            try selectSlot(lastSlot)
        }
    }

    /// Shows slot 1–9 (creating a blank note there if it is empty).
    func selectSlot(_ slot: Int) throws {
        guard (1...Self.slotCount).contains(slot) else { return }
        if mode == .slot(slot) { return }
        if isInSlotMode {
            try leaveSlotNote()
        } else {
            _ = try leaveCurrent()
            currentIndex = min(currentIndex, notes.count - 1)
        }
        if let existing = try store.note(inSlot: slot) {
            slotNote = existing
        } else {
            let note = Note(date: now(), slot: slot)
            try store.insert(note)
            slotNote = note
        }
        mode = .slot(slot)
        lastSlot = slot
    }

    private func leaveSlot() throws {
        try leaveSlotNote()
        mode = .stack
        if notes.isEmpty { try insertNewNote() }
        currentIndex = min(currentIndex, notes.count - 1)
    }

    private func leaveSlotNote() throws {
        try save()
        if let slotNote, slotNote.isBlank {
            try store.deleteBlank(id: slotNote.id)
        }
        slotNote = nil
    }

    // MARK: Trash & archive

    /// ⌘D – moves the current note to the trash. In the stack the next older note
    /// is shown, in a slot the slot becomes empty. Returns the id of the removed note.
    @discardableResult
    func trashCurrent() throws -> String {
        try removeCurrent { note in
            if note.isBlank {
                try store.deleteBlank(id: note.id)
            } else {
                try store.trash(note, at: now())
            }
        }
    }

    /// ⌘⇧A – moves the current note to the archive. Blank notes are just deleted.
    @discardableResult
    func archiveCurrent() throws -> String {
        try removeCurrent { note in
            if note.isBlank {
                try store.deleteBlank(id: note.id)
            } else {
                try store.archive(note, at: now())
            }
        }
    }

    private func removeCurrent(_ remove: (Note) throws -> Void) throws -> String {
        let note = current
        try remove(note)
        hasUnsavedChanges = false

        if case .slot(let slot) = mode {
            let blank = Note(date: now(), slot: slot)
            try store.insert(blank)
            slotNote = blank
            return note.id
        }

        notes.remove(at: currentIndex)
        if notes.isEmpty {
            try insertNewNote()
        } else {
            currentIndex = min(currentIndex, notes.count - 1)
        }
        return note.id
    }

    // MARK: Opening & reloading

    /// Shows a note found in the search. Notes in the stack or a slot are shown
    /// directly; archived or trashed notes must be restored first.
    @discardableResult
    func open(noteID: String) throws -> Bool {
        try save()
        guard let note = try store.note(id: noteID) else { return false }
        switch note.location {
        case .slot(let slot):
            try selectSlot(slot)
            return true
        case .stack:
            if isInSlotMode { try leaveSlot() }
            try reloadSnapshot()
            guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return false }
            if index != currentIndex {
                _ = try leaveCurrent()
                currentIndex = notes.firstIndex { $0.id == noteID } ?? 0
            }
            return true
        case .archive, .trash:
            return false
        }
    }

    /// Restores a note from the trash or archive and shows it.
    func restoreAndOpen(noteID: String) throws {
        guard let note = try store.note(id: noteID) else { return }
        switch note.location {
        case .trash: try store.restoreFromTrash(id: noteID, at: now())
        case .archive: try store.unarchive(id: noteID, at: now())
        case .stack, .slot: break
        }
        try open(noteID: noteID)
    }

    /// Reloads everything from the database (after a restore or external change).
    func reloadAll() throws {
        hasUnsavedChanges = false
        if case .slot(let slot) = mode {
            slotNote = try store.note(inSlot: slot)
            if slotNote == nil {
                let blank = Note(date: now(), slot: slot)
                try store.insert(blank)
                slotNote = blank
            }
        }
        try reloadSnapshot()
    }

    /// Called whenever the window is shown: re-sorts the stack and, if requested,
    /// starts with a fresh blank stack note.
    func prepareForShow(startFresh: Bool) throws {
        try save()
        if case .slot(let slot) = mode {
            slotNote = try store.note(inSlot: slot) ?? slotNote
        }
        try reloadSnapshot()
        if startFresh {
            try createNote()
        }
    }

    // MARK: Private

    private enum LeaveResult { case kept, removed }

    private func modifyCurrent(_ change: (inout Note) -> Void) {
        if isInSlotMode, slotNote != nil {
            change(&slotNote!)
        } else {
            change(&notes[currentIndex])
        }
    }

    /// Leaves the current stack note; blank ones are deleted.
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
        let currentID = notes.indices.contains(currentIndex) ? notes[currentIndex].id : nil
        notes = try store.stack()
        if notes.isEmpty {
            try insertNewNote()
        } else {
            currentIndex = notes.firstIndex { $0.id == currentID } ?? 0
        }
    }
}
