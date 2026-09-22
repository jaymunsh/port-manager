import Foundation

/// "Alert me if this port/process exceeds N bytes/sec" rule.
struct BandwidthAlert: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// Match sockets on this port (nil = match by command instead).
    var port: Int?
    /// Match processes whose command contains this string (case-insensitive).
    var command: String?
    /// Threshold in bytes/sec (sum of in+out).
    var threshold: Double
    var enabled: Bool = true
}
