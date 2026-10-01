import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject var devices: DeviceStore
    @State private var ejectTarget: VolumeInfo?

    var body: some View {
        List {
            Section {
                if devices.volumes.isEmpty {
                    Label("No external volumes mounted", systemImage: "externaldrive")
                        .foregroundStyle(.secondary)
                }
                ForEach(devices.volumes) { volume in
                    VolumeRow(volume: volume) {
                        ejectTarget = volume
                    }
                }
            } header: {
                Label("External Storage", systemImage: "externaldrive.fill")
            }

            Section {
                if devices.usbNodes.isEmpty {
                    Text(devices.isLoadingDevices ? "Scanning…" : "No USB devices")
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(devices.usbNodes, children: \.optionalChildren) { node in
                        DeviceRow(node: node)
                    }
                }
            } header: {
                Label("USB", systemImage: "cable.connector.horizontal")
            }

            Section {
                if devices.thunderboltNodes.isEmpty {
                    Text(devices.isLoadingDevices ? "Scanning…" : "No Thunderbolt devices")
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(devices.thunderboltNodes, children: \.optionalChildren) { node in
                        DeviceRow(node: node)
                    }
                }
            } header: {
                Label("Thunderbolt", systemImage: "bolt.horizontal")
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await devices.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan devices")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(verbatim: "\(devices.volumes.count) volumes · \(deviceCount) devices")
                Spacer()
                if let updated = devices.lastUpdated {
                    Text("Updated \(updated, format: .dateTime.hour().minute().second())")
                }
                if let error = devices.lastError { Text(error).foregroundStyle(.red) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .sheet(item: $ejectTarget) { volume in
            EjectSheet(volume: volume)
        }
        .task {
            await devices.refresh()
        }
    }

    private var deviceCount: Int {
        func count(_ nodes: [DeviceNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + count($1.children) }
        }
        return count(devices.usbNodes) + count(devices.thunderboltNodes)
    }
}

private struct DeviceRow: View {
    let node: DeviceNode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(node.name)
            }
            if !node.detail.isEmpty {
                Text(node.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch node.kind {
        case .bus: "cpu"
        case .hub: "point.3.connected.trianglepath.dotted"
        case .device: "cable.connector"
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo
    var onEject: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.volumeName).font(.headline)
                Text([
                    volume.mountPoint ?? "not mounted",
                    volume.fileSystem,
                    volume.capacityDescription,
                    volume.deviceProtocol
                ].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(volume.bsdName)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Button {
                onEject()
            } label: {
                Image(systemName: "eject.fill")
            }
            .buttonStyle(.borderless)
            .help("Safely eject \(volume.volumeName)")
        }
        .padding(.vertical, 4)
    }
}
