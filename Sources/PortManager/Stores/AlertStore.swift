import Foundation

@MainActor
final class AlertStore: ObservableObject {
    @Published private(set) var alerts: [BandwidthAlert] = []

    private let fileURL: URL
    private var changeHandlers: [() -> Void] = []
    private static let defaultFileURL: URL = {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortManager", isDirectory: true)
        return dir.appendingPathComponent("alerts.json")
    }()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        load()
    }

    func onChange(_ handler: @escaping () -> Void) { changeHandlers.append(handler) }

    /// Current in+out bytes/sec matching a rule.
    func currentRate(for alert: BandwidthAlert,
                     entries: [PortEntry],
                     netRates: [pid_t: NetRate],
                     connRates: [NettopProvider.ConnKey: NetRate]) -> Double {
        if let port = alert.port {
            let matching = entries.filter { $0.port == port }
            let pids = Set(matching.map(\.pid))
            // Accepted connections are present in nettop even when the UI
            // hides connected sockets. A measured zero is still valid data.
            let socketRates = connRates.filter { $0.key.localPort == port && pids.contains($0.key.pid) }.values
            if !socketRates.isEmpty { return socketRates.reduce(0) { $0 + $1.total } }
            // No per-socket data — fall back to the owning process total.
            return Set(matching.filter(\.isListener).map(\.pid))
                .reduce(0.0) { $0 + (netRates[$1]?.total ?? 0) }
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
        for handler in changeHandlers { handler() }
    }

    func update(_ alert: BandwidthAlert) {
        guard let idx = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[idx] = alert
        save()
        for handler in changeHandlers { handler() }
    }

    func remove(_ alert: BandwidthAlert) {
        alerts.removeAll { $0.id == alert.id }
        save()
        for handler in changeHandlers { handler() }
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
