import Foundation

/// In-binary test runner (`PortManager --selftest`).
/// CLT-only environments have no `swift test` runner, so assertions live here.
enum SelfTest {
    static func run() -> Never {
        MainActor.assumeIsolated {
            var failures = 0

            func check(_ condition: Bool, _ name: String) {
                if condition {
                    print("  ✓ \(name)")
                } else {
                    print("  ✗ \(name)")
                    failures += 1
                }
            }

            func section(_ name: String) { print("\n\(name)") }

            func entry(port: Int, command: String) -> PortEntry {
                PortEntry(pid: 1, command: command, user: "u", fd: "1",
                          proto: .tcp, address: "*", port: port,
                          state: "LISTEN", remote: nil)
            }

            // MARK: LsofParser

            section("LsofParser")

            let tcpFixture = """
            p497
            crapportd
            Lsunghyuk
            f7
            PTCP
            n*:49152
            f8
            PTCP
            n127.0.0.1:7265
            p836
            cnode
            Lsunghyuk
            f12
            PTCP
            n*:3000
            """

            let tcp = LsofParser.parse(tcpFixture)
            check(tcp.count == 3, "parses 3 TCP listeners")
            check(tcp[0].pid == 497 && tcp[0].command == "rapportd" && tcp[0].user == "sunghyuk",
                  "captures pid/command/user")
            check(tcp[0].proto == .tcp && tcp[0].port == 49152 && tcp[0].address == "*",
                  "captures proto/port/address")
            check(tcp[1].isLocalOnly && !tcp[0].isLocalOnly, "detects localhost binding")
            check(tcp[2].command == "node" && tcp[2].port == 3000, "second process block")

            let udpFixture = """
            p529
            cidentityservicesd
            Lsunghyuk
            f7
            PUDP
            n*:*
            f9
            PUDP
            n*:5353
            """

            let udp = LsofParser.parse(udpFixture)
            check(udp.count == 1, "skips unbound *:* socket")
            check(udp[0].proto == .udp && udp[0].port == 5353, "parses UDP proto")

            let v6 = LsofParser.parse("""
            p100
            cdevd
            Lroot
            f4
            PTCP
            n[::1]:8080 (LISTEN)
            """)
            check(v6.count == 1 && v6[0].address == "[::1]" && v6[0].port == 8080,
                  "parses IPv6 + LISTEN suffix")
            check(LsofParser.parse("").isEmpty, "empty output → no entries")

            let connected = LsofParser.splitEndpoint("127.0.0.1:5555->1.2.3.4:443")
            check(connected?.port == 5555 && connected?.remote == "1.2.3.4:443",
                  "splits local/remote of connected socket")

            let connFixture = """
            p836
            cnode
            Lsunghyuk
            f12
            PTCP
            n*:3000
            TST=LISTEN
            f14
            PTCP
            n10.0.0.1:5555->93.184.216.34:443
            TST=ESTABLISHED
            """
            let conns = LsofParser.parse(connFixture)
            check(conns.count == 2 && conns[0].state == "LISTEN" && conns[0].isListener,
                  "parses TST=LISTEN state")
            check(conns[1].state == "ESTABLISHED" && !conns[1].isListener
                  && conns[1].remote == "93.184.216.34:443",
                  "parses ESTABLISHED outbound socket")

            // MARK: PresetStore.status

            section("PresetStore.status")

            let store = PresetStore()
            let loose = PortPreset(name: "api", port: 8080)
            let strict = PortPreset(name: "api", port: 8080, expectedCommand: "node")

            check(store.status(for: loose, entries: []) == .free, "free when nothing listens")
            check(store.status(for: loose, entries: [entry(port: 8080, command: "python3")]) == .expected,
                  "occupied counts as expected without matcher")
            check(store.status(for: strict, entries: [entry(port: 8080, command: "node")]) == .expected,
                  "expected when command matches")
            check(store.status(for: strict, entries: [entry(port: 8080, command: "python3")]) == .conflict,
                  "conflict when command differs")
            check(store.status(for: strict, entries: [entry(port: 8081, command: "python3")]) == .free,
                  "other ports ignored")

            // MARK: ProcessService.parseStats

            section("ProcessService.parseStats")

            let psOut = "    1     0   0.0   0.1 /sbin/launchd\n  497     1  12.3   2.5 /usr/sbin/rapportd\nnotapid x y z\n"
            let stats = ProcessService.parseStats(psOut)
            check(stats[497]?.cpu == 12.3 && stats[497]?.mem == 2.5,
                  "parses pid/cpu/mem")
            check(stats[497]?.ppid == 1 && stats[1]?.command == "/sbin/launchd",
                  "parses ppid/comm")
            check(stats[1] != nil && stats[999] == nil, "skips malformed lines")
            let chain = ProcessService.ancestorChain(of: 497, stats: stats)
            check(chain.first?.pid == 1, "ancestor chain reaches launchd")

            // MARK: NettopProvider.parse

            section("NettopProvider.parse")

            let netOut = "                                              bytes_in  bytes_out\nnode.836   1000   500\n   tcp4 *:3000<->*:*   10   20\n   tcp4 127.0.0.1:5555<->1.2.3.4:443   700   300\nbad.line x y\nmDNSResponder.208   9000   700\n"
            let net = NettopProvider.parse(netOut)
            check(net.perPid[836]?.bytesIn == 1000 && net.perPid[836]?.bytesOut == 500,
                  "parses pid and byte counters")
            check(net.perPid[208] != nil && net.perPid[999] == nil,
                  "skips malformed nettop lines")
            let k = NettopProvider.ConnKey(pid: 836, localPort: 5555, remotePort: 443)
            check(net.perConn[k]?.bytesIn == 700, "parses per-connection counters")
            let listenerKey = NettopProvider.ConnKey(pid: 836, localPort: 3000, remotePort: 0)
            check(net.perConn[listenerKey] != nil, "wildcard remote → port 0 key")

            // MARK: DockerProvider.parse

            section("DockerProvider.parse")

            let dockerOut = "a1b2c3|postgres:16|db|0.0.0.0:5432->5432/tcp, :::5432->5432/tcp\n" +
                "d4e5f6|redis:7|cache|127.0.0.1:6379->6379/tcp\n" +
                "zzz|internal-only|worker|\n"
            let docker = DockerProvider.parse(dockerOut)
            check(docker.containers.count == 3, "parses container rows")
            check(docker.byPort[5432]?.image == "postgres:16", "maps host port to container")
            check(docker.byPort[6379]?.name == "cache", "localhost binding parsed")
            check(docker.byPort[80] == nil, "container-only ports not mapped")

            // MARK: LsofProvider (live)

            section("LsofProvider (live)")

            if let live = try? LsofProvider().snapshot() {
                check(!live.isEmpty, "found \(live.count) listeners on this machine")
            } else {
                check(false, "lsof snapshot failed")
            }

            print(failures == 0 ? "\nAll tests passed" : "\n\(failures) test(s) failed")
            exit(failures == 0 ? 0 : 1)
        }
    }
}
