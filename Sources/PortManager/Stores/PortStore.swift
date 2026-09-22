import Foundation

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var stats: [pid_t: ProcStat] = [:]
    @Published private(set) var netRates: [pid_t: NetRate] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published var includeUDP = UserDefaults.standard.bool(forKey: "ports.includeUDP") {
        didSet {
            UserDefaults.standard.set(includeUDP, forKey: "ports.includeUDP")
            Task { await refresh() }
        }
    }
    @Published var showConnections = UserDefaults.standard.bool(forKey: "ports.showConnections") {
        didSet {
            UserDefaults.standard.set(showConnections, forKey: "ports.showConnections")
            Task { await refresh() }
        }
    }
    /// Seconds between automatic snapshots. 0 disables polling.
    @Published var refreshInterval: TimeInterval = {
        let v = UserDefaults.standard.double(forKey: "ports.refreshInterval")
        return v > 0 ? v : 3
    }() {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "ports.refreshInterval") }
    }

    private var pollTask: Task<Void, Never>?
    private var diffHandlers: [([PortEntry], [PortEntry]) -> Void] = []
    private var prevNet: [pid_t: (in: Int64, out: Int64, at: Date)] = [:]

    func onDiff(_ handler: @escaping ([PortEntry], [PortEntry]) -> Void) {
        diffHandlers.append(handler)
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.refreshInterval
                guard interval > 0 else { continue }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        let udp = includeUDP
        let conn = showConnections
        let result = await Task.detached(priority: .utility) {
            (try? LsofProvider().snapshot(includeUDP: udp, includeConnections: conn),
             ProcessService().allStats(),
             NettopProvider().snapshot())
        }.value
        let (snapshot, newStats, net) = result
        guard let snapshot else {
            lastError = "lsof 실행에 실패했습니다"
            return
        }
        lastError = nil
        stats = newStats
        netRates = Self.rates(from: net, previous: &prevNet)
        let isBaseline = lastUpdated == nil
        // Only listeners drive diff notifications — outbound connections
        // churn too fast to be meaningful events.
        let old = Set(entries.filter(\.isListener))
        let new = Set(snapshot.filter(\.isListener))
        entries = snapshot.sorted { ($0.port, $0.command) < ($1.port, $1.command) }
        lastUpdated = .now
        // The first snapshot is a baseline — existing listeners aren't "new".
        guard !isBaseline else { return }
        let added = new.subtracting(old).sorted { $0.port < $1.port }
        let removed = old.subtracting(new).sorted { $0.port < $1.port }
        if !added.isEmpty || !removed.isEmpty {
            for handler in diffHandlers { handler(added, removed) }
        }
    }

    /// Converts cumulative nettop counters into per-second rates.
    private static func rates(
        from snapshot: [pid_t: NettopProvider.Snapshot],
        previous: inout [pid_t: (in: Int64, out: Int64, at: Date)]
    ) -> [pid_t: NetRate] {
        let now = Date()
        var out: [pid_t: NetRate] = [:]
        for (pid, s) in snapshot {
            if let p = previous[pid] {
                let dt = max(now.timeIntervalSince(p.at), 0.1)
                out[pid] = NetRate(
                    inRate: max(0, Double(s.bytesIn - p.in) / dt),
                    outRate: max(0, Double(s.bytesOut - p.out) / dt))
            }
            previous[pid] = (s.bytesIn, s.bytesOut, now)
        }
        return out
    }

    /// Live entry matching a port+pid pair, if it still exists.
    func liveEntry(pid: pid_t, port: Int) -> PortEntry? {
        entries.first { $0.pid == pid && $0.port == port }
    }
}
