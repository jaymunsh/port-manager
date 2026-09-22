import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var state: AppState
    @State private var section: SidebarSection = .ports

    enum SidebarSection: String, CaseIterable, Identifiable {
        case ports, devices, presets, activity

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ports: "Ports"
            case .devices: "Devices"
            case .presets: "Presets"
            case .activity: "Activity"
            }
        }

        var icon: String {
            switch self {
            case .ports: "network"
            case .devices: "externaldrive.connected.to.line.below"
            case .presets: "bookmark"
            case .activity: "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch section {
            case .ports: PortListView()
            case .devices: DeviceListView()
            case .presets: PresetListView()
            case .activity: ActivityLogView()
            }
        }
        .onAppear { state.start() }
    }
}
