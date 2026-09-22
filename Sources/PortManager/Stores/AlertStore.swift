import Foundation

@MainActor
final class AlertStore: ObservableObject {
    @Published private(set) var alerts: [BandwidthAlert] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortManager", isDirectory: true)
        return dir.appendingPathComponent("alerts.json")
    }()

    init() {
        load()
    }

    /// Current in+out bytes/sec matching a rule.
    func currentRate(for alert: BandwidthAlert,
                     entries: [PortEntry],
                     netRates: [pid_t: NetRate],
                     connRates: [NettopProvider.ConnKey: NetRate]) -> Double {
        if let port = alert.port {
            let matching = entries.filter { $0.port == port }
            let connSum = matching.reduce(0.0) { $0 + (connRates[$1.connKey]?.total ?? 0) }
            if connSum > 0 { return connSum }
            // No per-socket data — fall back to the owning process total.
            return matching.filter(\.isListener)
                .reduce(0.0) { $0 + (netRates[$1.pid]?.total ?? 0) }
        }
        if let command = alert.command {
            let pids = Set(entries.filter {
                $0.command.localizedCaseInsensitiveContains(command)
            }.map(\.pid))
            return pids.reduce(0.0) { $0 + (netRates[$1]?.total ?? 0) }
        }
        return 0
    }

    func add(_ alert: BandwidthAlert) {
        alerts.append(alert)
        save()
    }

    func update(_ alert: BandwidthAlert) {
        guard let idx = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[idx] = alert
        save()
    }

    func remove(_ alert: BandwidthAlert) {
        alerts.removeAll { $0.id == alert.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BandwidthAlert].self, from: data)
        else { return }
        alerts = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(alerts).write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort persistence.
        }
    }
}
