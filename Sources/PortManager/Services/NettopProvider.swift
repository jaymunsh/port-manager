import Foundation

/// Per-process network byte counters from `nettop -P -x -l 1`.
/// Values are cumulative since process start — the store diffs them.
struct NettopProvider: Sendable {
    struct Snapshot: Sendable {
        var bytesIn: Int64
        var bytesOut: Int64
    }

    func snapshot() -> [pid_t: Snapshot] {
        guard let res = try? Shell.run("/usr/bin/nettop",
                                       ["-P", "-x", "-l", "1", "-J", "bytes_in,bytes_out"])
        else { return [:] }
        return Self.parse(res.stdout)
    }

    /// Lines look like: `com.docker.backend.29480   123456   7890`
    static func parse(_ output: String) -> [pid_t: Snapshot] {
        var map: [pid_t: Snapshot] = [:]
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 3,
                  let bytesIn = Int64(cols[cols.count - 2]),
                  let bytesOut = Int64(cols[cols.count - 1]),
                  let dot = cols[0].lastIndex(of: "."),
                  let pid = pid_t(cols[0][cols[0].index(after: dot)...])
            else { continue }
            map[pid] = Snapshot(bytesIn: bytesIn, bytesOut: bytesOut)
        }
        return map
    }
}
