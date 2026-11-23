/// Runs an action once after input has paused for `delay`.
/// Only a single one-shot task exists while input is pending; nothing runs when idle.
@MainActor
final class Debouncer {
    private let delay: Duration
    private let action: @MainActor () -> Void
    private var task: Task<Void, Never>?

    init(delay: Duration, action: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.action = action
    }

    var isPending: Bool { task != nil }

    func schedule() {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.task = nil
            self.action()
        }
    }

    /// Runs a pending action immediately.
    func flush() {
        guard isPending else { return }
        cancel()
        action()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
