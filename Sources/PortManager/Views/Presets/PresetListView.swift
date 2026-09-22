import SwiftUI

struct PresetListView: View {
    @EnvironmentObject var presets: PresetStore
    @EnvironmentObject var ports: PortStore
    @State private var editing: PortPreset?
    @State private var isAdding = false

    var body: some View {
        List {
            if presets.presets.isEmpty {
                ContentUnavailableView(
                    "No Presets",
                    systemImage: "bookmark",
                    description: Text("Save the ports your projects use to spot conflicts at a glance."))
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
        .sheet(isPresented: $isAdding) {
            PresetEditorSheet(preset: PortPreset(name: "", port: 3000)) {
                presets.add($0)
            }
        }
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
