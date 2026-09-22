import Foundation

/// Turns raw store diffs into activity log entries and user notifications.
@MainActor
final class MonitorEngine: ObservableObject {
    @Published var notifyNewListeners = true
    @Published var notifyPresetConflicts = true
    @Published var notifyDiskEvents = true

    private let notifier = NotifyService()
    private var started = false
    /// Last known status per preset — transitions are what we notify on.
    private var presetStatuses: [UUID: PresetStatus] = [:]

    func start(ports: PortStore, devices: DeviceStore,
               presets: PresetStore, activity: ActivityStore) {
        guard !started else { return }
        started = true
        notifier.requestPermission()

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
