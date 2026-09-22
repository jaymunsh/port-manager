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
                          proto: .tcp, address: "*", port: port)
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
            check(connected?.port == 5555, "takes local side of connected socket")

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
