import SwiftUI

struct PresetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var preset: PortPreset
    var onSave: (PortPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Port Preset").font(.headline)
            Form {
                TextField("Name", text: $preset.name, prompt: Text("my-api"))
                TextField("Port", value: $preset.port, format: .number.grouping(.never))
                Picker("Protocol", selection: $preset.proto) {
                    Text("TCP").tag("TCP")
                    Text("UDP").tag("UDP")
                }
                TextField("Expected process", text: Binding(
                    get: { preset.expectedCommand ?? "" },
                    set: { preset.expectedCommand = $0.isEmpty ? nil : $0 }),
                    prompt: Text("e.g. node, python (optional)"))
                TextField("Note", text: $preset.note)
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(preset)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preset.name.isEmpty || !(1...65535).contains(preset.port))
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
