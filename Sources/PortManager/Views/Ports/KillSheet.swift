import SwiftUI

/// Safe-kill flow: confirm → SIGTERM → wait → offer SIGKILL.
struct KillSheet: View {
    let entry: PortEntry

    @EnvironmentObject var ports: PortStore
    @EnvironmentObject var activity: ActivityStore
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .confirm
    @State private var info: ProcessInfo?
    @State private var errorMessage: String?
    @State private var identity: ProcessIdentity?

    private let service = ProcessService()

    enum Phase {
        case confirm, working, needsForce, done, blocked, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title
            Divider()
            content
            Divider()
            buttons
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(phase == .working)
        .task {
            guard let selected = entry.processIdentity else {
                errorMessage = KillError.identityUnavailable.description
                phase = .failed
                return
            }
            info = try? await Background.run { ProcessService().info(for: entry.pid) }
            guard !Task.isCancelled else { return }
            guard ProcessService.identityMatches(expected: selected, current: service.identity(for: entry.pid)) else {
                errorMessage = KillError.identityChanged.description
                phase = .failed
                return
            }
            identity = selected
        }
    }

    private var title: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.shared.icon(for: entry.pid))
                .scaleEffect(1.8)
                .frame(width: 32)
            VStack(alignment: .leading) {
                Text("Terminate \(entry.command)").font(.headline)
                Text(verbatim: "pid \(entry.pid) · listening on \(entry.endpoint)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .confirm:
            VStack(alignment: .leading, spacing: 8) {
                if let info {
                    row("Path", info.executablePath.isEmpty ? "—" : info.executablePath)
                    row("Started", info.startTime?.formatted() ?? "—")
                    row("Child processes",
                        info.childPIDs.isEmpty ? "none" : "\(info.childPIDs.count)")
                    if !info.childPIDs.isEmpty {
                        Label("This process has children that may also be affected.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
                if service.isProtected(pid: entry.pid, command: entry.command) {
                    Label("This is a protected system process.",
                          systemImage: "lock.shield.fill")
                        .foregroundStyle(.red).font(.callout)
                }
                Text("A polite SIGTERM is sent first. Force kill (SIGKILL) is only used if it ignores the request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .working:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for \(entry.command) to exit…")
            }
        case .needsForce:
            Label("The process ignored SIGTERM. You can force kill it (SIGKILL) — unsaved state may be lost.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .done:
            Label("Process terminated.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .blocked:
            VStack(alignment: .leading, spacing: 8) {
                Label(errorMessage ?? "", systemImage: "lock.fill")
                    .foregroundStyle(.red)
                Text("You can terminate it manually with:")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(verbatim: "sudo kill \(entry.pid)")
                        .font(.caption.monospaced())
                        .padding(6)
                        .background(.quaternary, in: .rect(cornerRadius: 6))
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("sudo kill \(entry.pid)", forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        case .failed:
            Label(errorMessage ?? "Unknown error", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Spacer()
            switch phase {
            case .confirm:
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Terminate", role: .destructive) {
                    Task { await terminate(force: false) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(identity == nil || service.isProtected(pid: entry.pid, command: entry.command))
            case .working:
                ProgressView().controlSize(.small)
            case .needsForce:
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Force Kill", role: .destructive) {
                    Task { await terminate(force: true) }
                }
            case .done, .blocked, .failed:
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).font(.caption.monospaced())
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }
    }

    private func terminate(force: Bool) async {
        guard phase != .working else { return }
        guard let identity else {
            errorMessage = KillError.identityUnavailable.description
            phase = .failed
            return
        }
        phase = .working
        if let error = service.sendSignal(force ? SIGKILL : SIGTERM, to: identity) {
            switch error {
            case .notPermitted:
                errorMessage = error.description
                phase = .blocked
            case .noSuchProcess:
                phase = .done
            case .failed, .protectedProcess, .identityChanged, .identityUnavailable:
                errorMessage = error.description
                phase = .failed
            }
            return
        }
        // Poll until the process exits (up to ~5s).
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            if !service.isAlive(identity) {
                phase = .done
                activity.log(.process, "Terminated \(entry.command) (pid \(entry.pid))")
                await ports.refresh()
                return
            }
        }
        phase = force ? .failed : .needsForce
        if force { errorMessage = "Process survived SIGKILL" }
    }
}
