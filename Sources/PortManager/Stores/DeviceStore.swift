import Foundation

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var usbNodes: [DeviceNode] = []
    @Published private(set) var thunderboltNodes: [DeviceNode] = []
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var isLoadingDevices = false
    @Published private(set) var lastUpdated: Date?

    /// Wired by MonitorEngine to log/notify on disk events.
    var onDiskEvent: ((DiskEvent) -> Void)?

    private let disks = DiskService()
    private var started = false
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
        Task { await refresh() }
        Task {
            try? await Task.sleep(for: .seconds(2))
            suppressingBaseline = false
        }
    }

    func refresh() async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        async let usb = Task.detached { try? USBProvider().usbTree() }.value
        async let tb = Task.detached { try? USBProvider().thunderboltTree() }.value
        usbNodes = await usb ?? []
        thunderboltNodes = await tb ?? []
        volumes = disks.externalVolumes()
        lastUpdated = .now
    }

    func unmount(_ volume: VolumeInfo, force: Bool) async -> Result<Void, DiskServiceError> {
        await withCheckedContinuation { cont in
            disks.unmount(bsdName: volume.bsdName, force: force) { result in
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

    func blockingProcesses(for volume: VolumeInfo) -> [(pid: pid_t, command: String)] {
        guard let mount = volume.mountPoint else { return [] }
        return (try? LsofProvider().processesUsing(path: mount)) ?? []
    }

    private func handle(_ event: DiskEvent) {
        switch event {
        case .appeared(let info):
            if !volumes.contains(info) {
                volumes.append(info)
                volumes.sort { $0.volumeName < $1.volumeName }
            }
            if !suppressingBaseline { onDiskEvent?(event) }
        case .disappeared(let bsd):
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
