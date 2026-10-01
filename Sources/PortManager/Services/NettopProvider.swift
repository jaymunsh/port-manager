import Darwin
import Foundation

/// Per-process and per-connection network byte counters from
/// `nettop -x -l 1`. Values are cumulative since process start —
/// the store diffs successive snapshots into rates.
struct NettopProvider: Sendable {
    struct Snapshot: Sendable {
        var bytesIn: Int64
        var bytesOut: Int64
    }

    /// Identifies a connection by process, transport and both endpoints.
    struct ConnKey: Hashable, Sendable {
        var pid: pid_t
        var localPort: Int
        var remotePort: Int
        var localAddress: String = "*"
        var remoteAddress: String = "*"
        var proto: String = "TCP"

        init(pid: pid_t, localPort: Int, remotePort: Int,
             localAddress: String = "*", remoteAddress: String = "*", proto: String = "TCP") {
            self.pid = pid
            self.localPort = localPort
            self.remotePort = remotePort
            self.localAddress = Self.normalize(localAddress)
            self.remoteAddress = Self.normalize(remoteAddress)
            self.proto = proto.uppercased()
        }

        private static func normalize(_ host: String) -> String {
            let clean = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
            let components = clean.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
            let base = String(components[0])
            let scope = components.count == 2 ? "%\(components[1])" : ""
            var address = in6_addr()
            if inet_pton(AF_INET6, base, &address) == 1 {
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                if inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil {
                    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) + scope
                }
            }
            return clean
        }
    }

    struct Result: Sendable {
        var perPid: [pid_t: Snapshot] = [:]
        var perConn: [ConnKey: Snapshot] = [:]
    }

    func snapshot() throws -> Result {
        let res = try Shell.run("/usr/bin/nettop", ["-n", "-x", "-l", "1", "-J", "bytes_in,bytes_out"])
        try res.requireSuccess(command: "nettop")
        return Self.parse(res.stdout)
    }

    /// Output shape:
    ///   `node.836                          1000   500`      — process totals
    ///   `   tcp4 10.1.0.4:63294<->17.0.0.1:443   100   50` — per connection
    static func parse(_ output: String) -> Result {
        var result = Result()
        var currentPID: pid_t = 0
        for line in output.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0.isWhitespace })
            guard line.contains("<->") else {
                // The process name can contain spaces. Locate its final .PID token.
                currentPID = 0
                guard let header = cols.lastIndex(where: { processPID($0) != nil }),
                      let pid = processPID(cols[header]) else { continue }
                currentPID = pid
                let counters = cols.dropFirst(header + 1)
                if counters.count == 2, let bin = Int64(counters[counters.startIndex]),
                   let bout = Int64(counters[counters.index(after: counters.startIndex)]) {
                    result.perPid[pid] = Snapshot(bytesIn: bin, bytesOut: bout)
                }
                continue
            }
            guard let idx = cols.firstIndex(where: { $0.contains("<->") }), idx > 0 else { continue }
            let endpoints = cols[idx]
            guard let arrow = endpoints.range(of: "<->") else { continue }
            let local = endpoints[endpoints.startIndex..<arrow.lowerBound]
            let remote = endpoints[arrow.upperBound...]
            let ipv6 = cols[idx - 1].hasSuffix("6")
            guard currentPID > 0, let localEndpoint = endpoint(local, ipv6: ipv6),
                  let remoteEndpoint = endpoint(remote, ipv6: ipv6) else { continue }
            let proto = cols[idx - 1].hasPrefix("udp") ? "UDP" : "TCP"
            let key = ConnKey(pid: currentPID, localPort: localEndpoint.port,
                              remotePort: remoteEndpoint.port,
                              localAddress: localEndpoint.address,
                              remoteAddress: remoteEndpoint.address, proto: proto)
            let counters = cols.dropFirst(idx + 1)
            if counters.count == 2, let bin = Int64(counters[counters.startIndex]),
               let bout = Int64(counters[counters.index(after: counters.startIndex)]) {
                result.perConn[key] = Snapshot(bytesIn: bin, bytesOut: bout)
            } else if counters.isEmpty, remoteEndpoint.port == 0, remoteEndpoint.address == "*" {
                // nettop leaves idle listener counters blank; retain a measured zero
                // so alert evaluation does not fall back to unrelated process traffic.
                result.perConn[key] = Snapshot(bytesIn: 0, bytesOut: 0)
            }
        }
        return result
    }

    private static func processPID(_ token: Substring) -> pid_t? {
        guard let dot = token.lastIndex(of: "."),
              let pid = pid_t(token[token.index(after: dot)...]), pid > 0 else { return nil }
        return pid
    }

    /// nettop uses `host:port` for IPv4 and `host.port` for IPv6.
    private static func endpoint(_ endpoint: Substring, ipv6: Bool) -> (address: String, port: Int)? {
        guard let delimiter = ipv6 ? (endpoint.lastIndex(of: ".") ?? endpoint.lastIndex(of: ":"))
                                  : endpoint.lastIndex(of: ":") else { return nil }
        let tail = endpoint[endpoint.index(after: delimiter)...]
        guard let port = tail == "*" ? 0 : Int(tail) else { return nil }
        return (String(endpoint[..<delimiter]), port)
    }
}
