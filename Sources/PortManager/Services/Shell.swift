import Darwin
import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String

    func requireSuccess(command: String) throws {
        guard status == 0 else {
            throw ShellError.commandFailed(command, status, stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum ShellError: Error, LocalizedError, Sendable {
    case timedOut(String)
    case cancelled
    case outputReadFailed(Int32)
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let command): "\(command) timed out"
        case .cancelled: "Command cancelled"
        case .outputReadFailed(let code): "Unable to read command output (errno \(code))"
        case .commandFailed(let command, let status, let message):
            "\(command) failed (\(status))\(message.isEmpty ? "" : ": \(message)")"
        }
    }
}

enum Shell {
    /// Drain both pipes as the child runs. Nonblocking reads keep stderr from
    /// blocking stdout, and make timeout/cancellation independent of EOF.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval = 15,
                    isCancelled: @Sendable () -> Bool = { Task.isCancelled }) throws -> CommandResult {
        guard !isCancelled() else { throw ShellError.cancelled }
        guard timeout > 0 else { throw ShellError.timedOut(launchPath) }
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        let outFD = outPipe.fileHandleForReading.fileDescriptor
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        for fd in [outFD, errFD] {
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
                throw ShellError.outputReadFailed(errno)
            }
        }
        defer {
            if process.isRunning { stop(process) }
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
        }
        try process.run()
        let started = Foundation.ProcessInfo.processInfo.systemUptime
        var outData = Data(), errData = Data()
        var outEOF = false, errEOF = false
        var buffer = [UInt8](repeating: 0, count: 8192)

        func readAvailable(_ fd: Int32, into data: inout Data, eof: inout Bool) throws -> Bool {
            if eof { return false }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                return true
            }
            if count < 0 && errno != EAGAIN && errno != EINTR {
                throw ShellError.outputReadFailed(errno)
            }
            if count == 0 { eof = true }
            return false
        }

        while true {
            guard !isCancelled() else { throw ShellError.cancelled }
            guard Foundation.ProcessInfo.processInfo.systemUptime - started < timeout else {
                throw ShellError.timedOut(launchPath)
            }
            // Limit each read to one chunk so neither stream can starve the
            // other stream or the cancellation check.
            let readOut = try readAvailable(outFD, into: &outData, eof: &outEOF)
            let readErr = try readAvailable(errFD, into: &errData, eof: &errEOF)
            if !process.isRunning && !readOut && !readErr { break }
            if !readOut && !readErr {
                var descriptors = [
                    pollfd(fd: outEOF ? -1 : outFD, events: Int16(POLLIN), revents: 0),
                    pollfd(fd: errEOF ? -1 : errFD, events: Int16(POLLIN), revents: 0)
                ]
                _ = poll(&descriptors, nfds_t(descriptors.count), 20)
            }
        }
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Foundation.ProcessInfo.processInfo.systemUptime + 0.25
        while process.isRunning && Foundation.ProcessInfo.processInfo.systemUptime < deadline {
            usleep(10_000)
        }
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}

/// Detached collectors inherit cancellation explicitly, so stopping a store
/// also stops any subprocess currently running in its collector.
enum Background {
    static func run<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
