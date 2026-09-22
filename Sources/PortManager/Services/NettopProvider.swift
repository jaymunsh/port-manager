import Foundation

/// Per-process and per-connection network byte counters from
/// `nettop -x -l 1`. Values are cumulative since process start —
/// the store diffs successive snapshots into rates.
struct NettopProvider: Sendable {
    struct Snapshot: Sendable {
        var bytesIn: Int64
        var bytesOut: Int64
    }

    /// Identifies one socket: owning pid + local port + remote port
    /// (0 for listeners/wildcard peers).
    struct ConnKey: Hashable, Sendable {
        var pid: pid_t
        var localPort: Int
        var remotePort: Int
    }

    struct Result: Sendable {
        var perPid: [pid_t: Snapshot] = [:]
        var perConn: [ConnKey: Snapshot] = [:]
    }

    func snapshot() -> Result {
        guard let res = try? Shell.run("/usr/bin/nettop",
                                       ["-x", "-l", "1", "-J", "bytes_in,bytes_out"])
        else { return Result() }
        return Self.parse(res.stdout)
    }

    /// Output shape:
    ///   `node.836                          1000   500`      — process totals
    ///   `   tcp4 10.1.0.4:63294<->17.0.0.1:443   100   50` — per connection
    static func parse(_ output: String) -> Result {
        var result = Result()
        var currentPID: pid_t = 0
        for line in output.split(separator: "\n") {
            guard line.contains("<->") else {
                // Process header row: "name.pid   in   out"
                let cols = line.split(separator: " ", omittingEmptySubsequences: true)
                guard cols.count >= 3,
                      let bin = Int64(cols[cols.count - 2]),
                      let bout = Int64(cols[cols.count - 1]),
                      let dot = cols[0].lastIndex(of: "."),
                      let pid = pid_t(cols[0][cols[0].index(after: dot)...])
                else { continue }
                currentPID = pid
                result.perPid[pid] = Snapshot(bytesIn: bin, bytesOut: bout)
                continue
            }
            // Connection row — last two columns are the counters.
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let idx = cols.firstIndex(where: { $0.contains("<->") }),
                  cols.count > idx + 2,
                  let bin = Int64(cols[cols.count - 2]),
                  let bout = Int64(cols[cols.count - 1])
            else { continue }
            let endpoints = cols[idx]
            guard let arrow = endpoints.range(of: "<->") else { continue }
            let local = endpoints[endpoints.startIndex..<arrow.lowerBound]
            let remote = endpoints[arrow.upperBound...]
            guard let localPort = lastPort(local) else { continue }
            let key = ConnKey(pid: currentPID, localPort: localPort,
                              remotePort: lastPort(remote) ?? 0)
            result.perConn[key] = Snapshot(bytesIn: bin, bytesOut: bout)
        }
        return result
    }

    /// Port from `host:port` / `*:*` — nil when the port is `*`.
    private static func lastPort(_ endpoint: Substring) -> Int? {
        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        let tail = endpoint[endpoint.index(after: colon)...]
        guard tail != "*" else { return nil }
        return Int(tail)
    }
}
