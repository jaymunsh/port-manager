import Foundation

/// Per-process network throughput in bytes/sec.
struct NetRate: Sendable, Hashable {
    var inRate: Double
    var outRate: Double
    var total: Double { inRate + outRate }
}
