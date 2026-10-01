import Foundation

/// Per-process network throughput in bytes/sec.
struct NetRate: Sendable, Hashable {
    var inRate: Double
    var outRate: Double
    var total: Double { inRate + outRate }
}

/// Only counters in the current snapshot are retained. Monotonic time avoids
/// spikes caused by wall-clock adjustments, sleep or time-zone changes.
struct RateTracker<Key: Hashable & Sendable>: Sendable {
    private var previous: [Key: (in: Int64, out: Int64, at: TimeInterval)] = [:]
    var count: Int { previous.count }

    mutating func update(_ snapshot: [Key: NettopProvider.Snapshot],
                         at now: TimeInterval = Foundation.ProcessInfo.processInfo.systemUptime) -> [Key: NetRate] {
        var rates: [Key: NetRate] = [:]
        var current: [Key: (in: Int64, out: Int64, at: TimeInterval)] = [:]
        for (key, sample) in snapshot {
            if let before = previous[key], now > before.at {
                let dt = max(now - before.at, 0.1)
                if sample.bytesIn >= before.in && sample.bytesOut >= before.out {
                    rates[key] = NetRate(inRate: Double(sample.bytesIn - before.in) / dt,
                                         outRate: Double(sample.bytesOut - before.out) / dt)
                } else {
                    rates[key] = NetRate(inRate: 0, outRate: 0)
                }
            }
            current[key] = (sample.bytesIn, sample.bytesOut, now)
        }
        previous = current
        return rates
    }

    mutating func reset() { previous.removeAll() }
}
