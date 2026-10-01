import Foundation

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var usbNodes: [DeviceNode] = []
    @Published private(set) var thunderboltNodes: [DeviceNode] = []
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var isLoadingDevices = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?

    /// Wired by MonitorEngine to log/notify on disk events.
    var onDiskEvent: ((DiskEvent) -> Void)?

    private let disks = DiskService()
    private var started = false
    private let refreshGate = RefreshGate()
    private var startupTask: Task<Void, Never>?
    private var baselineTask: Task<Void, Never>?
    /// DA fires "appeared" for every disk already attached when the session
    /// starts — suppress event reporting until that initial flood has passed.
    private var suppressingBaseline = true

    func start() {
        guard !started else { return }
        started = true
        disks.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        disks.start()
        startupTask = Task { await refresh() }
        baselineTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            suppressingBaseline = false
        }
    }

    func refresh() async {
        await refreshGate.run { [weak self] in await self?.refreshOnce() }
    }

    func stop() {
        startupTask?.cancel()
        baselineTask?.cancel()
        refreshGate.cancel()
        disks.stop()
        started = false
        suppressingBaseline = true
    }

    private func refreshOnce() async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        do {
            async let usb = Background.run { try USBProvider().usbTree() }
            async let tb = Background.run { try USBProvider().thunderboltTree() }
            let (usbResult, tbResult) = try await (usb, tb)
            guard !Task.isCancelled else { return }
            usbNodes = usbResult
            thunderboltNodes = tbResult
            volumes = disks.externalVolumes()
            lastUpdated = .now
            lastError = nil
        } catch {
            guard !Task.isCancelled else { return }
            lastError = error.localizedDescription
        }
    }

    func unmount(_ volume: VolumeInfo, force: Bool) async -> Result<Void, DiskServiceError> {
        await withCheckedContinuation { cont in
            disks.unmount(bsdName: volume.bsdName, force: force, wholeDevice: true) { result in
                cont.resume(returning: result)
            }
        }
    }

    func eject(_ volume: VolumeInfo) async -> Result<Void, DiskServiceError> {
        await withCheckedContinuation { cont in
            disks.eject(bsdName: volume.bsdName) { result in
                cont.resume(returning: result)
            }
        }
    }

    func safelyEject(_ volume: VolumeInfo, force: Bool) async -> Result<Void, DiskServiceError> {
        await EjectOperation.perform(unmount: { await self.unmount(volume, force: force) },
                                     eject: { await self.eject(volume) })
    }

    func mountPointsOnDevice(for volume: VolumeInfo) -> [String] {
        let whole = disks.wholeDiskName(for: volume.bsdName)
        let siblings = whole == nil ? [] : volumes.filter { disks.wholeDiskName(for: $0.bsdName) == whole }
        return Array(Set(([volume] + siblings).compactMap(\.mountPoint))).sorted()
    }

    func blockingProcesses(at mountPoints: [String]) async throws -> [(pid: pid_t, command: String)] {
        try await Background.run {
            var processes: [pid_t: String] = [:]
            for mount in mountPoints {
                // A successful partial unmount may already have removed this path.
                guard FileManager.default.fileExists(atPath: mount) else { continue }
                for process in try LsofProvider().processesUsing(path: mount) {
                    processes[process.pid] = process.command
                }
            }
            return processes.map { (pid: $0.key, command: $0.value) }.sorted { $0.pid < $1.pid }
        }
    }

    private func handle(_ event: DiskEvent) {
        guard started else { return }
        switch event {
        case .appeared(let info):
            if let index = volumes.firstIndex(where: { $0.bsdName == info.bsdName }) {
                volumes[index] = info
            } else {
                volumes.append(info)
                volumes.sort { $0.volumeName < $1.volumeName }
            }
            if !suppressingBaseline { onDiskEvent?(event) }
        case .disappeared(let bsd):
            guard volumes.contains(where: { $0.bsdName == bsd }) else { return }
            volumes.removeAll { $0.bsdName == bsd }
            onDiskEvent?(event)
        case .changed(let info):
            let idx = volumes.firstIndex { $0.bsdName == info.bsdName }
            let wasMounted = idx.map { volumes[$0].mountPoint != nil } ?? false
            if let idx {
                volumes[idx] = info
            } else if info.mountPoint != nil {
                volumes.append(info)
                volumes.sort { $0.volumeName < $1.volumeName }
            }
            // Mount/unmount of an attached disk arrives as .changed, not
            // .appeared — surface the transition so it still gets logged.
            if !wasMounted, info.mountPoint != nil, !suppressingBaseline {
                onDiskEvent?(.appeared(info))
            } else if wasMounted, info.mountPoint == nil {
                onDiskEvent?(.unmounted(info))
            }
        case .unmounted:
            onDiskEvent?(event)
        }
    }
}
