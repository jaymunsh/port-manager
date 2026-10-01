import Darwin
import Foundation

/// CPU/memory usage for one process, from a single `ps` snapshot.
struct ProcStat: Sendable, Hashable {
    var cpu: Double
    var mem: Double
    var ppid: pid_t = 0
    var command: String = ""
}

struct ProcessService: Sendable {
    /// PIDs that must never be signalled from this app.
    private static let protectedPIDs: Set<pid_t> = [0, 1]
    private static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "systemd"
    ]

    func isProtected(pid: pid_t, command: String) -> Bool {
        pid <= 1 || pid == getpid() || Self.protectedPIDs.contains(pid)
            || Self.protectedNames.contains(URL(fileURLWithPath: command).lastPathComponent)
    }

    func identity(for pid: pid_t) -> ProcessIdentity? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let commandCapacity = MemoryLayout.size(ofValue: info.pbi_comm)
        let command = withUnsafePointer(to: &info.pbi_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: commandCapacity) {
                String(cString: $0)
            }
        }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0
            ? String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        return ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec,
                               startMicroseconds: info.pbi_start_tvusec,
                               command: command, executablePath: path)
    }

    static func identityMatches(expected: ProcessIdentity, current: ProcessIdentity?) -> Bool {
        current == expected
    }

    func isAlive(_ identity: ProcessIdentity) -> Bool {
        Self.identityMatches(expected: identity, current: self.identity(for: identity.pid))
    }

    func isAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM // exists but owned by someone else
    }

    func executablePath(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if len > 0 {
            return String(decoding: buffer.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return (try? Shell.run("/bin/ps", ["-p", String(pid), "-o", "comm="]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    func info(for pid: pid_t) -> ProcessInfo {
        let psResult = try? Shell.run("/bin/ps", [
            "-p", String(pid),
            "-o", "ppid=,user=,%cpu=,%mem=,lstart="
        ])
        var ppid: pid_t = 0
        var user = ""
        var cpu = 0.0, mem = 0.0
        var start: Date?
        if let line = psResult?.stdout.split(separator: "\n").first {
            // e.g. "   1 sunghyuk   0.0  0.1 Tue Sep 16 09:12:33 2025"
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.count >= 4 {
                ppid = pid_t(cols[0]) ?? 0
                user = String(cols[1])
                cpu = Double(cols[2]) ?? 0
                mem = Double(cols[3]) ?? 0
                if cols.count >= 9 {
                    let dateStr = cols[4...8].joined(separator: " ")
                    let fmt = DateFormatter()
                    fmt.locale = Locale(identifier: "en_US_POSIX")
                    fmt.dateFormat = "EEE MMM d HH:mm:ss yyyy"
                    start = fmt.date(from: dateStr)
                }
            }
        }

        var children: [pid_t] = []
        if let res = try? Shell.run("/usr/bin/pgrep", ["-P", String(pid)]) {
            children = res.stdout.split(separator: "\n").compactMap { pid_t($0) }
        }

        return ProcessInfo(
            pid: pid,
            executablePath: executablePath(for: pid),
            ppid: ppid,
            childPIDs: children,
            user: user,
            cpuPercent: cpu,
            memPercent: mem,
            startTime: start,
            openFileCount: LsofProvider().openFileCount(for: pid)
        )
    }

    /// CPU/mem for every process in one `ps` call — cheap enough to run per refresh.
    /// Also captures ppid+comm so the UI can reconstruct the parent chain.
    func allStats() -> [pid_t: ProcStat] {
        guard let res = try? Shell.run("/bin/ps", ["-axo", "pid=,ppid=,%cpu=,%mem=,comm="]) else { return [:] }
        return Self.parseStats(res.stdout)
    }

    static func parseStats(_ output: String) -> [pid_t: ProcStat] {
        var map: [pid_t: ProcStat] = [:]
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 4, let pid = pid_t(cols[0]) else { continue }
            // comm is the remainder of the line — it may contain spaces.
            let comm = cols.count > 4 ? cols[4...].joined(separator: " ") : ""
            map[pid] = ProcStat(
                cpu: Double(cols[2]) ?? 0,
                mem: Double(cols[3]) ?? 0,
                ppid: pid_t(cols[1]) ?? 0,
                command: comm)
        }
        return map
    }

    /// Ancestor chain for `pid`: [(pid, command)] walking up to launchd.
    /// Uses the stats table already collected by the store.
    static func ancestorChain(of pid: pid_t, stats: [pid_t: ProcStat], maxDepth: Int = 12) -> [(pid: pid_t, command: String)] {
        var chain: [(pid_t, String)] = []
        var current = stats[pid]?.ppid ?? 0
        var seen: Set<pid_t> = [pid]
        while current > 1, !seen.contains(current), chain.count < maxDepth {
            seen.insert(current)
            guard let stat = stats[current] else { break }
            chain.append((current, stat.command))
            current = stat.ppid
        }
        if current <= 1 && !seen.contains(1), let launchd = stats[1] {
            chain.append((1, launchd.command))
        }
        return chain.reversed() // launchd … parent
    }

    /// Sends a signal; returns nil on success.
    func sendSignal(_ sig: Int32, to expected: ProcessIdentity) -> KillError? {
        let pid = expected.pid
        if isProtected(pid: pid, command: expected.command) { return .protectedProcess }
        guard let current = identity(for: pid) else {
            return isAlive(pid) ? .identityUnavailable : .noSuchProcess
        }
        if isProtected(pid: pid, command: current.command)
            || isProtected(pid: pid, command: current.executablePath) { return .protectedProcess }
        guard Self.identityMatches(expected: expected, current: current) else { return .identityChanged }
        guard sig == SIGTERM || sig == SIGKILL else { return .failed(EINVAL) }
        if kill(pid, sig) == 0 { return nil }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .noSuchProcess
        default: return .failed(errno)
        }
    }
}
