import Foundation

struct PortEntry: Identifiable, Hashable, Sendable {
    enum Proto: String, Hashable, Sendable {
        case tcp = "TCP"
        case udp = "UDP"
    }

    let pid: pid_t
    let command: String
    let user: String
    let fd: String
    let proto: Proto
    let address: String
    let port: Int

    var id: String { "\(pid):\(fd):\(proto.rawValue):\(address):\(port)" }
    var endpoint: String { "\(address):\(port)" }
    var isLocalOnly: Bool { address == "127.0.0.1" || address == "[::1]" || address == "localhost" }
}
