import Foundation

@MainActor
final class AppState: ObservableObject {
    /// Currently selected sidebar section — settable from the menu bar
    /// popover so it can deep-link into e.g. Settings.
    @Published var section: MainWindow.SidebarSection = .ports

    let ports = PortStore()
    let devices = DeviceStore()
    let presets = PresetStore()
    let alerts = AlertStore()
    let activity = ActivityStore()
    let monitor = MonitorEngine()
    let network = NetworkStore()

    private var started = false

    func start() {
        guard !started else { return }
        started = true

        monitor.start(ports: ports, devices: devices, presets: presets,
                      activity: activity, alerts: alerts)
        ports.startPolling()
        devices.start()
        network.startPolling()
    }

    func stop() {
        ports.stopPolling()
        devices.stop()
        network.stopPolling()
    }
}
