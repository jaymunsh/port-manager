import Foundation

struct PortSnapshot: Sendable {
    var entries: [PortEntry]
    var stats: [pid_t: ProcStat]
}

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var stats: [pid_t: ProcStat] = [:]
    @Published private(set) var netRates: [pid_t: NetRate] = [:]
    @Published private(set) var connRates: [NettopProvider.ConnKey: NetRate] = [:]
    @Published private(set) var dockerByPort: [Int: DockerContainer] = [:]
    @Published private(set) var dockerContainers: [DockerContainer] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var bandwidthError: String?
    @Published var includeUDP = false {
        didSet {
            guard initialized else { return }
            defaults.set(includeUDP, forKey: "ports.includeUDP")
            Task { await refresh() }
        }
    }
    @Published var showConnections = false {
        didSet {
            guard initialized else { return }
            defaults.set(showConnections, forKey: "ports.showConnections")
            Task { await refresh() }
        }
    }
    /// 0 pauses port polling; manual refresh remains available.
    @Published var refreshInterval: TimeInterval = 3 {
        didSet {
            guard initialized else { return }
            defaults.set(refreshInterval, forKey: "ports.refreshInterval")
            if polling { startPortPolling() }
        }
    }

    var bandwidthMonitoringEnabled = false { didSet { updateBandwidthPolling() } }
    private var consumers: Set<UUID> = []
    private var polling = false
    private var pollTask: Task<Void, Never>?
    private var netTask: Task<Void, Never>?
    private var dockerTask: Task<Void, Never>?
    private let refreshGate = RefreshGate()
    private var diffHandlers: [([PortEntry], [PortEntry]) -> Void] = []
    private var snapshotHandlers: [() -> Void] = []
    private var rateHandlers: [() -> Void] = []
    private var pidTracker = RateTracker<pid_t>()
    private var connTracker = RateTracker<NettopProvider.ConnKey>()
    private let collector: @Sendable (Bool, Bool) throws -> PortSnapshot
    private let bandwidthCollector: @Sendable () throws -> NettopProvider.Result
    private let dockerCollector: @Sendable () -> DockerProvider.Snapshot
    private let defaults: UserDefaults
    private var initialized = false

    init(defaults: UserDefaults = .standard,
         collector: @escaping @Sendable (Bool, Bool) throws -> PortSnapshot = PortStore.collect,
         bandwidthCollector: @escaping @Sendable () throws -> NettopProvider.Result = { try NettopProvider().snapshot() },
         dockerCollector: @escaping @Sendable () -> DockerProvider.Snapshot = { DockerProvider().snapshot() }) {
        self.collector = collector
        self.bandwidthCollector = bandwidthCollector
        self.dockerCollector = dockerCollector
        self.defaults = defaults
        includeUDP = defaults.bool(forKey: "ports.includeUDP")
        showConnections = defaults.bool(forKey: "ports.showConnections")
        if let interval = defaults.object(forKey: "ports.refreshInterval") as? Double {
            refreshInterval = interval.isFinite ? max(0, interval) : 3
        }
        initialized = true
    }

    nonisolated private static func collect(udp: Bool, connections: Bool) throws -> PortSnapshot {
        let service = ProcessService()
        var snapshot = try LsofProvider().snapshot(includeUDP: udp, includeConnections: connections)
        let identities = Dictionary(uniqueKeysWithValues: Set(snapshot.map(\.pid)).map {
            ($0, service.identity(for: $0))
        })
        for index in snapshot.indices { snapshot[index].processIdentity = identities[snapshot[index].pid] ?? nil }
        return PortSnapshot(entries: snapshot, stats: service.allStats())
    }

    func onDiff(_ handler: @escaping ([PortEntry], [PortEntry]) -> Void) { diffHandlers.append(handler) }
    func onSnapshot(_ handler: @escaping () -> Void) { snapshotHandlers.append(handler) }
    func onRates(_ handler: @escaping () -> Void) { rateHandlers.append(handler) }

    func setBandwidthConsumer(_ id: UUID, active: Bool) {
        if active { consumers.insert(id) } else { consumers.remove(id) }
        updateBandwidthPolling()
    }

    func startPolling() {
        guard !polling else { return }
        polling = true
        startPortPolling()
        updateBandwidthPolling()
        dockerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let collect = self.dockerCollector
                guard let snapshot = try? await Background.run(collect), !Task.isCancelled else { return }
                self.dockerContainers = snapshot.containers
                self.dockerByPort = snapshot.byPort
                try? await Task.sleep(for: .seconds(snapshot.available ? 15 : 60))
            }
        }
    }

    private func startPortPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.refreshInterval
                if interval > 0 && interval.isFinite { await self.refresh() }
                try? await Task.sleep(for: .seconds(interval > 0 && interval.isFinite ? interval : 1))
            }
        }
    }

    private func updateBandwidthPolling() {
        guard polling && (bandwidthMonitoringEnabled || !consumers.isEmpty) else {
            netTask?.cancel()
            netTask = nil
            pidTracker.reset()
            connTracker.reset()
            if !netRates.isEmpty || !connRates.isEmpty {
                netRates = [:]
                connRates = [:]
                for handler in rateHandlers { handler() }
            }
            bandwidthError = nil
            return
        }
        guard netTask == nil else { return }
        netTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let started = Foundation.ProcessInfo.processInfo.systemUptime
                let collect = self.bandwidthCollector
                do {
                    let snapshot = try await Background.run(collect)
                    guard !Task.isCancelled else { return }
                    self.bandwidthError = nil
                    self.netRates = self.pidTracker.update(snapshot.perPid)
                    self.connRates = self.connTracker.update(snapshot.perConn)
                    for handler in self.rateHandlers { handler() }
                    let remaining = max(0, 5 - (Foundation.ProcessInfo.processInfo.systemUptime - started))
                    if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.bandwidthError = error.localizedDescription
                    self.pidTracker.reset()
                    self.connTracker.reset()
                    self.netRates = [:]
                    self.connRates = [:]
                    // A failing collector must not turn into a hot spawn loop.
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    func stopPolling() {
        polling = false
        pollTask?.cancel()
        pollTask = nil
        dockerTask?.cancel()
        dockerTask = nil
        refreshGate.cancel()
        updateBandwidthPolling()
    }

    static func groups(from entries: [PortEntry]) -> [ProcessGroup] {
        Dictionary(grouping: entries, by: \.pid).map { pid, sockets in
            ProcessGroup(pid: pid, command: sockets.first?.command ?? "?", user: sockets.first?.user ?? "",
                         sockets: sockets.sorted { $0.port < $1.port })
        }.sorted { ($0.primaryPort, $0.command) < ($1.primaryPort, $1.command) }
    }

    func container(forPort port: Int) -> DockerContainer? { dockerByPort[port] }

    func refresh() async {
        await refreshGate.run { [weak self] in await self?.refreshOnce() }
    }

    private func refreshOnce() async {
        let udp = includeUDP, connections = showConnections
        let collect = collector
        do {
            let snapshot = try await Background.run { try collect(udp, connections) }
            guard !Task.isCancelled, udp == includeUDP, connections == showConnections else { return }
            lastError = nil
            stats = snapshot.stats
            let baseline = lastUpdated == nil
            let old = Set(entries.filter(\.isListener)), new = Set(snapshot.entries.filter(\.isListener))
            entries = snapshot.entries.sorted { ($0.port, $0.command) < ($1.port, $1.command) }
            lastUpdated = .now
            if !baseline {
                let added = new.subtracting(old).sorted { $0.port < $1.port }
                let removed = old.subtracting(new).sorted { $0.port < $1.port }
                if !added.isEmpty || !removed.isEmpty {
                    for handler in diffHandlers { handler(added, removed) }
                }
            }
            // Includes the baseline, even when there are no listener changes.
            for handler in snapshotHandlers { handler() }
        } catch {
            guard !Task.isCancelled, udp == includeUDP, connections == showConnections else { return }
            lastError = error.localizedDescription
        }
    }

    func liveEntry(pid: pid_t, port: Int) -> PortEntry? {
        entries.first { $0.pid == pid && $0.port == port }
    }
}
