import Foundation

struct NetworkConfiguration: Sendable {
    var gateway: String?
    var dns: [String]
}

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var interfaces: [NetInterface] = []
    @Published private(set) var gateway: String?
    @Published private(set) var dns: [String] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?

    private var pollTask: Task<Void, Never>?
    private let refreshGate = RefreshGate()
    private var tracker = RateTracker<String>()
    private var lastConfigurationUpdate: TimeInterval?
    private var configurationRequested = false
    private var configurationSignature: [String] = []
    private let interfaceCollector: @Sendable () throws -> [NetInterface]
    private let configurationCollector: @Sendable () throws -> NetworkConfiguration
    private let clock: () -> TimeInterval

    init(interfaceCollector: @escaping @Sendable () throws -> [NetInterface] = { try NetworkProvider().interfaces() },
         configurationCollector: @escaping @Sendable () throws -> NetworkConfiguration = {
             let provider = NetworkProvider()
             return try NetworkConfiguration(gateway: provider.defaultGateway(), dns: provider.dnsServers())
         }, clock: @escaping () -> TimeInterval = { Foundation.ProcessInfo.processInfo.systemUptime }) {
        self.interfaceCollector = interfaceCollector
        self.configurationCollector = configurationCollector
        self.clock = clock
    }

    var totalInRate: Double { interfaces.filter(\.isActive).reduce(0) { $0 + $1.inRate } }
    var totalOutRate: Double { interfaces.filter(\.isActive).reduce(0) { $0 + $1.outRate } }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(forceConfiguration: false)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        refreshGate.cancel()
        tracker.reset()
        lastConfigurationUpdate = nil
    }

    /// Manual refresh always updates DNS/gateway. Polling caches them for 30s,
    /// invalidating earlier when interface addressing/availability changes.
    func refresh(forceConfiguration: Bool = true) async {
        configurationRequested = configurationRequested || forceConfiguration
        await refreshGate.run { [weak self] in await self?.refreshOnce() }
    }

    private func refreshOnce() async {
        let collectInterfaces = interfaceCollector
        do {
            let snapshot = try await Background.run(collectInterfaces)
            guard !Task.isCancelled else { return }
            let now = clock()
            let signature = snapshot.map {
                "\($0.name)|\($0.ipv4 ?? "")|\($0.ipv6 ?? "")|\($0.isUp)|\($0.isActive)"
            }.sorted()
            let needsConfiguration = configurationRequested || lastConfigurationUpdate == nil
                || now - (lastConfigurationUpdate ?? 0) >= 30 || signature != configurationSignature
            if needsConfiguration {
                configurationRequested = false
                let collectConfiguration = configurationCollector
                let configuration = try await Background.run(collectConfiguration)
                guard !Task.isCancelled else { return }
                gateway = configuration.gateway
                dns = configuration.dns
                lastConfigurationUpdate = now
                configurationSignature = signature
            }
            let counters = Dictionary(uniqueKeysWithValues: snapshot.map {
                ($0.name, NettopProvider.Snapshot(bytesIn: $0.bytesIn, bytesOut: $0.bytesOut))
            })
            let rates = tracker.update(counters, at: now)
            interfaces = snapshot.map { value in
                var iface = value
                iface.inRate = rates[value.name]?.inRate ?? 0
                iface.outRate = rates[value.name]?.outRate ?? 0
                return iface
            }
            lastUpdated = .now
            lastError = nil
        } catch {
            guard !Task.isCancelled else { return }
            lastError = error.localizedDescription
        }
    }
}
