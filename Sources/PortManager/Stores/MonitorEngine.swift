import Foundation

/// Turns raw store diffs into activity log entries and user notifications.
@MainActor
final class MonitorEngine: ObservableObject {
    @Published var notifyNewListeners = MonitorEngine.defaultsBool("notify.newListeners") {
        didSet { Self.persist(key: "notify.newListeners", value: notifyNewListeners) }
    }
    @Published var notifyPresetConflicts = MonitorEngine.defaultsBool("notify.presetConflicts") {
        didSet { Self.persist(key: "notify.presetConflicts", value: notifyPresetConflicts) }
    }
    @Published var notifyDiskEvents = MonitorEngine.defaultsBool("notify.diskEvents") {
        didSet { Self.persist(key: "notify.diskEvents", value: notifyDiskEvents) }
    }
    @Published var notifyBandwidth = MonitorEngine.defaultsBool("notify.bandwidth") {
        didSet { Self.persist(key: "notify.bandwidth", value: notifyBandwidth) }
    }

    private static func defaultsBool(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private static func persist(key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private let notifier = NotifyService()
    private let allowNotifications: Bool
    private var started = false
    /// Last known status per preset — transitions are what we notify on.
    private var presetStatuses: [UUID: PresetStatus] = [:]
    /// Whether each bandwidth alert was over threshold last tick.
    private var alertOver: [UUID: Bool] = [:]
    private var alertRules: [UUID: BandwidthAlert] = [:]

    init(allowNotifications: Bool = true) { self.allowNotifications = allowNotifications }

    private func post(title: String, body: String) {
        if allowNotifications { notifier.post(title: title, body: body) }
    }

    func start(ports: PortStore, devices: DeviceStore,
               presets: PresetStore, activity: ActivityStore,
               alerts: AlertStore) {
        guard !started else { return }
        started = true
        if allowNotifications { notifier.requestPermission() }

        ports.onRates { [weak self, weak ports, weak alerts, weak activity] in
            guard let ports, let alerts, let activity else { return }
            self?.evaluateBandwidthAlerts(
                alerts: alerts, entries: ports.entries,
                netRates: ports.netRates, connRates: ports.connRates,
                activity: activity)
        }

        ports.onSnapshot { [weak self, weak ports, weak presets, weak activity] in
            guard let self, let ports, let presets, let activity else { return }
            self.evaluatePresets(presets: presets, entries: ports.entries, activity: activity)
        }
        presets.onChange { [weak self, weak ports, weak presets, weak activity] in
            guard let self, let ports, let presets, let activity, ports.lastUpdated != nil else { return }
            self.evaluatePresets(presets: presets, entries: ports.entries, activity: activity)
        }
        alerts.onChange { [weak self, weak ports, weak alerts, weak activity] in
            guard let self, let ports, let alerts, let activity else { return }
            ports.bandwidthMonitoringEnabled = alerts.alerts.contains(where: \.enabled)
            self.evaluateBandwidthAlerts(alerts: alerts, entries: ports.entries,
                                         netRates: ports.netRates, connRates: ports.connRates, activity: activity)
        }
        ports.bandwidthMonitoringEnabled = alerts.alerts.contains(where: \.enabled)
        if ports.lastUpdated != nil {
            evaluatePresets(presets: presets, entries: ports.entries, activity: activity)
        }

        ports.onDiff { [weak self, weak activity] added, removed in
            guard let self, let activity else { return }
            for entry in added {
                activity.log(.listener, "\(entry.command) started listening on \(entry.endpoint)")
                if self.notifyNewListeners {
                    self.post(
                        title: "New listener",
                        body: "\(entry.command) is now listening on \(entry.endpoint)")
                }
            }
            for entry in removed {
                activity.log(.listener, "\(entry.command) stopped listening on \(entry.endpoint)")
            }
        }

        devices.onDiskEvent = { [weak self, weak activity] event in
            Task { @MainActor in
                guard let self, let activity else { return }
                switch event {
                case .appeared(let info):
                    if let mount = info.mountPoint {
                        activity.log(.disk, "\(info.volumeName) mounted at \(mount)")
                    } else {
                        activity.log(.disk, "\(info.volumeName) attached (not mounted)")
                    }
                    if self.notifyDiskEvents {
                        self.post(title: "Disk mounted", body: info.volumeName)
                    }
                case .unmounted(let info):
                    activity.log(.disk, "\(info.volumeName) unmounted")
                case .disappeared(let bsd):
                    activity.log(.disk, "\(bsd) removed")
                    if self.notifyDiskEvents {
                        self.post(title: "Disk removed", body: bsd)
                    }
                case .changed:
                    break
                }
            }
        }
    }

    /// Notify only on the normal→over transition, not while it stays over.
    private func evaluateBandwidthAlerts(alerts: AlertStore, entries: [PortEntry],
                                         netRates: [pid_t: NetRate],
                                         connRates: [NettopProvider.ConnKey: NetRate],
                                         activity: ActivityStore) {
        let enabledIDs = Set(alerts.alerts.filter(\.enabled).map(\.id))
        alertOver = alertOver.filter { enabledIDs.contains($0.key) }
        alertRules = alertRules.filter { enabledIDs.contains($0.key) }
        for alert in alerts.alerts where alert.enabled {
            if alertRules[alert.id] != alert { alertOver[alert.id] = false }
            alertRules[alert.id] = alert
            let rate = alerts.currentRate(
                for: alert, entries: entries, netRates: netRates, connRates: connRates)
            let isOver = rate > alert.threshold
            let wasOver = alertOver[alert.id] ?? false
            alertOver[alert.id] = isOver
            guard isOver, !wasOver else { continue }
            let label = alert.port.map { ":\($0)" } ?? alert.command ?? alert.name
            let msg = "\(alert.name) (\(label)) at ↓↑\(ByteFormat.rate(rate))/s — threshold \(ByteFormat.rate(alert.threshold))/s"
            activity.log(.bandwidth, msg)
            if notifyBandwidth {
                post(title: "Bandwidth alert", body: msg)
            }
        }
    }

    private func evaluatePresets(presets: PresetStore, entries: [PortEntry],
                                 activity: ActivityStore) {
        let ids = Set(presets.presets.map(\.id))
        presetStatuses = presetStatuses.filter { ids.contains($0.key) }
        for preset in presets.presets {
            let status = presets.status(for: preset, entries: entries)
            let previous = presetStatuses[preset.id]
            presetStatuses[preset.id] = status
            guard previous != status else { continue }
            switch status {
            case .conflict:
                let holder = entries.first { $0.isListener && $0.port == preset.port && $0.proto.rawValue == preset.proto }?.command ?? "?"
                activity.log(.preset, "\(preset.name) :\(preset.port) conflict — held by \(holder)")
                if notifyPresetConflicts {
                    post(
                        title: "Port conflict",
                        body: ":\(preset.port) (\(preset.name)) is held by \(holder)")
                }
            case .expected where previous == .conflict:
                activity.log(.preset, "\(preset.name) :\(preset.port) back to expected process")
            case .free where previous != nil:
                activity.log(.preset, "\(preset.name) :\(preset.port) is now free")
            default:
                break
            }
        }
    }
}
