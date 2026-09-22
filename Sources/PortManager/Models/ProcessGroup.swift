import Foundation

/// All sockets belonging to one process, aggregated for the grouped view.
struct ProcessGroup: Identifiable, Hashable, Sendable {
    var pid: pid_t
    var command: String
    var user: String
    var sockets: [PortEntry]

    var id: pid_t { pid }
    var listeners: [PortEntry] { sockets.filter(\.isListener) }
    var connections: [PortEntry] { sockets.filter { !$0.isListener } }
    /// Lowest port for stable display/sorting.
    var primaryPort: Int { sockets.map(\.port).min() ?? 0 }

    /// Distinct listening ports, sorted.
    var listenPorts: [Int] {
        Array(Set(listeners.map(\.port))).sorted()
    }
}
