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
    /// TCP state (LISTEN, ESTABLISHED, …); empty for UDP.
    let state: String
    /// "host:port" of the peer for outbound/connected sockets.
    let remote: String?

    var id: String { "\(pid):\(fd):\(proto.rawValue):\(address):\(port):\(remote ?? "")" }
    var endpoint: String { "\(address):\(port)" }
    var isLocalOnly: Bool { address == "127.0.0.1" || address == "[::1]" || address == "localhost" }
    /// Listening TCP socket, or a bound (unconnected) UDP socket.
    var isListener: Bool { remote == nil && (proto == .udp || state == "LISTEN") }
}
