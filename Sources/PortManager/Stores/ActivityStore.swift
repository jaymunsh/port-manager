import Foundation

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var events: [ActivityEvent] = []

    /// Days of history kept on disk; loaded back on launch.
    @Published var retentionDays: Int = {
        let v = UserDefaults.standard.integer(forKey: "history.retentionDays")
        return v > 0 ? v : 7
    }() {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "history.retentionDays")
            history.prune(olderThan: retentionDays)
        }
    }

    private let history: HistoryService
    private let limit = 500

    init(history: HistoryService = HistoryService()) {
        self.history = history
        history.prune(olderThan: retentionDays)
        events = Array(history.loadRecent(days: retentionDays).prefix(limit))
    }

    func log(_ kind: ActivityEvent.Kind, _ message: String) {
        let event = ActivityEvent(date: .now, kind: kind, message: message)
        events.insert(event, at: 0)
        if events.count > limit {
            events.removeLast(events.count - limit)
        }
        history.append(event)
    }

    func clear() {
        events.removeAll()
        history.clear()
    }
}
