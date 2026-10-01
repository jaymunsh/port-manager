import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var ports: PortStore
    @EnvironmentObject var presets: PresetStore
    @EnvironmentObject var devices: DeviceStore
    @Environment(\.openWindow) private var openWindow
    @State private var killTarget: PortEntry?
    @State private var ejectTarget: VolumeInfo?

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    presetsSection
                    listenersSection
                    volumesSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 480)
        .onAppear { state.start() }
        .sheet(item: $killTarget) { entry in
            KillSheet(entry: entry)
        }
        .sheet(item: $ejectTarget) { volume in
            EjectSheet(volume: volume)
        }
    }

    // MARK: - Sections

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            stat("\(ports.entries.filter(\.isListener).count)", "listeners", "network")
            stat("\(conflictCount)", "conflicts", "exclamationmark.triangle")
            stat("\(devices.volumes.count)", "disks", "externaldrive")
        }
        .padding(12)
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(value).font(.headline.monospacedDigit())
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var presetsSection: some View {
        Text("Presets").font(.caption.bold()).foregroundStyle(.secondary)
        if presets.presets.isEmpty {
            Text("No presets — add one from the Ports tab")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        ForEach(presets.presets) { preset in
            let status = presets.status(for: preset, entries: ports.entries)
            HStack {
                Circle().fill(color(for: status)).frame(width: 8, height: 8)
                Text(preset.name).lineLimit(1)
                Text(verbatim: ":\(preset.port)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if status == .conflict,
                   let entry = ports.entries.first(where: { $0.port == preset.port }) {
                    Button("Kill…") { killTarget = entry }
                        .controlSize(.mini)
                }
            }
            .font(.callout)
        }
    }

    /// Top listeners by current CPU — a glanceable "what's busiest" list.
    @ViewBuilder
    private var listenersSection: some View {
        let top = ports.entries.filter(\.isListener)
            .sorted { (ports.stats[$0.pid]?.cpu ?? 0) > (ports.stats[$1.pid]?.cpu ?? 0) }
        Text("Listeners").font(.caption.bold()).foregroundStyle(.secondary)
        if top.isEmpty {
            Text("No listeners").font(.caption).foregroundStyle(.tertiary)
        }
        ForEach(top.prefix(10)) { entry in
            HStack(spacing: 6) {
                Image(nsImage: IconCache.shared.icon(for: entry.pid))
                    .resizable().frame(width: 14, height: 14)
                Text(verbatim: ":\(entry.port)")
                    .font(.caption.monospacedDigit().bold())
                Text(entry.command).lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                if let stat = ports.stats[entry.pid], stat.cpu > 0 {
                    Text(verbatim: String(format: "%.0f%%", stat.cpu))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
        }
        if top.count > 10 {
            Text("… \(top.count - 10) more")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var volumesSection: some View {
        Text("External Disks").font(.caption.bold()).foregroundStyle(.secondary)
        if devices.volumes.isEmpty {
            Text("None mounted").font(.caption).foregroundStyle(.tertiary)
        }
        ForEach(devices.volumes) { volume in
            HStack {
                Image(systemName: "externaldrive.fill").foregroundStyle(.secondary)
                Text(volume.volumeName).lineLimit(1)
                Spacer()
                Button { ejectTarget = volume } label: {
                    Image(systemName: "eject.fill")
                }
                .buttonStyle(.borderless)
                .help("Safely eject \(volume.volumeName)")
                .accessibilityLabel("Safely eject \(volume.volumeName)")
            }
            .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open", systemImage: "macwindow")
            }
            .controlSize(.small)

            Button {
                // Deep-link into the main window's Settings tab — more
                // reliable than openSettings() from a MenuBarExtra.
                state.section = .settings
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gear")
            }
            .controlSize(.small)
            .help("Settings")

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .controlSize(.small)
        }
        .padding(10)
    }

    private var conflictCount: Int {
        presets.presets.filter {
            presets.status(for: $0, entries: ports.entries) == .conflict
        }.count
    }

    private func color(for status: PresetStatus) -> Color {
        switch status {
        case .free: .green
        case .expected: .blue
        case .conflict: .red
        }
    }
}
