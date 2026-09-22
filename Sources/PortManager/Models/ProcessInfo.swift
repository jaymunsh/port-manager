import Foundation

struct ProcessInfo: Sendable {
    let pid: pid_t
    let executablePath: String
    let ppid: pid_t
    let childPIDs: [pid_t]
    let user: String
    let cpuPercent: Double
    let memPercent: Double
    let startTime: Date?
    let openFileCount: Int
}

enum KillError: Error, Sendable {
    case notPermitted
    case noSuchProcess
    case failed(Int32)

    var description: String {
        switch self {
        case .notPermitted: "Permission denied — the process is owned by another user or root"
        case .noSuchProcess: "Process no longer exists"
        case .failed(let code): "kill(2) failed with errno \(code)"
        }
    }
}
