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
            .environmentObject(state.network)
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

        MenuBarExtra {
            injectStores(into: MenuBarPopover())
        } label: {
            injectStores(into: MenuBarLabel())
        }
        .menuBarExtraStyle(.window)

        Settings {
            injectStores(into: SettingsView())
        }
    }
}
