import SwiftUI

/// Network interfaces, addressing, and live throughput.
struct NetworkView: View {
    @EnvironmentObject var network: NetworkStore

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Gateway") {
                    Text(network.gateway ?? "—").font(.callout.monospaced())
                }
                LabeledContent("DNS") {
                    Text(network.dns.isEmpty ? "—" : network.dns.joined(separator: ", "))
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section("Interfaces") {
                if network.interfaces.isEmpty {
                    Text("No active interfaces")
                        .foregroundStyle(.tertiary)
                }
                ForEach(network.interfaces) { iface in
                    InterfaceRow(iface: iface)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await network.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now")
            }
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
    }

    private var statusBar: some View {
        HStack {
            Text(verbatim: "\(network.interfaces.count) interfaces")
            Spacer()
            Text(verbatim: "↓\(ByteFormat.rate(network.totalInRate))/s  ↑\(ByteFormat.rate(network.totalOutRate))/s")
            if let updated = network.lastUpdated {
                Text("Updated \(updated, format: .dateTime.hour().minute().second())")
            }
            if let error = network.lastError { Text(error).foregroundStyle(.red) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct InterfaceRow: View {
    let iface: NetInterface

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iface.isActive ? Color.accentColor : .secondary)
                    .frame(width: 20)
                Text(iface.displayName).font(.headline)
                Text(verbatim: iface.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "↓\(ByteFormat.rate(iface.inRate))/s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(verbatim: "↑\(ByteFormat.rate(iface.outRate))/s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(iface.isActive ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 16) {
                if let v4 = iface.ipv4 {
                    LabeledMini("IPv4", v4)
                }
                if let v6 = iface.ipv6 {
                    LabeledMini("IPv6", v6)
                }
                if let mac = iface.mac {
                    LabeledMini("MAC", mac)
                }
                if let wifi = iface.wifi {
                    LabeledMini("SSID", wifi.ssid ?? "hidden")
                    LabeledMini("Signal", "\(wifi.rssi) dBm (\(wifi.signalDescription))")
                    LabeledMini("Ch", "\(wifi.channel)")
                    LabeledMini("Tx", "\(Int(wifi.txRateMbps)) Mbps")
                }
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        if iface.wifi != nil { return "wifi" }
        switch iface.displayName {
        case "VPN": return "lock.shield"
        case "Bridge": return "point.3.connected.trianglepath.dotted"
        default: return "cable.connector"
        }
    }
}

private struct LabeledMini: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(verbatim: value).font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}
