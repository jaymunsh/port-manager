import Foundation

/// A running Docker container as reported by `docker ps`.
struct DockerContainer: Identifiable, Hashable, Sendable {
    var id: String          // short container id
    var name: String
    var image: String
    /// Published host ports this container maps (e.g. 5432 for `0.0.0.0:5432->5432`).
    var hostPorts: [Int]
}
