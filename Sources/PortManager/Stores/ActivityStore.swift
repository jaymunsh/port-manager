import Foundation

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var events: [ActivityEvent] = []

    private let limit = 300

    func log(_ kind: ActivityEvent.Kind, _ message: String) {
        events.insert(ActivityEvent(date: .now, kind: kind, message: message), at: 0)
        if events.count > limit {
            events.removeLast(events.count - limit)
        }
    }

    func clear() {
        events.removeAll()
    }
}
