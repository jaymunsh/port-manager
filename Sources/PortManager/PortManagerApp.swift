import SwiftUI

struct PortManagerApp: App {
    @StateObject private var state = AppState()
    /// Read once at launch — `isInserted` with a live binding triggers a
    /// SwiftUI KVO feedback loop (MenuBarExtraController spins at 100% CPU),
    /// so the toggle applies on next launch.
    private let menuBarEnabled = UserDefaults.standard.object(forKey: "menubar.enabled") as? Bool ?? true

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

        MenuBarExtra(isInserted: .constant(menuBarEnabled)) {
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
