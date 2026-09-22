import SwiftUI

/// Editor for a bandwidth threshold rule (port- or process-scoped).
struct AlertEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var alert: BandwidthAlert
    var onSave: (BandwidthAlert) -> Void

    /// Threshold edited in KB/s for human-friendly input.
    @State private var thresholdKB: Double = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bandwidth Alert").font(.headline)
            Form {
                TextField("Name", text: $alert.name, prompt: Text("my-api traffic"))
                Picker("Target", selection: targetKind) {
                    Text("Port").tag(0)
                    Text("Process").tag(1)
                }
                if alert.port != nil {
                    TextField("Port", value: Binding(
                        get: { alert.port ?? 0 },
                        set: { alert.port = $0 }),
                        format: .number.grouping(.never))
                } else {
                    TextField("Process name", text: Binding(
                        get: { alert.command ?? "" },
                        set: { alert.command = $0.isEmpty ? nil : $0 }),
                        prompt: Text("e.g. docker, node"))
                }
                LabeledContent("Threshold") {
                    HStack {
                        Slider(value: $thresholdKB, in: 10...100_000)
                            .frame(width: 160)
                        Text(verbatim: "\(ByteFormat.rate(thresholdKB * 1000))/s")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    alert.threshold = thresholdKB * 1000
                    onSave(alert)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(alert.name.isEmpty || (alert.port == nil && (alert.command ?? "").isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { thresholdKB = max(alert.threshold / 1000, 10) }
    }

    private var targetKind: Binding<Int> {
        Binding(
            get: { alert.port != nil ? 0 : 1 },
            set: { kind in
                if kind == 0 {
                    if alert.port == nil { alert.port = 8080 }
                    alert.command = nil
                } else {
                    alert.port = nil
                    if alert.command == nil { alert.command = "" }
                }
            })
    }
}
