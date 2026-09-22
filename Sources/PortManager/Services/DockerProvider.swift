import Foundation

/// Reads `docker ps` to map published host ports back to containers.
/// Docker may be absent — all methods return empty results then.
struct DockerProvider: Sendable {
    struct Snapshot: Sendable {
        var containers: [DockerContainer]
        /// host port → container
        var byPort: [Int: DockerContainer]
        /// false when the docker CLI/daemon is unavailable — callers should
        /// back off instead of re-running a failing spawn every poll.
        var available: Bool
    }

    func snapshot() -> Snapshot {
        guard let res = try? Shell.run("/usr/bin/env", [
            "docker", "ps", "--format", "{{.ID}}|{{.Image}}|{{.Names}}|{{.Ports}}"
        ]), res.status == 0 else {
            return Snapshot(containers: [], byPort: [:], available: false)
        }
        return Self.parse(res.stdout)
    }

    static func parse(_ output: String) -> Snapshot {
        var containers: [DockerContainer] = []
        var byPort: [Int: DockerContainer] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { continue }
            let hostPorts = Self.parsePorts(String(parts[3]))
            let container = DockerContainer(
                id: String(parts[0]),
                name: String(parts[2]),
                image: String(parts[1]),
                hostPorts: hostPorts)
            containers.append(container)
            for port in hostPorts { byPort[port] = container }
        }
        return Snapshot(containers: containers, byPort: byPort, available: true)
    }

    /// Extracts host ports from a Ports column like
    /// `0.0.0.0:5432->5432/tcp, [::]:8080->8080/tcp` or `127.0.0.1:3000->80/tcp`.
    static func parsePorts(_ field: String) -> [Int] {
        var ports: Set<Int> = []
        for mapping in field.split(separator: ",") {
            // Each entry: "<bind>:<hostPort>-><containerPort>/<proto>"
            guard let arrow = mapping.range(of: "->") else { continue }
            let left = mapping[..<arrow.lowerBound]
            guard let colon = left.lastIndex(of: ":"),
                  let port = Int(left[left.index(after: colon)...]) else { continue }
            ports.insert(port)
        }
        return ports.sorted()
    }
}
