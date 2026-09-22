import Foundation

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var stats: [pid_t: ProcStat] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published var includeUDP = false {
        didSet { Task { await refresh() } }
    }
    /// Seconds between automatic snapshots. 0 disables polling.
    @Published var refreshInterval: TimeInterval = 3

    private var pollTask: Task<Void, Never>?
    private var diffHandlers: [([PortEntry], [PortEntry]) -> Void] = []

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
        let result = await Task.detached(priority: .utility) {
            (try? LsofProvider().snapshot(includeUDP: udp), ProcessService().allStats())
        }.value
        let (snapshot, newStats) = result
        guard let snapshot else {
            lastError = "lsof 실행에 실패했습니다"
            return
        }
        lastError = nil
        stats = newStats
        let isBaseline = lastUpdated == nil
        let old = Set(entries)
        let new = Set(snapshot)
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

    /// Live entry matching a port+pid pair, if it still exists.
    func liveEntry(pid: pid_t, port: Int) -> PortEntry? {
        entries.first { $0.pid == pid && $0.port == port }
    }
}
