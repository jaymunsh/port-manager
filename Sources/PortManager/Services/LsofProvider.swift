import Foundation

struct LsofProvider: Sendable {
    /// Snapshot of TCP listeners (and optionally all UDP sockets / outbound
    /// connections). `-iTCP -sTCP:LISTEN -iUDP` evaluates as
    /// (TCP AND LISTEN) OR (UDP).
    func snapshot(includeUDP: Bool = false, includeConnections: Bool = false) throws -> [PortEntry] {
        var args = ["-nP", "-FpcnPLfT", "-iTCP"]
        if !includeConnections { args.append("-sTCP:LISTEN") }
        if includeUDP { args.append("-iUDP") }
        let result = try Shell.run("/usr/sbin/lsof", args)
        // lsof exits 1 when nothing matches — still parse whatever stdout has.
        if result.status != 0 && (result.status != 1 || !result.stderr.isEmpty) {
            try result.requireSuccess(command: "lsof")
        }
        return LsofParser.parse(result.stdout)
    }

    /// Processes holding open files under a path (used to explain busy ejects).
    func processesUsing(path: String) throws -> [(pid: pid_t, command: String)] {
        let result = try Shell.run("/usr/sbin/lsof", ["-nP", "-Fpc", "--", path])
        if result.status != 0 && (result.status != 1 || !result.stderr.isEmpty) {
            try result.requireSuccess(command: "lsof")
        }
        var seen = Set<pid_t>()
        var out: [(pid_t, String)] = []
        var lastPID: pid_t = 0
        var cmdByPID: [pid_t: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            guard let f = line.first else { continue }
            let v = String(line.dropFirst())
            if f == "p", let pid = pid_t(v) {
                lastPID = pid
            } else if f == "c" {
                cmdByPID[lastPID] = v
            }
        }
        for (pid, cmd) in cmdByPID where seen.insert(pid).inserted {
            out.append((pid, cmd))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// Number of open files/connections for a pid.
    func openFileCount(for pid: pid_t) -> Int {
        guard let result = try? Shell.run("/usr/sbin/lsof", ["-p", String(pid), "-Fn"]) else { return 0 }
        return result.stdout.split(separator: "\n").filter { $0.hasPrefix("n") }.count
    }
}
