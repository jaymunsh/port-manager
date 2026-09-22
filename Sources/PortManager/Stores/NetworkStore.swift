import Foundation

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var interfaces: [NetInterface] = []
    @Published private(set) var gateway: String?
    @Published private(set) var dns: [String] = []
    @Published private(set) var lastUpdated: Date?

    private var pollTask: Task<Void, Never>?
    private var previous: [String: (bytesIn: Int64, bytesOut: Int64, at: Date)] = [:]

    /// Total up/down across active interfaces — used by the menu bar label.
    var totalInRate: Double { interfaces.reduce(0) { $0 + $1.inRate } }
    var totalOutRate: Double { interfaces.reduce(0) { $0 + $1.outRate } }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refresh() async {
        let snapshot = await Task.detached(priority: .utility) {
            let provider = NetworkProvider()
            return (provider.interfaces(), provider.defaultGateway(), provider.dnsServers())
        }.value
        let (ifaces, gw, dnsServers) = snapshot

        let now = Date()
        var enriched: [NetInterface] = []
        enriched.reserveCapacity(ifaces.count)
        for var iface in ifaces {
            if let prev = previous[iface.name] {
                let dt = max(now.timeIntervalSince(prev.at), 0.1)
                iface.inRate = max(0, Double(iface.bytesIn - prev.bytesIn) / dt)
                iface.outRate = max(0, Double(iface.bytesOut - prev.bytesOut) / dt)
            }
            previous[iface.name] = (iface.bytesIn, iface.bytesOut, now)
            enriched.append(iface)
        }
        interfaces = enriched
        gateway = gw
        dns = dnsServers
        lastUpdated = now
    }
}
