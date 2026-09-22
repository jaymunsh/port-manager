import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var ports: PortStore
    @EnvironmentObject var presets: PresetStore
    @EnvironmentObject var devices: DeviceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var killTarget: PortEntry?

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    presetsSection
                    volumesSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 340, height: 420)
        .onAppear { state.start() }
        .sheet(item: $killTarget) { entry in
            KillSheet(entry: entry)
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
                MenuBarEjectButton(volume: volume)
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
                openSettings()
            } label: {
                Image(systemName: "gear")
            }
            .controlSize(.small)

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

private struct MenuBarEjectButton: View {
    let volume: VolumeInfo
    @EnvironmentObject var devices: DeviceStore
    @State private var working = false

    var body: some View {
        Button {
            working = true
            Task {
                _ = await devices.unmount(volume, force: false)
                _ = await devices.eject(volume)
                working = false
            }
        } label: {
            if working {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "eject.fill")
            }
        }
        .buttonStyle(.borderless)
        .disabled(working)
        .help("Eject \(volume.volumeName)")
    }
}
