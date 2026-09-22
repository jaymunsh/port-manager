import SwiftUI

struct ActivityLogView: View {
    @EnvironmentObject var activity: ActivityStore

    var body: some View {
        List(activity.events) { event in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: event.kind))
                    .foregroundStyle(color(for: event.kind))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message)
                    Text(event.date, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if activity.events.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Port and device events will appear here."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    activity.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear log")
                .disabled(activity.events.isEmpty)
            }
        }
    }

    private func icon(for kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .listener: "network"
        case .preset: "bookmark.fill"
        case .disk: "externaldrive.fill"
        case .device: "cable.connector"
        case .process: "xmark.circle"
        case .bandwidth: "speedometer"
        }
    }

    private func color(for kind: ActivityEvent.Kind) -> Color {
        switch kind {
        case .listener: .blue
        case .preset: .orange
        case .disk: .purple
        case .device: .teal
        case .process: .red
        case .bandwidth: .pink
        }
    }
}
