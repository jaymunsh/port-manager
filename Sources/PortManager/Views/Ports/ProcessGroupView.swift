import SwiftUI

/// Ports tab "process mode": sockets rolled up per process with expandable
/// rows. Simpler than the socket table when asking "who owns what".
struct ProcessGroupView: View {
    @EnvironmentObject var ports: PortStore
    @EnvironmentObject var presets: PresetStore

    let groups: [ProcessGroup]
    var onSelectEntry: (PortEntry) -> Void
    var onKill: (PortEntry) -> Void

    var body: some View {
        List(groups) { group in
            DisclosureGroup {
                ForEach(group.sockets) { entry in
                    socketRow(entry)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectEntry(entry) }
                        .contextMenu { socketMenu(entry) }
                }
            } label: {
                groupHeader(group)
                    .contentShape(Rectangle())
                    .contextMenu { groupMenu(group) }
            }
        }
    }

    private func groupHeader(_ group: ProcessGroup) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.shared.icon(for: group.pid))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.command).font(.headline)
                    Text(verbatim: "pid \(group.pid)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let container = dockerBadge(for: group) {
                        Text(container)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: .capsule)
                            .foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 8) {
                    if !group.listenPorts.isEmpty {
                        Text(verbatim: "ports \(group.listenPorts.map(String.init).joined(separator: ", "))")
                    }
                    if !group.connections.isEmpty {
                        Text(verbatim: "\(group.connections.count) conns")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let stat = ports.stats[group.pid] {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: String(format: "%.1f%% CPU", stat.cpu))
                    Text(verbatim: String(format: "%.1f%% MEM", stat.mem))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if let rate = ports.netRates[group.pid], rate.total > 0 {
                Text(verbatim: "↓\(ByteFormat.rate(rate.inRate)) ↑\(ByteFormat.rate(rate.outRate))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func socketRow(_ entry: PortEntry) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(entry.isListener ? Color.blue : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(entry.port, format: .number.grouping(.never))
                .font(.body.monospacedDigit())
            Text(entry.address)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.proto.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let remote = entry.remote {
                Text(verbatim: "→ \(remote)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !entry.isListener {
                Text(entry.state)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let preset = presets.preset(for: entry) {
                Label(preset.name, systemImage: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            let rate = entry.isListener ? nil : ports.connRates[entry.connKey]
            if let rate, rate.total > 0 {
                Text(verbatim: "↓\(ByteFormat.rate(rate.inRate)) ↑\(ByteFormat.rate(rate.outRate))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func groupMenu(_ group: ProcessGroup) -> some View {
        if let listener = group.listeners.first {
            Button("Terminate Process…") { onKill(listener) }
        }
        Button("Copy PID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(group.pid), forType: .string)
        }
    }

    @ViewBuilder
    private func socketMenu(_ entry: PortEntry) -> some View {
        Button("Terminate Process…") { onKill(entry) }
        Button("Copy Port") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(entry.port), forType: .string)
        }
        if let remote = entry.remote {
            Button("Copy Remote Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(remote, forType: .string)
            }
        }
    }

    private func dockerBadge(for group: ProcessGroup) -> String? {
        guard group.command.localizedCaseInsensitiveContains("docker") else { return nil }
        for port in group.listenPorts {
            if let c = ports.container(forPort: port) {
                return "🐳 \(c.image)"
            }
        }
        return nil
    }
}
