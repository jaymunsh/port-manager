import SwiftUI

/// Status-bar label: globe icon plus live listener count.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var ports: PortStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
            Text(verbatim: "\(ports.entries.filter(\.isListener).count)")
                .font(.caption.monospacedDigit())
        }
        .onAppear { state.start() }
    }
}
