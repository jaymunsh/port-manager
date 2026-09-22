import SwiftUI

/// Safe eject flow: confirm → unmount + eject → on failure show blocking
/// processes and offer a forced retry.
struct EjectSheet: View {
    let volume: VolumeInfo

    @EnvironmentObject var devices: DeviceStore
    @EnvironmentObject var activity: ActivityStore
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .confirm
    @State private var blockers: [(pid: pid_t, command: String)] = []
    @State private var errorMessage: String?

    enum Phase {
        case confirm, working, blocked, done, failed
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
        .frame(minHeight: 160)
    }

    private var title: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill")
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading) {
                Text("Eject \(volume.volumeName)").font(.headline)
                Text("\(volume.bsdName) · \(volume.mountPoint ?? "not mounted") · \(volume.capacityDescription)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .confirm:
            Text("The volume will be unmounted and the device ejected. If files are in use, you will see which processes are holding them.")
                .foregroundStyle(.secondary)
        case .working:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Unmounting \(volume.volumeName)…")
            }
        case .blocked:
            VStack(alignment: .leading, spacing: 8) {
                Label("The volume is in use by these processes:",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                ForEach(blockers, id: \.pid) { blocker in
                    HStack {
                        Image(nsImage: IconCache.shared.icon(for: blocker.pid))
                        Text(blocker.command)
                        Text(verbatim: "pid \(blocker.pid)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Quit them and retry, or force eject (may lose unsaved data).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .done:
            Label("\(volume.volumeName) was safely ejected.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label(errorMessage ?? "Eject failed", systemImage: "xmark.octagon.fill")
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
                Button("Eject") { Task { await eject(force: false) } }
                    .keyboardShortcut(.defaultAction)
            case .working:
                ProgressView().controlSize(.small)
            case .blocked:
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Force Eject", role: .destructive) { Task { await eject(force: true) } }
            case .done, .failed:
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func eject(force: Bool) async {
        phase = .working
        // 1. Unmount the volume.
        let unmountResult = await devices.unmount(volume, force: force)
        if case .failure(let error) = unmountResult, !force {
            blockers = devices.blockingProcesses(for: volume)
            if blockers.isEmpty {
                errorMessage = describe(error)
                phase = .failed
            } else {
                phase = .blocked
            }
            return
        }
        // 2. Eject the whole device.
        let ejectResult = await devices.eject(volume)
        switch ejectResult {
        case .success:
            phase = .done
            activity.log(.disk, "Ejected \(volume.volumeName)")
        case .failure(let error):
            if force {
                errorMessage = describe(error)
                phase = .failed
            } else {
                blockers = devices.blockingProcesses(for: volume)
                if blockers.isEmpty {
                    // Volume already unmounted; surface the eject error.
                    errorMessage = describe(error)
                    phase = .failed
                } else {
                    phase = .blocked
                }
            }
        }
    }

    private func describe(_ error: DiskServiceError) -> String {
        switch error {
        case .sessionUnavailable: "Disk service unavailable"
        case .cannotCreateDiskRef(let bsd): "Cannot reference \(bsd)"
        case .operationFailed(let message): message
        }
    }
}
