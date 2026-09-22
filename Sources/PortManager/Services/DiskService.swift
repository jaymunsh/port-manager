import DiskArbitration
import Foundation

enum DiskEvent: Sendable {
    case appeared(VolumeInfo)
    case disappeared(bsdName: String)
    case changed(VolumeInfo)
}

enum DiskServiceError: Error, Sendable {
    case sessionUnavailable
    case cannotCreateDiskRef(String)
    case operationFailed(String)
}

/// Thin wrapper over DiskArbitration: enumerates external volumes,
/// receives mount/unmount callbacks, performs unmount/eject.
final class DiskService: @unchecked Sendable {
    private var session: DASession?
    var onEvent: (@Sendable (DiskEvent) -> Void)?

    // MARK: - Session lifecycle

    func start() {
        guard session == nil, let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, diskAppeared, context)
        DARegisterDiskDisappearedCallback(session, nil, diskDisappeared, context)
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, diskChanged, context)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    // MARK: - Enumeration

    /// Mounted volumes that live on external/removable media.
    func externalVolumes() -> [VolumeInfo] {
        guard let session else { return [] }
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey,
            .volumeIsRemovableKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: []) ?? []
        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let internalFlag = values.volumeIsInternal ?? true
            let removable = (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false)
            guard !internalFlag || removable else { continue }
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
                  let info = volumeInfo(from: disk) else { continue }
            volumes.append(info)
        }
        return volumes.sorted { $0.volumeName < $1.volumeName }
    }

    // MARK: - Description extraction

    func volumeInfo(from disk: DADisk) -> VolumeInfo? {
        guard let raw = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        let bsd = raw[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? ""
        guard !bsd.isEmpty else { return nil }
        let volName = raw[kDADiskDescriptionVolumeNameKey as String] as? String ?? bsd
        let mount = (raw[kDADiskDescriptionVolumePathKey as String] as? URL)?.path
        let kind = raw[kDADiskDescriptionVolumeKindKey as String] as? String ?? ""
        let size = (raw[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.int64Value ?? 0
        let ejectable = (raw[kDADiskDescriptionMediaEjectableKey as String] as? NSNumber)?.boolValue ?? false
            || (raw[kDADiskDescriptionMediaRemovableKey as String] as? NSNumber)?.boolValue ?? false
        let proto = raw[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
        let internalFlag = (raw[kDADiskDescriptionDeviceInternalKey as String] as? NSNumber)?.boolValue ?? true
        // Keep only external/removable volumes.
        guard ejectable || !internalFlag else { return nil }
        var available: Int64 = 0
        if let mount, let values = try? URL(fileURLWithPath: mount)
            .resourceValues(forKeys: [.volumeAvailableCapacityKey]) {
            available = Int64(values.volumeAvailableCapacity ?? 0)
        }
        return VolumeInfo(
            bsdName: bsd, volumeName: volName, mountPoint: mount,
            fileSystem: kind, totalBytes: size, availableBytes: available,
            isEjectable: ejectable, deviceProtocol: proto
        )
    }

    // MARK: - Unmount / eject

    /// Unmounts a single volume. `force` detaches even when files are open.
    func unmount(bsdName: String, force: Bool,
                 completion: @escaping @Sendable (Result<Void, DiskServiceError>) -> Void) {
        guard let session else {
            completion(.failure(.sessionUnavailable)); return
        }
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            completion(.failure(.cannotCreateDiskRef(bsdName))); return
        }
        let box = CallbackBox(completion)
        let options: DADiskUnmountOptions = force
            ? DADiskUnmountOptions(kDADiskUnmountOptionForce)
            : DADiskUnmountOptions(kDADiskUnmountOptionDefault)
        DADiskUnmount(disk, options, unmountCompletion, Unmanaged.passRetained(box).toOpaque())
    }

    /// Ejects the whole physical device owning `bsdName` (all sibling volumes).
    func eject(bsdName: String,
               completion: @escaping @Sendable (Result<Void, DiskServiceError>) -> Void) {
        guard let session else {
            completion(.failure(.sessionUnavailable)); return
        }
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            completion(.failure(.cannotCreateDiskRef(bsdName))); return
        }
        let target = DADiskCopyWholeDisk(disk) ?? disk
        let box = CallbackBox(completion)
        DADiskEject(target, DADiskEjectOptions(kDADiskEjectOptionDefault), ejectCompletion, Unmanaged.passRetained(box).toOpaque())
    }

    // MARK: - Callback plumbing

    fileprivate final class CallbackBox {
        let run: @Sendable (Result<Void, DiskServiceError>) -> Void
        init(_ run: @escaping @Sendable (Result<Void, DiskServiceError>) -> Void) { self.run = run }
    }

    fileprivate func handleEvent(_ event: DiskEvent) {
        onEvent?(event)
    }
}

// MARK: - C callbacks (non-capturing, run on the scheduled run loop)

private let diskAppeared: DADiskAppearedCallback = { disk, context in
    guard let context else { return }
    let service = Unmanaged<DiskService>.fromOpaque(context).takeUnretainedValue()
    if let info = service.volumeInfo(from: disk) {
        service.handleEvent(.appeared(info))
    }
}

private let diskDisappeared: DADiskDisappearedCallback = { disk, context in
    guard let context else { return }
    let service = Unmanaged<DiskService>.fromOpaque(context).takeUnretainedValue()
    let bsd = DADiskGetBSDName(disk).map { String(cString: $0) } ?? "?"
    service.handleEvent(.disappeared(bsdName: bsd))
}

private let diskChanged: DADiskDescriptionChangedCallback = { disk, keys, context in
    guard let context else { return }
    let service = Unmanaged<DiskService>.fromOpaque(context).takeUnretainedValue()
    if let info = service.volumeInfo(from: disk) {
        service.handleEvent(.changed(info))
    }
}

private let unmountCompletion: DADiskUnmountCallback = { disk, dissenter, context in
    guard let context else { return }
    let box = Unmanaged<DiskService.CallbackBox>.fromOpaque(context).takeRetainedValue()
    if let dissenter {
        let status = DADissenterGetStatus(dissenter)
        let message = DADissenterGetStatusString(dissenter) as String? ?? "unmount failed"
        box.run(.failure(.operationFailed("\(message) (status \(status))")))
    } else {
        box.run(.success(()))
    }
}

private let ejectCompletion: DADiskEjectCallback = { disk, dissenter, context in
    guard let context else { return }
    let box = Unmanaged<DiskService.CallbackBox>.fromOpaque(context).takeRetainedValue()
    if let dissenter {
        let status = DADissenterGetStatus(dissenter)
        let message = DADissenterGetStatusString(dissenter) as String? ?? "eject failed"
        box.run(.failure(.operationFailed("\(message) (status \(status))")))
    } else {
        box.run(.success(()))
    }
}
