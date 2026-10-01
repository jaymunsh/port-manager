import Foundation

/// Persists activity events as JSONL — one file per day under
/// `~/Library/Application Support/PortManager/history/`.
/// Size stays tiny: one event is ~100 bytes.
struct HistoryService: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    private static let defaultDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortManager/history", isDirectory: true)
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
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
    func loadRecent(days: Int, limit: Int = 500) -> [ActivityEvent] {
        guard days > 0, limit > 0 else { return [] }
        var events: [ActivityEvent] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for offset in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let url = fileURL(for: date)
            guard let data = try? Data(contentsOf: url) else { continue }
            var dayEvents: [ActivityEvent] = []
            for line in data.split(separator: 0x0A) {
                if let event = try? decoder.decode(ActivityEvent.self, from: line) {
                    dayEvents.append(event)
                }
            }
            events.append(contentsOf: dayEvents.sorted { $0.date > $1.date }.prefix(limit - events.count))
            if events.count >= limit { break }
        }
        return events.sorted { $0.date > $1.date }
    }

    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil) else { return }
        for url in files where url.lastPathComponent.hasPrefix("history-") && url.pathExtension == "jsonl" {
            try? FileManager.default.removeItem(at: url)
        }
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
