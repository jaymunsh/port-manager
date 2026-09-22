import Foundation

/// Parses `lsof -F` machine-readable output into `PortEntry` values.
///
/// Field layout per record block:
///   p<pid>      — starts a process block
///   c<command>  — process command name
///   L<login>    — owning user
///   f<fd>       — starts a file-descriptor record (one socket each)
///   P<proto>    — TCP / UDP
///   n<name>     — endpoint, e.g. `*:3000`, `127.0.0.1:7265`, `a:1->b:2`
///   TST=<state> — TCP state (LISTEN, ESTABLISHED, …)
enum LsofParser {
    static func parse(_ output: String) -> [PortEntry] {
        var entries: [PortEntry] = []
        var pid: pid_t = 0
        var command = ""
        var user = ""
        var fd = ""
        var proto = ""
        var state = ""
        var name: String?

        func flush() {
            if let current = name, let ep = splitEndpoint(current) {
                entries.append(PortEntry(
                    pid: pid, command: command, user: user, fd: fd,
                    proto: proto == "UDP" ? .udp : .tcp,
                    address: ep.address, port: ep.port,
                    state: state, remote: ep.remote
                ))
            }
            name = nil
            state = ""
        }

        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                flush()
                pid = pid_t(value) ?? 0
                command = ""
                user = ""
            case "c":
                command = value
            case "L":
                user = value
            case "f":
                flush()
                fd = value
                proto = ""
            case "P":
                proto = value
            case "n":
                name = value
            case "T":
                if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default:
                break
            }
        }
        flush()
        return entries
    }

    /// Splits `host:port[->peer:port]` — including `[ipv6]:port` — and ignores
    /// entries without a numeric local port (e.g. `*:*` unbound UDP).
    static func splitEndpoint(_ name: String) -> (address: String, port: Int, remote: String?)? {
        var s = name
        if let space = s.firstIndex(of: " ") {
            s = String(s[..<space])
        }
        var remote: String?
        if let arrow = s.range(of: "->") {
            let r = String(s[arrow.upperBound...])
            remote = r.isEmpty ? nil : r
            s = String(s[..<arrow.lowerBound])
        }
        guard let colon = s.lastIndex(of: ":") else { return nil }
        let host = String(s[..<colon])
        guard let port = Int(s[s.index(after: colon)...]) else { return nil }
        return (host, port, remote)
    }
}
