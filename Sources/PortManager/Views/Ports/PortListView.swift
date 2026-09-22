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
    @State private var sortOrder: [RowComparator] = [RowComparator(key: .port)]

    private var filtered: [PortEntry] {
        ports.entries
            .filter { entry in
                (!localOnly || entry.isLocalOnly) &&
                (search.isEmpty
                    || entry.command.localizedCaseInsensitiveContains(search)
                    || String(entry.port).contains(search)
                    || entry.address.contains(search))
            }
            .sorted(using: sortOrder)
    }

    private var selectedEntry: PortEntry? {
        guard let selection else { return nil }
        return ports.entries.first { $0.id == selection }
    }

    var body: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Port", sortUsing: RowComparator(key: .port)) { entry in
                Text(entry.port, format: .number.grouping(.never))
                    .font(.body.monospacedDigit())
            }
            .width(min: 50, ideal: 64)

            TableColumn("Process", sortUsing: RowComparator(key: .command)) { entry in
                HStack(spacing: 6) {
                    Image(nsImage: IconCache.shared.icon(for: entry.pid))
                    Text(entry.command).lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("PID", sortUsing: RowComparator(key: .pid)) { entry in
                Text(verbatim: "\(entry.pid)").foregroundStyle(.secondary)
            }
            .width(56)

            TableColumn("Bind", sortUsing: RowComparator(key: .address)) { entry in
                Text(entry.address)
            }
            .width(min: 60, ideal: 96)

            TableColumn("Proto", sortUsing: RowComparator(key: .proto)) { entry in
                Text(entry.proto.rawValue)
                    .foregroundStyle(.secondary)
            }
            .width(44)

            TableColumn("CPU", sortUsing: RowComparator(key: .cpu, stats: ports.stats)) { entry in
                statText(ports.stats[entry.pid]?.cpu)
            }
            .width(52)

            TableColumn("Mem", sortUsing: RowComparator(key: .mem, stats: ports.stats)) { entry in
                statText(ports.stats[entry.pid]?.mem)
            }
            .width(52)

            TableColumn("User", sortUsing: RowComparator(key: .user)) { entry in
                Text(entry.user)
            }
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

    private func statText(_ value: Double?) -> some View {
        Text(verbatim: value.map { String(format: "%.1f", $0) } ?? "–")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
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

/// One comparator type for every sortable column — Table requires a single
/// concrete element type in its sort order, so cpu/mem (looked up from
/// PortStore.stats) and key path fields share this struct.
private struct RowComparator: SortComparator, Hashable {
    typealias Compared = PortEntry
    enum Key { case port, command, pid, address, proto, user, cpu, mem }
    var order: SortOrder = .forward
    var key: Key
    var stats: [pid_t: ProcStat] = [:]

    func compare(_ lhs: PortEntry, _ rhs: PortEntry) -> ComparisonResult {
        let cmp: ComparisonResult = switch key {
        case .port: Self.cmp(lhs.port, rhs.port)
        case .command: Self.cmp(lhs.command, rhs.command)
        case .pid: Self.cmp(lhs.pid, rhs.pid)
        case .address: Self.cmp(lhs.address, rhs.address)
        case .proto: Self.cmp(lhs.proto.rawValue, rhs.proto.rawValue)
        case .user: Self.cmp(lhs.user, rhs.user)
        case .cpu: Self.cmp(stat(lhs, \.cpu), stat(rhs, \.cpu))
        case .mem: Self.cmp(stat(lhs, \.mem), stat(rhs, \.mem))
        }
        guard order == .reverse else { return cmp }
        return switch cmp {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        default: .orderedSame
        }
    }

    private func stat(_ entry: PortEntry, _ field: KeyPath<ProcStat, Double>) -> Double {
        stats[entry.pid].map { $0[keyPath: field] } ?? -.infinity
    }

    private static func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a == b ? .orderedSame : a < b ? .orderedAscending : .orderedDescending
    }
}
