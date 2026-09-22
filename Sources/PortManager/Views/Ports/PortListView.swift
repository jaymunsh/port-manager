import SwiftUI

struct PortListView: View {
    @EnvironmentObject var ports: PortStore
    @EnvironmentObject var presets: PresetStore
    @State private var search = ""
    @State private var selection: PortEntry.ID?
    @State private var localOnly = false
    @State private var showInspector = true
    @State private var killTarget: PortEntry?
    @State private var presetTarget: PortEntry?

    private var filtered: [PortEntry] {
        ports.entries.filter { entry in
            (!localOnly || entry.isLocalOnly) &&
            (search.isEmpty
                || entry.command.localizedCaseInsensitiveContains(search)
                || String(entry.port).contains(search)
                || entry.address.contains(search))
        }
    }

    private var selectedEntry: PortEntry? {
        guard let selection else { return nil }
        return ports.entries.first { $0.id == selection }
    }

    var body: some View {
        Table(filtered, selection: $selection) {
            TableColumn("Port") { entry in
                Text(entry.port, format: .number.grouping(.never))
                    .font(.body.monospacedDigit())
            }
            .width(min: 50, ideal: 64)

            TableColumn("Process") { entry in
                HStack(spacing: 6) {
                    Image(nsImage: IconCache.shared.icon(for: entry.pid))
                    Text(entry.command).lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("PID") { entry in
                Text(verbatim: "\(entry.pid)").foregroundStyle(.secondary)
            }
            .width(56)

            TableColumn("Bind", value: \.address)
                .width(min: 60, ideal: 96)

            TableColumn("Proto") { entry in
                Text(entry.proto.rawValue)
                    .foregroundStyle(.secondary)
            }
            .width(44)

            TableColumn("User", value: \.user)
                .width(min: 60, ideal: 90)

            TableColumn("Preset") { entry in
                if let preset = presets.preset(for: entry) {
                    Label(preset.name, systemImage: "bookmark.fill")
                        .foregroundStyle(presetColor(preset))
                        .lineLimit(1)
                }
            }
            .width(min: 60, ideal: 100)
        }
        .searchable(text: $search, prompt: "Port, process, or address")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await ports.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Refresh now (⌘R)")

                Toggle(isOn: $localOnly) {
                    Image(systemName: "house")
                }
                .toggleStyle(.button)
                .help("Show localhost bindings only")

                Toggle(isOn: Binding(
                    get: { ports.includeUDP },
                    set: { ports.includeUDP = $0 })) {
                    Text("UDP")
                }
                .toggleStyle(.button)
                .help("Include UDP sockets")

                Toggle(isOn: $showInspector) {
                    Image(systemName: "sidebar.trailing")
                }
                .toggleStyle(.button)
                .help("Toggle details inspector")
            }
        }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
        .inspector(isPresented: $showInspector) {
            if let entry = selectedEntry {
                PortDetailView(entry: entry, onKill: { killTarget = $0 })
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 340)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "network",
                    description: Text("Select a port to see details"))
            }
        }
        .contextMenu(forSelectionType: PortEntry.ID.self) { ids in
            if let id = ids.first,
               let entry = filtered.first(where: { $0.id == id }) {
                Button("Terminate Process…") { killTarget = entry }
                Button("Save as Preset…") { presetTarget = entry }
                if entry.proto == .tcp {
                    Button {
                        openInBrowser(entry)
                    } label: {
                        Text(verbatim: "Open http://localhost:\(entry.port)")
                    }
                }
                Divider()
                Button("Copy lsof Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "lsof -nP -i :\(entry.port)", forType: .string)
                }
            }
        }
        .sheet(item: $killTarget) { entry in
            KillSheet(entry: entry)
        }
        .sheet(item: $presetTarget) { entry in
            PresetEditorSheet(preset: preset(for: entry)) { preset in
                presets.add(preset)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(verbatim: "\(filtered.count) \(ports.includeUDP ? "sockets" : "listeners")")
            Spacer()
            if let updated = ports.lastUpdated {
                Text("Updated \(updated, format: .dateTime.hour().minute().second())")
            }
            if let error = ports.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func preset(for entry: PortEntry) -> PortPreset {
        PortPreset(
            name: entry.command,
            port: entry.port,
            proto: entry.proto.rawValue,
            expectedCommand: entry.command)
    }

    private func presetColor(_ preset: PortPreset) -> Color {
        switch presets.status(for: preset, entries: ports.entries) {
        case .expected: .blue
        case .conflict: .red
        case .free: .green
        }
    }

    private func openInBrowser(_ entry: PortEntry) {
        guard let url = URL(string: "http://localhost:\(entry.port)") else { return }
        NSWorkspace.shared.open(url)
    }
}
