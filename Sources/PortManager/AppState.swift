import Foundation

@MainActor
final class AppState: ObservableObject {
    let ports = PortStore()
    let devices = DeviceStore()
    let presets = PresetStore()
    let activity = ActivityStore()
    let monitor = MonitorEngine()
    let network = NetworkStore()

    private var started = false

    func start() {
        guard !started else { return }
        started = true

        ports.startPolling()
        devices.start()
        network.startPolling()
        monitor.start(ports: ports, devices: devices, presets: presets, activity: activity)
    }
}
