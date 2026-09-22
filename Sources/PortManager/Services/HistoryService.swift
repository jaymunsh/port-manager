import Foundation

/// Persists activity events as JSONL — one file per day under
/// `~/Library/Application Support/PortManager/history/`.
/// Size stays tiny: one event is ~100 bytes.
struct HistoryService: Sendable {
    let directory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortManager/history", isDirectory: true)
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func fileURL(for date: Date) -> URL {
        directory.appendingPathComponent("history-\(Self.dayFormatter.string(from: date)).jsonl")
    }

    /// Appends one JSON line. Called from the main actor but writes are
    /// ~100 bytes so synchronous IO is fine.
    func append(_ event: ActivityEvent) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let line = try encoder.encode(event)
            let url = fileURL(for: event.date)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: line + Data("\n".utf8))
                try handle.close()
            } else {
                try (line + Data("\n".utf8)).write(to: url)
            }
        } catch {
            // History persistence is best-effort.
        }
    }

    /// Loads events from the most recent `days` files (newest first).
    func loadRecent(days: Int) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for offset in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let url = fileURL(for: date)
            guard let data = try? Data(contentsOf: url) else { continue }
            for line in data.split(separator: 0x0A) {
                if let event = try? decoder.decode(ActivityEvent.self, from: line) {
                    events.append(event)
                }
            }
            if !events.isEmpty { break } // stop at the newest non-empty day
        }
        return events.sorted { $0.date > $1.date }
    }

    /// Deletes history files older than `days`.
    func prune(olderThan days: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        for url in files where url.pathExtension == "jsonl" {
            // Filename encodes the day — parse it rather than statting.
            let name = url.deletingPathExtension().lastPathComponent
            guard let day = Self.dayFormatter.date(from: String(name.dropFirst("history-".count))),
                  day < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
