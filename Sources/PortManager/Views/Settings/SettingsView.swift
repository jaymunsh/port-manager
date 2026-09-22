import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var ports: PortStore
    @EnvironmentObject var monitor: MonitorEngine
    @EnvironmentObject var activity: ActivityStore
    @AppStorage("menubar.enabled") private var menuBarEnabled = true

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Registration can fail for unsigned dev builds; ignore.
                }
            })
    }

    private var refreshInterval: Binding<Double> {
        Binding(
            get: { ports.refreshInterval },
            set: { ports.refreshInterval = $0 })
    }

    private var includeUDP: Binding<Bool> {
        Binding(
            get: { ports.includeUDP },
            set: { ports.includeUDP = $0 })
    }

    private func notifyBinding(_ keyPath: ReferenceWritableKeyPath<MonitorEngine, Bool>) -> Binding<Bool> {
        Binding(
            get: { monitor[keyPath: keyPath] },
            set: { monitor[keyPath: keyPath] = $0 })
    }

    var body: some View {
        Form {
            Section("Polling") {
                LabeledContent("Refresh interval") {
                    HStack {
                        Slider(value: refreshInterval, in: 1...10, step: 1)
                            .frame(width: 160)
                        Text(verbatim: "\(Int(ports.refreshInterval))s")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                Toggle("Include UDP sockets", isOn: includeUDP)
            }

            Section("Notifications") {
                Toggle("New listeners", isOn: notifyBinding(\.notifyNewListeners))
                Toggle("Preset conflicts", isOn: notifyBinding(\.notifyPresetConflicts))
                Toggle("Disk mount / eject", isOn: notifyBinding(\.notifyDiskEvents))
                Toggle("Bandwidth alerts", isOn: notifyBinding(\.notifyBandwidth))
            }

            Section("History") {
                LabeledContent("Keep activity for") {
                    Stepper(
                        value: Binding(
                            get: { activity.retentionDays },
                            set: { activity.retentionDays = $0 }),
                        in: 1...30) {
                        Text(verbatim: "\(activity.retentionDays) days")
                            .monospacedDigit()
                    }
                }
            }

            Section("General") {
                Toggle("Show in menu bar (applies after relaunch)", isOn: $menuBarEnabled)
                Toggle("Launch at login", isOn: launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
        .padding()
    }
}
