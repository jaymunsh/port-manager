import Foundation

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var stats: [pid_t: ProcStat] = [:]
    /// Per-process totals (nettop header rows).
    @Published private(set) var netRates: [pid_t: NetRate] = [:]
    /// Per-socket rates keyed by pid+local port+remote port.
    @Published private(set) var connRates: [NettopProvider.ConnKey: NetRate] = [:]
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
    private var netTask: Task<Void, Never>?
    private var diffHandlers: [([PortEntry], [PortEntry]) -> Void] = []
    private var prevNet: [pid_t: (in: Int64, out: Int64, at: Date)] = [:]
    private var prevConn: [NettopProvider.ConnKey: (in: Int64, out: Int64, at: Date)] = [:]

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
        // nettop takes ~5s per snapshot — keep it off the port-refresh
        // path so the table stays responsive.
        netTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let net = await Task.detached(priority: .utility) {
                    NettopProvider().snapshot()
                }.value
                guard !Task.isCancelled else { return }
                self.netRates = Self.rates(from: net.perPid, previous: &self.prevNet)
                self.connRates = Self.rates(from: net.perConn, previous: &self.prevConn)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        netTask?.cancel()
        netTask = nil
    }

    func refresh() async {
        let udp = includeUDP
        let conn = showConnections
        let result = await Task.detached(priority: .utility) {
            (try? LsofProvider().snapshot(includeUDP: udp, includeConnections: conn),
             ProcessService().allStats())
        }.value
        let (snapshot, newStats) = result
        guard let snapshot else {
            lastError = "lsof 실행에 실패했습니다"
            return
        }
        lastError = nil
        stats = newStats
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
    private static func rates<K: Hashable>(
        from snapshot: [K: NettopProvider.Snapshot],
        previous: inout [K: (in: Int64, out: Int64, at: Date)]
    ) -> [K: NetRate] {
        let now = Date()
        var out: [K: NetRate] = [:]
        for (key, s) in snapshot {
            if let p = previous[key] {
                let dt = max(now.timeIntervalSince(p.at), 0.1)
                out[key] = NetRate(
                    inRate: max(0, Double(s.bytesIn - p.in) / dt),
                    outRate: max(0, Double(s.bytesOut - p.out) / dt))
            }
            previous[key] = (s.bytesIn, s.bytesOut, now)
        }
        return out
    }

    /// Live entry matching a port+pid pair, if it still exists.
    func liveEntry(pid: pid_t, port: Int) -> PortEntry? {
        entries.first { $0.pid == pid && $0.port == port }
    }
}
