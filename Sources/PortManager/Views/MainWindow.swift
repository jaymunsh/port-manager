import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var state: AppState

    enum SidebarSection: String, CaseIterable, Identifiable {
        case ports, network, devices, presets, activity, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ports: "Ports"
            case .network: "Network"
            case .devices: "Devices"
            case .presets: "Presets"
            case .activity: "Activity"
            case .settings: "Settings"
            }
        }

        var icon: String {
            switch self {
            case .ports: "network"
            case .network: "wifi"
            case .devices: "externaldrive.connected.to.line.below"
            case .presets: "bookmark"
            case .activity: "list.bullet.rectangle"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $state.section) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch state.section {
            case .ports: PortListView()
            case .network: NetworkView()
            case .devices: DeviceListView()
            case .presets: PresetListView()
            case .activity: ActivityLogView()
            case .settings: SettingsView()
            }
        }
        .onAppear { state.start() }
    }
}
