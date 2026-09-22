import Foundation

struct PortPreset: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var port: Int
    var proto: String = "TCP"
    var expectedCommand: String?
    var note: String = ""
}

enum PresetStatus: String, Sendable {
    /// Nobody is listening on the port.
    case free
    /// Something is listening and it matches expectedCommand (or none was set).
    case expected
    /// Something is listening but the command does not match expectedCommand.
    case conflict
}
