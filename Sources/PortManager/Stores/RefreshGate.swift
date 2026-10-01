import Foundation

/// One collector at a time; overlapping requests are combined into one
/// follow-up using the newest operation. Every caller awaits that follow-up.
@MainActor
final class RefreshGate {
    private var task: Task<Void, Never>?
    private var pending: (@MainActor () async -> Void)?

    var isRefreshing: Bool { task != nil }

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        guard !Task.isCancelled else { return }
        pending = operation
        while pending != nil || task != nil {
            if let task {
                await task.value
            } else {
                let worker = Task { [weak self] in
                    while !Task.isCancelled, let operation = self?.pending {
                        self?.pending = nil
                        await operation()
                    }
                    self?.task = nil
                }
                task = worker
                await worker.value
            }
        }
    }

    func cancel() {
        pending = nil
        task?.cancel()
        // Retain ownership until the cancelled collector actually returns. A new
        // request waits for it before starting, including non-cooperative work.
    }
}
