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
    private var started = false
    /// Last known status per preset — transitions are what we notify on.
    private var presetStatuses: [UUID: PresetStatus] = [:]
    /// Whether each bandwidth alert was over threshold last tick.
    private var alertOver: [UUID: Bool] = [:]

    func start(ports: PortStore, devices: DeviceStore,
               presets: PresetStore, activity: ActivityStore,
               alerts: AlertStore) {
        guard !started else { return }
        started = true
        notifier.requestPermission()

        ports.onRates { [weak self] in
            self?.evaluateBandwidthAlerts(
                alerts: alerts, entries: ports.entries,
                netRates: ports.netRates, connRates: ports.connRates,
                activity: activity)
        }

        ports.onDiff { [weak self] added, removed in
            guard let self else { return }
            for entry in added {
                activity.log(.listener, "\(entry.command) started listening on \(entry.endpoint)")
                if self.notifyNewListeners {
                    self.notifier.post(
                        title: "New listener",
                        body: "\(entry.command) is now listening on \(entry.endpoint)")
                }
            }
            for entry in removed {
                activity.log(.listener, "\(entry.command) stopped listening on \(entry.endpoint)")
            }
            self.evaluatePresets(presets: presets, entries: ports.entries, activity: activity)
        }

        devices.onDiskEvent = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .appeared(let info):
                    if let mount = info.mountPoint {
                        activity.log(.disk, "\(info.volumeName) mounted at \(mount)")
                    } else {
                        activity.log(.disk, "\(info.volumeName) attached (not mounted)")
                    }
                    if self.notifyDiskEvents {
                        self.notifier.post(title: "Disk mounted", body: info.volumeName)
                    }
                case .unmounted(let info):
                    activity.log(.disk, "\(info.volumeName) unmounted")
                case .disappeared(let bsd):
                    activity.log(.disk, "\(bsd) removed")
                    if self.notifyDiskEvents {
                        self.notifier.post(title: "Disk removed", body: bsd)
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
        for alert in alerts.alerts where alert.enabled {
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
                notifier.post(title: "Bandwidth alert", body: msg)
            }
        }
    }

    private func evaluatePresets(presets: PresetStore, entries: [PortEntry],
                                 activity: ActivityStore) {
        for preset in presets.presets {
            let status = presets.status(for: preset, entries: entries)
            let previous = presetStatuses[preset.id]
            presetStatuses[preset.id] = status
            guard previous != status else { continue }
            switch status {
            case .conflict:
                let holder = entries.first { $0.port == preset.port }?.command ?? "?"
                activity.log(.preset, "\(preset.name) :\(preset.port) conflict — held by \(holder)")
                if notifyPresetConflicts {
                    notifier.post(
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
