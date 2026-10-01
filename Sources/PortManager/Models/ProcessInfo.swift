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

/// Creation time comes directly from libproc, including microseconds.
struct ProcessIdentity: Hashable, Sendable {
    let pid: pid_t
    var startSeconds: UInt64
    var startMicroseconds: UInt64
    let command: String
    let executablePath: String
}

enum KillError: Error, Sendable, Equatable {
    case notPermitted
    case noSuchProcess
    case failed(Int32)
    case protectedProcess
    case identityChanged
    case identityUnavailable

    var description: String {
        switch self {
        case .notPermitted: "Permission denied — the process is owned by another user or root"
        case .noSuchProcess: "Process no longer exists"
        case .failed(let code): "kill(2) failed with errno \(code)"
        case .protectedProcess: "This process is protected and cannot be terminated"
        case .identityChanged: "The process changed since it was selected. Refresh and select it again"
        case .identityUnavailable: "Cannot verify the process identity. Refresh and try again"
        }
    }
}
