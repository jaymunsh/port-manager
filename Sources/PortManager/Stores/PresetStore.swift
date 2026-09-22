import Foundation

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [PortPreset] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortManager", isDirectory: true)
        return dir.appendingPathComponent("presets.json")
    }()

    init() {
        load()
    }

    func status(for preset: PortPreset, entries: [PortEntry]) -> PresetStatus {
        let matching = entries.filter {
            $0.port == preset.port && $0.proto.rawValue == preset.proto
        }
        guard !matching.isEmpty else { return .free }
        guard let expected = preset.expectedCommand, !expected.isEmpty else {
            return .expected
        }
        return matching.contains {
            $0.command.localizedCaseInsensitiveContains(expected)
        } ? .expected : .conflict
    }

    func add(_ preset: PortPreset) {
        presets.append(preset)
        save()
    }

    func update(_ preset: PortPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        save()
    }

    func remove(_ preset: PortPreset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    func preset(for entry: PortEntry) -> PortPreset? {
        presets.first { $0.port == entry.port && $0.proto == entry.proto.rawValue }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PortPreset].self, from: data)
        else { return }
        presets = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(presets)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence failure is non-fatal for a dev tool; keep going.
        }
    }
}
