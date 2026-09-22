import Foundation

struct NetInterface: Identifiable, Hashable, Sendable {
    let name: String            // en0, utun3, …
    var displayName: String     // "Wi-Fi", "Ethernet", "VPN", …
    var isUp: Bool              // UP flag set
    var isActive: Bool          // has a live IPv4 address
    var ipv4: String?
    var ipv6: String?
    var mac: String?
    var bytesIn: Int64 = 0      // cumulative counters
    var bytesOut: Int64 = 0
    var inRate: Double = 0      // bytes/sec, filled by NetworkStore
    var outRate: Double = 0
    var wifi: WifiInfo?

    var id: String { name }
}

struct WifiInfo: Hashable, Sendable {
    var ssid: String?
    var rssi: Int               // dBm
    var channel: Int
    var txRateMbps: Double

    var signalDescription: String {
        switch rssi {
        case -50...0: return "excellent"
        case -60 ..< -50: return "good"
        case -70 ..< -60: return "fair"
        default: return "weak"
        }
    }
}
