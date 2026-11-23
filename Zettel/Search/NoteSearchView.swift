import SwiftUI

/// State of the ⌘F search: query, filter, results and keyboard selection.
@MainActor
@Observable
final class NoteSearchViewModel {
    var query = "" { didSet { update() } }
    var filter: NoteSearch.Filter = .all { didSet { update() } }
    private(set) var results: [NoteSearch.Result] = []
    var selectedID: String?

    private var notes: [Note] = []
    private let loadNotes: () -> [Note]
    /// Opens a result. `restoring` is true for archived and trashed notes.
    private let onOpen: (Note, _ restoring: Bool) -> Void

    init(loadNotes: @escaping () -> [Note], onOpen: @escaping (Note, Bool) -> Void) {
        self.loadNotes = loadNotes
        self.onOpen = onOpen
    }

    /// Fresh data each time the search opens.
    func reload() {
        notes = loadNotes()
        update()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(index + offset, 0), results.count - 1)
        selectedID = results[next].id
    }

    func activateSelection() {
        guard let result = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        activate(result)
    }

    func activate(_ result: NoteSearch.Result) {
        switch result.note.location {
        case .stack, .slot: onOpen(result.note, false)
        case .archive, .trash: onOpen(result.note, true)
        }
    }

    private func update() {
        results = NoteSearch.search(notes, query: query, filter: filter)
        if !results.contains(where: { $0.id == selectedID }) {
            selectedID = results.first?.id
        }
    }
}

/// ⌘F: search over all notes with list and filter. Shown inside the note window.
struct NoteSearchView: View {
    @Bindable var model: NoteSearchViewModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(Strings.Search.placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                    .onKeyPress(.return) { model.activateSelection(); return .handled }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Picker(Strings.Search.filter, selection: $model.filter) {
                ForEach(NoteSearch.Filter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 12)

            Divider()

            if model.results.isEmpty {
                Spacer()
                Text(model.query.isEmpty ? Strings.Search.empty : Strings.Search.noResults)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedID) {
                        ForEach(model.results) { result in
                            ResultRow(result: result) { model.activate(result) }
                                .tag(result.id)
                                .id(result.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { model.activate(result) }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: model.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { fieldFocused = true }
    }
}

private struct ResultRow: View {
    let result: NoteSearch.Result
    let activate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title.isEmpty ? Strings.Search.untitled : result.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(result.note.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                switch result.note.location {
                case .stack:
                    EmptyView()
                case .slot(let slot):
                    Badge(text: "Platz \(slot)")
                case .archive:
                    Button(Strings.Search.unarchive, action: activate).controlSize(.small)
                case .trash:
                    Button(Strings.Search.restore, action: activate).controlSize(.small)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}
