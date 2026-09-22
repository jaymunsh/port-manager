import CoreWLAN
import Foundation

/// Gathers network interface state: byte counters (netstat -ibn),
/// addressing/flags (ifconfig), default gateway and DNS (netstat/scutil),
/// and Wi-Fi details (CoreWLAN).
struct NetworkProvider: Sendable {
    /// Interface prefixes we surface — skips lo/gif/stf/anpi/awdl/llw noise.
    private static let visiblePrefixes = ["en", "utun", "bridge", "ipsec", "ppp"]

    func interfaces() -> [NetInterface] {
        let counters = linkCounters()
        let config = ifconfigInfo()
        let wifiIface = wifiInterfaceName()

        var out: [NetInterface] = []
        for (name, c) in counters {
            guard Self.visiblePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            let cfg = config[name]
            let iface = NetInterface(
                name: name,
                displayName: displayName(for: name, wifiInterface: wifiIface),
                isUp: cfg?.isUp ?? false,
                isActive: cfg?.isActive ?? false,
                ipv4: cfg?.ipv4,
                ipv6: cfg?.ipv6,
                mac: cfg?.mac ?? c.mac,
                bytesIn: c.bytesIn,
                bytesOut: c.bytesOut,
                wifi: name == wifiIface ? wifiInfo() : nil
            )
            if !iface.isUp && iface.bytesIn == 0 && iface.bytesOut == 0 { continue }
            out.append(iface)
        }
        return out.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func defaultGateway() -> String? {
        guard let res = try? Shell.run("/usr/sbin/netstat", ["-rn", "-f", "inet"]) else { return nil }
        for line in res.stdout.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.count >= 2, cols[0] == "default", cols[2].contains("G") {
                return String(cols[1])
            }
        }
        return nil
    }

    func dnsServers() -> [String] {
        guard let res = try? Shell.run("/usr/sbin/scutil", ["--dns"]) else { return [] }
        var seen = Set<String>()
        var servers: [String] = []
        for line in res.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("nameserver["),
                  let value = trimmed.split(separator: ":").last else { continue }
            let server = value.trimmingCharacters(in: .whitespaces)
            if seen.insert(server).inserted { servers.append(server) }
        }
        return servers
    }

    // MARK: - Parsing

    /// Byte counters + MAC per interface from `netstat -ibn` <Link#> rows.
    private func linkCounters() -> [String: (bytesIn: Int64, bytesOut: Int64, mac: String?)] {
        guard let res = try? Shell.run("/usr/sbin/netstat", ["-ibn"]) else { return [:] }
        var map: [String: (Int64, Int64, String?)] = [:]
        for line in res.stdout.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 10, cols[2].hasPrefix("<Link") else { continue }
            let name = String(cols[0]).replacingOccurrences(of: "*", with: "")
            let mac = cols[3].contains(":") ? String(cols[3]) : nil
            map[name] = (Int64(cols[6]) ?? 0, Int64(cols[9]) ?? 0, mac)
        }
        return map
    }

    private struct Ifconfig {
        var isUp = false
        var isActive = false
        var ipv4: String?
        var ipv6: String?
        var mac: String?
    }

    private func ifconfigInfo() -> [String: Ifconfig] {
        guard let res = try? Shell.run("/sbin/ifconfig", ["-a"]) else { return [:] }
        var map: [String: Ifconfig] = [:]
        var current: String?
        for line in res.stdout.split(separator: "\n") {
            if !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") {
                current = String(line[..<colon])
                map[current!] = Ifconfig(isUp: line.contains("UP,") || line.contains("<UP"),
                                         isActive: false)
                continue
            }
            guard let name = current else { continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("ether ") {
                map[name]?.mac = String(t.dropFirst(6))
            } else if t.hasPrefix("inet ") {
                map[name]?.ipv4 = t.split(separator: " ").dropFirst().first.map(String.init)
                map[name]?.isActive = true
            } else if t.hasPrefix("inet6 ") && !t.contains("%") {
                map[name]?.ipv6 = t.split(separator: " ").dropFirst().first.map(String.init)
            } else if t.hasPrefix("status: active") {
                map[name]?.isActive = true
            }
            if map[name]?.ipv4 != nil { map[name]?.isActive = true }
        }
        return map
    }

    private func wifiInterfaceName() -> String? {
        CWWiFiClient.shared().interface()?.interfaceName
    }

    private func wifiInfo() -> WifiInfo? {
        guard let i = CWWiFiClient.shared().interface() else { return nil }
        return WifiInfo(
            ssid: i.ssid(),
            rssi: i.rssiValue(),
            channel: i.wlanChannel()?.channelNumber ?? 0,
            txRateMbps: i.transmitRate()
        )
    }

    private func displayName(for name: String, wifiInterface: String?) -> String {
        if name == wifiInterface { return "Wi-Fi" }
        if name.hasPrefix("en") { return "Ethernet" }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return "VPN" }
        if name.hasPrefix("bridge") { return "Bridge" }
        return name
    }
}
