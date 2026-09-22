import Foundation

struct DeviceNode: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case bus
        case hub
        case device
    }

    let id = UUID()
    var name: String
    var detail: String
    var kind: Kind
    var children: [DeviceNode]

    /// OutlineGroup requires an optional children key path.
    var optionalChildren: [DeviceNode]? { children.isEmpty ? nil : children }
}

struct VolumeInfo: Identifiable, Hashable, Sendable {
    var id: String { bsdName }
    let bsdName: String
    let volumeName: String
    let mountPoint: String?
    let fileSystem: String
    let totalBytes: Int64
    let availableBytes: Int64
    let isEjectable: Bool
    let deviceProtocol: String

    var capacityDescription: String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .binary
        return "\(fmt.string(fromByteCount: availableBytes)) free of \(fmt.string(fromByteCount: totalBytes))"
    }
}
