import SwiftUI

/// Status-bar label: globe icon plus live total throughput.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var network: NetworkStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
            Text(verbatim: "↓\(ByteFormat.rate(network.totalInRate))")
                .font(.caption.monospacedDigit())
        }
        .onAppear { state.start() }
    }
}
