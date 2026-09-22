import SwiftUI

/// Inspector panel showing live detail for a selected port entry.
struct PortDetailView: View {
    let entry: PortEntry
    var onKill: (PortEntry) -> Void

    @State private var info: ProcessInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                processSection
                Divider()
                actions
            }
            .padding()
        }
        .task(id: entry.id) {
            info = await Task.detached {
                ProcessService().info(for: entry.pid)
            }.value
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(nsImage: IconCache.shared.icon(for: entry.pid))
                    .scaleEffect(1.5)
                Text(entry.command).font(.headline)
            }
            Text(entry.endpoint)
                .font(.system(.title3, design: .monospaced))
            if let remote = entry.remote {
                Text(verbatim: "→ \(remote)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: "\(entry.proto.rawValue)\(entry.state.isEmpty ? "" : " · \(entry.state)") · pid \(entry.pid) · \(entry.user)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Process").font(.subheadline.bold())
            if let info {
                LabeledContent("Path") {
                    Text(info.executablePath)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Started") {
                    Text(info.startTime?.formatted() ?? "—")
                        .font(.caption)
                }
                LabeledContent("CPU / Mem") {
                    Text("\(info.cpuPercent, format: .number.precision(.fractionLength(1)))% / \(info.memPercent, format: .number.precision(.fractionLength(1)))%")
                        .font(.caption)
                }
                LabeledContent("Open files") {
                    Text(verbatim: "\(info.openFileCount)").font(.caption)
                }
                LabeledContent("Children") {
                    Text(info.childPIDs.isEmpty
                         ? "none"
                         : info.childPIDs.map(String.init).joined(separator: ", "))
                        .font(.caption)
                }
                if !info.childPIDs.isEmpty {
                    Label("Terminating may also affect child processes",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(role: .destructive) {
                onKill(entry)
            } label: {
                Label("Terminate Process…", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            if entry.proto == .tcp {
                Button {
                    if let url = URL(string: "http://localhost:\(entry.port)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label {
                        Text(verbatim: "Open localhost:\(entry.port)")
                    } icon: {
                        Image(systemName: "safari")
                    }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "lsof -nP -i :\(entry.port)", forType: .string)
            } label: {
                Label("Copy lsof Command", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
    }
}
