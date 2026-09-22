import Darwin
import Foundation

/// CPU/memory usage for one process, from a single `ps` snapshot.
struct ProcStat: Sendable {
    var cpu: Double
    var mem: Double
}

struct ProcessService: Sendable {
    /// PIDs that must never be signalled from this app.
    private static let protectedPIDs: Set<pid_t> = [0, 1]
    private static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "systemd"
    ]

    func isProtected(pid: pid_t, command: String) -> Bool {
        Self.protectedPIDs.contains(pid) || Self.protectedNames.contains(command)
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
    func allStats() -> [pid_t: ProcStat] {
        guard let res = try? Shell.run("/bin/ps", ["-axo", "pid=,%cpu=,%mem="]) else { return [:] }
        return Self.parseStats(res.stdout)
    }

    static func parseStats(_ output: String) -> [pid_t: ProcStat] {
        var map: [pid_t: ProcStat] = [:]
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 3, let pid = pid_t(cols[0]) else { continue }
            map[pid] = ProcStat(cpu: Double(cols[1]) ?? 0, mem: Double(cols[2]) ?? 0)
        }
        return map
    }

    /// Sends a signal; returns nil on success.
    func sendSignal(_ sig: Int32, to pid: pid_t) -> KillError? {
        if kill(pid, sig) == 0 { return nil }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .noSuchProcess
        default: return .failed(errno)
        }
    }
}
