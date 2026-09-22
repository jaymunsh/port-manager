import SwiftUI

struct PresetListView: View {
    @EnvironmentObject var presets: PresetStore
    @EnvironmentObject var ports: PortStore
    @EnvironmentObject var alerts: AlertStore
    @State private var editing: PortPreset?
    @State private var editingAlert: BandwidthAlert?
    @State private var isAdding = false

    var body: some View {
        List {
            Section("Port Presets") {
                if presets.presets.isEmpty {
                    Text("No presets — save a port via right-click in the Ports table.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(presets.presets) { preset in
                    PresetRow(preset: preset,
                              status: presets.status(for: preset, entries: ports.entries))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = preset }
                        .contextMenu {
                            Button("Edit…") { editing = preset }
                            Divider()
                            Button("Delete", role: .destructive) { presets.remove(preset) }
                        }
                }
            }
            Section("Bandwidth Alerts") {
                if alerts.alerts.isEmpty {
                    Text("No alerts — right-click a row in Ports → Bandwidth Alert…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(alerts.alerts) { alert in
                    AlertRow(alert: alert,
                             rate: alerts.currentRate(
                                for: alert, entries: ports.entries,
                                netRates: ports.netRates, connRates: ports.connRates))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editingAlert = alert }
                        .contextMenu {
                            Button("Edit…") { editingAlert = alert }
                            Button(alert.enabled ? "Disable" : "Enable") {
                                var a = alert
                                a.enabled.toggle()
                                alerts.update(a)
                            }
                            Divider()
                            Button("Delete", role: .destructive) { alerts.remove(alert) }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add preset")
            }
        }
        .sheet(item: $editing) { preset in
            PresetEditorSheet(preset: preset) { presets.update($0) }
        }
        .sheet(item: $editingAlert) { alert in
            AlertEditorSheet(alert: alert) { alerts.update($0) }
        }
        .sheet(isPresented: $isAdding) {
            PresetEditorSheet(preset: PortPreset(name: "", port: 3000)) {
                presets.add($0)
            }
        }
    }
}

private struct AlertRow: View {
    let alert: BandwidthAlert
    let rate: Double

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(rate > alert.threshold ? Color.red : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(alert.name.isEmpty ? "Untitled" : alert.name).font(.headline)
                    if let port = alert.port {
                        Text(verbatim: ":\(port)")
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    } else if let command = alert.command {
                        Text(command)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if !alert.enabled {
                        Text("disabled")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(verbatim: "now ↓↑\(ByteFormat.rate(rate))/s")
                    Text(verbatim: "alert over \(ByteFormat.rate(alert.threshold))/s")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PresetRow: View {
    let preset: PortPreset
    let status: PresetStatus

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(preset.name.isEmpty ? "Untitled" : preset.name).font(.headline)
                    Text(verbatim: ":\(preset.port)")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text(preset.proto)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
                HStack(spacing: 8) {
                    Text(statusLabel).foregroundStyle(statusColor)
                    if let expected = preset.expectedCommand, !expected.isEmpty {
                        Text("expects \(expected)").foregroundStyle(.tertiary)
                    }
                    if !preset.note.isEmpty {
                        Text(preset.note).foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .free: .green
        case .expected: .blue
        case .conflict: .red
        }
    }

    private var statusLabel: String {
        switch status {
        case .free: "free"
        case .expected: "running"
        case .conflict: "conflict"
        }
    }
}
