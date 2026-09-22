import SwiftUI

struct PortManagerApp: App {
    @StateObject private var state = AppState()

    private func injectStores<Content: View>(into content: Content) -> some View {
        content
            .environmentObject(state)
            .environmentObject(state.ports)
            .environmentObject(state.devices)
            .environmentObject(state.presets)
            .environmentObject(state.activity)
            .environmentObject(state.monitor)
    }

    var body: some Scene {
        WindowGroup("PortManager", id: "main") {
            injectStores(into: MainWindow())
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("PortManager", systemImage: "network") {
            injectStores(into: MenuBarPopover())
        }
        .menuBarExtraStyle(.window)

        Settings {
            injectStores(into: SettingsView())
        }
    }
}
