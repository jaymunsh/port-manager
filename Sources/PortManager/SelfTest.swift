import Foundation

/// In-binary test runner (`PortManager --selftest`).
/// CLT-only environments have no `swift test` runner, so assertions live here.
enum SelfTest {
    @MainActor
    static func run() async -> Never {
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
        let outbound = PortEntry(pid: 123, command: "curl", user: "u", fd: "1",
                                 proto: .tcp, address: "127.0.0.1", port: 8080,
                                 state: "ESTABLISHED", remote: "1.1.1.1:443")
        check(store.status(for: strict, entries: [outbound]) == .free,
              "outbound connections do not occupy a preset")

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
        let k = NettopProvider.ConnKey(pid: 836, localPort: 5555, remotePort: 443,
                                      localAddress: "127.0.0.1", remoteAddress: "1.2.3.4")
        check(net.perConn[k]?.bytesIn == 700, "parses per-connection counters")
        let listenerKey = NettopProvider.ConnKey(pid: 836, localPort: 3000, remotePort: 0)
        check(net.perConn[listenerKey] != nil, "wildcard remote → port 0 key")
        let separatePeers = NettopProvider.parse("node.123 1000 500\n" +
            " tcp4 127.0.0.1:5000<->1.1.1.1:443 100 20\n" +
            " tcp4 127.0.0.1:5000<->2.2.2.2:443 300 40\n")
        check(separatePeers.perConn.count == 2, "same ports with different peers remain distinct")
        let ipv6Net = NettopProvider.parse("node.123 1000 500\n tcp6 ::1.8080<->::1.60285 100 20\n")
        let ipv6Entry = PortEntry(pid: 123, command: "node", user: "u", fd: "1", proto: .tcp,
                                 address: "[::1]", port: 8080, state: "ESTABLISHED", remote: "[::1]:60285")
        check(ipv6Net.perConn[ipv6Entry.connKey]?.bytesIn == 100,
              "real nettop IPv6 dot-port endpoints match lsof")
        let idleNet = NettopProvider.parse("node.123 1000 500\n tcp4 *:8080<->*:*\n")
        check(idleNet.perConn[NettopProvider.ConnKey(pid: 123, localPort: 8080, remotePort: 0)]?.bytesIn == 0,
              "blank idle listener counters represent measured zero")
        let spacedName = NettopProvider.parse("Google Chrome.123 1000 500\n tcp4 127.0.0.1:8080<->1.1.1.1:443 100 20\n")
        check(spacedName.perPid[123]?.bytesIn == 1000 && spacedName.perConn.keys.first?.pid == 123,
              "process names containing spaces preserve PID attribution")
        let scopedNet = NettopProvider.parse("node.123 1000 500\n udp6 fe80::1%en0.8080<->fe80::2%en0.443 100 20\n")
        let scopedKey = NettopProvider.ConnKey(pid: 123, localPort: 8080, remotePort: 443,
                                              localAddress: "[fe80:0:0:0:0:0:0:1%en0]",
                                              remoteAddress: "fe80::2%en0", proto: "UDP")
        check(scopedNet.perConn[scopedKey]?.bytesIn == 100,
              "scoped IPv6 addresses normalize and preserve UDP transport")
        let missingConnected = NettopProvider.parse("node.123 1000 500\n tcp4 127.0.0.1:8080<->1.1.1.1:443\n")
        check(missingConnected.perConn.isEmpty, "missing connected counters do not invent a zero measurement")

        section("AlertStore.currentRate")
        let alerts = AlertStore()
        let rule = BandwidthAlert(name: "test", port: 8080, threshold: 150)
        let v4 = PortEntry(pid: 123, command: "node", user: "u", fd: "1",
                           proto: .tcp, address: "127.0.0.1", port: 8080, state: "LISTEN", remote: nil)
        let v6Listener = PortEntry(pid: 123, command: "node", user: "u", fd: "2",
                                  proto: .tcp, address: "[::1]", port: 8080, state: "LISTEN", remote: nil)
        check(alerts.currentRate(for: rule, entries: [v4, v6Listener],
                                netRates: [123: NetRate(inRate: 100, outRate: 0)], connRates: [:]) == 100,
              "dual-stack listeners count each PID once")
        check(alerts.currentRate(for: rule, entries: [v4],
                                netRates: [123: NetRate(inRate: 100, outRate: 0)],
                                connRates: [v4.connKey: NetRate(inRate: 0, outRate: 0)]) == 0,
              "measured zero does not fall back to process traffic")
        var idleTracker = RateTracker<NettopProvider.ConnKey>()
        _ = idleTracker.update(idleNet.perConn, at: 1)
        let idleRates = idleTracker.update(idleNet.perConn, at: 2)
        check(alerts.currentRate(for: rule, entries: [v4],
                                netRates: [123: NetRate(inRate: 1000, outRate: 500)],
                                connRates: idleRates) == 0,
              "blank nettop listener stays zero through rate tracking and alert evaluation")

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

        section("LsofProvider blockers (owned temporary file)")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try Data("selftest".utf8).write(to: file)
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: file) }
            let blockers = try LsofProvider().processesUsing(path: file.path)
            check(blockers.contains { $0.pid == getpid() && !$0.command.isEmpty },
                  "returns PID and command for a process holding a file")
        } catch {
            check(false, "blocker query failed: \(error)")
        }

        await ReliabilitySelfTest.run(check: check)
        print(failures == 0 ? "\nAll tests passed" : "\n\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func shellStress() -> Never {
        do {
            let result = try Shell.run("/usr/bin/perl", ["-e", "print STDERR 'e' x 262144; print STDOUT 'done';"], timeout: 3)
            exit(result.stdout == "done" && result.stderr.count == 262144 ? 0 : 1)
        } catch { exit(1) }
    }
}


/// Regression scenarios use isolated files and owned child processes only.
@MainActor
enum ReliabilitySelfTest {
    static func run(check: (Bool, String) -> Void) async {
        print("\nShell reliability")
        do {
            let helper = Process()
            helper.executableURL = Bundle.main.executableURL
            helper.arguments = ["--selftest-shell-helper"]
            try helper.run()
            let deadline = Foundation.ProcessInfo.processInfo.systemUptime + 5
            while helper.isRunning && Foundation.ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if helper.isRunning { _ = kill(helper.processIdentifier, SIGKILL) }
            helper.waitUntilExit()
            check(helper.terminationStatus == 0, "stderr flood completes without deadlock")
            let started = Foundation.ProcessInfo.processInfo.systemUptime
            do {
                _ = try Shell.run("/bin/sleep", ["10"], timeout: 0.1)
                check(false, "sleep must time out")
            } catch ShellError.timedOut {
                check(Foundation.ProcessInfo.processInfo.systemUptime - started < 2, "command timeout stops an owned child promptly")
            }
            do {
                _ = try Shell.run("/bin/echo", ["must not run"], isCancelled: { true })
                check(false, "cancelled commands must not launch")
            } catch ShellError.cancelled { check(true, "pre-launch cancellation is respected") }
            let worker = Task {
                try await Background.run { try Shell.run("/bin/sleep", ["10"]) }
            }
            try? await Task.sleep(for: .milliseconds(40))
            worker.cancel()
            do {
                _ = try await worker.value
                check(false, "detached collector should be cancelled")
            } catch ShellError.cancelled { check(true, "cancellation reaches a detached subprocess") }
        } catch { check(false, "shell regression: \(error)") }

        print("\nNetworkProvider parsing")
        let counters = NetworkProvider.parseLinkCounters("""
        Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        en0 1500 <Link#1> aa:bb:cc:dd:ee:ff 10 0 1000 20 0 2000 0
        utun0 1380 <Link#2> 30 0 3000 40 0 4000 0
        malformed row
        """)
        check(counters["en0"]?.bytesIn == 1000 && counters["en0"]?.bytesOut == 2000, "Ethernet byte columns")
        check(counters["utun0"]?.bytesIn == 3000 && counters["utun0"]?.bytesOut == 4000, "VPN byte columns without MAC")
        check(NetworkProvider.parseDNS("nameserver[0] : 2001:4860:4860::8888\nnameserver[1] : 1.1.1.1\nnameserver[2] : 1.1.1.1") == ["2001:4860:4860::8888", "1.1.1.1"], "IPv6 DNS is preserved and duplicates removed")
        check(NetworkProvider.parseGateway("default truncated") == nil, "truncated gateway row is ignored")

        print("\nHistoryService")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = HistoryService(directory: directory)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        history.append(ActivityEvent(date: yesterday, kind: .listener, message: "yesterday"))
        history.append(ActivityEvent(date: .now, kind: .listener, message: "today"))
        check(history.loadRecent(days: 7).count == 2, "history restores multiple days")
        check(history.loadRecent(days: 7, limit: 1).first?.message == "today", "history limit keeps newest events")
        history.clear()
        check(history.loadRecent(days: 7).isEmpty, "clearing history survives reload")

        print("\nProcess identity and eject safety")
        let service = ProcessService()
        check(service.isProtected(pid: -1, command: "node"), "nonpositive PIDs are protected")
        check(service.isProtected(pid: 123, command: "/System/Library/WindowServer"), "protection accepts executable paths")
        if let identity = service.identity(for: getpid()) {
            check(service.identity(for: getpid()) == identity, "native process identity is stable")
            var changed = identity
            changed.startMicroseconds += 1
            check(ProcessService.identityMatches(expected: changed, current: identity) == false,
                  "different creation time rejects a reused PID")
            check(ProcessService.identityMatches(expected: identity, current: nil) == false,
                  "unavailable identity fails closed")
            check(service.sendSignal(SIGTERM, to: identity) == .protectedProcess,
                  "service refuses to signal the self-test process")
        } else { check(false, "native process identity unavailable") }
        var ejectCalls = 0
        let blocked: Result<Void, DiskServiceError> = .failure(.operationFailed("busy"))
        let ejectFailure = await EjectOperation.perform(unmount: { blocked }, eject: {
            ejectCalls += 1
            return .success(())
        })
        if case .failure = ejectFailure { check(ejectCalls == 0, "failed unmount never proceeds to eject") }
        else { check(false, "unmount error is preserved") }
        var order: [String] = []
        let ejectSuccess = await EjectOperation.perform(unmount: {
            order.append("unmount")
            return .success(())
        }, eject: {
            order.append("eject")
            return .success(())
        })
        if case .success = ejectSuccess { check(order == ["unmount", "eject"], "eject waits for successful unmount") }
        else { check(false, "eject sequence should succeed") }

        print("\nRefresh coalescing and counter lifecycle")
        let gate = RefreshGate()
        var collections = 0, active = 0, maximumActive = 0
        let refresh: @MainActor () async -> Void = {
            collections += 1
            active += 1
            maximumActive = max(maximumActive, active)
            try? await Task.sleep(for: .milliseconds(30))
            active -= 1
        }
        async let first: Void = gate.run(refresh)
        try? await Task.sleep(for: .milliseconds(5))
        async let second: Void = gate.run(refresh)
        async let third: Void = gate.run(refresh)
        _ = await (first, second, third)
        check(collections == 2 && maximumActive == 1, "overlapping refreshes coalesce without parallel collectors")
        check(!gate.isRefreshing, "refresh gate returns to idle")
        let restartingGate = RefreshGate()
        var restartingActive = 0, restartingMaximum = 0
        let slowRefresh: @MainActor () async -> Void = {
            restartingActive += 1
            restartingMaximum = max(restartingMaximum, restartingActive)
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { continuation.resume() }
            }
            restartingActive -= 1
        }
        let abandoned = Task { await restartingGate.run(slowRefresh) }
        for _ in 0..<50 where restartingActive == 0 { try? await Task.sleep(for: .milliseconds(1)) }
        restartingGate.cancel()
        async let restarted: Void = restartingGate.run(slowRefresh)
        await abandoned.value
        _ = await restarted
        check(restartingMaximum == 1, "cancel and immediate restart remain serialized")
        var tracker = RateTracker<Int>()
        _ = tracker.update([1: .init(bytesIn: 100, bytesOut: 50)], at: 1)
        let rates = tracker.update([1: .init(bytesIn: 200, bytesOut: 70)], at: 3)
        check(rates[1]?.inRate == 50 && rates[1]?.outRate == 10, "counter deltas use elapsed monotonic time")
        _ = tracker.update([:], at: 4)
        check(tracker.count == 0, "disappeared counter keys are pruned")
        check(tracker.update([1: .init(bytesIn: 300, bytesOut: 80)], at: 5).isEmpty,
              "reappearing counters start a fresh baseline")
        let reset = tracker.update([1: .init(bytesIn: 1, bytesOut: 1)], at: 6)
        check(reset[1]?.total == 0, "reset counters do not spike")

        print("\nPreset monitoring")
        let presetStore = PresetStore(fileURL: directory.appendingPathComponent("presets.json"))
        let alertStore = AlertStore(fileURL: directory.appendingPathComponent("alerts.json"))
        let activity = ActivityStore(history: history)
        let listener = PortEntry(pid: 123, command: "python", user: "u", fd: "1", proto: .tcp,
                                 address: "*", port: 8080, state: "LISTEN", remote: nil)
        let portStore = PortStore(collector: { _, _ in PortSnapshot(entries: [listener], stats: [:]) })
        let monitor = MonitorEngine(allowNotifications: false)
        presetStore.add(PortPreset(name: "api", port: 8080, expectedCommand: "node"))
        monitor.start(ports: portStore, devices: DeviceStore(), presets: presetStore, activity: activity, alerts: alertStore)
        await portStore.refresh()
        check(activity.events.filter { $0.kind == .preset }.count == 1,
              "initial snapshot detects existing preset conflicts")
        await portStore.refresh()
        check(activity.events.filter { $0.kind == .preset }.count == 1,
              "unchanged snapshot does not repeat a conflict")
        presetStore.add(PortPreset(name: "second rule", port: 8080, expectedCommand: "ruby"))
        check(activity.events.filter { $0.kind == .preset }.count == 2,
              "adding a preset evaluates current listeners immediately")

        print("\nStore polling and stale results")
        let suite = "PortManager.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.0, forKey: "ports.refreshInterval")
        let optionsCount = TestCounter()
        let optionPorts = PortStore(defaults: defaults, collector: { udp, _ in
            _ = optionsCount.increment()
            usleep(50_000)
            let socket = PortEntry(pid: 123, command: "test", user: "u", fd: "1", proto: .tcp,
                                   address: "*", port: udp ? 9002 : 9001, state: "LISTEN", remote: nil)
            return PortSnapshot(entries: [socket], stats: [:])
        })
        var publishedPorts: [Int] = []
        optionPorts.onSnapshot { [weak optionPorts] in
            if let port = optionPorts?.entries.first?.port { publishedPorts.append(port) }
        }
        let optionRefresh = Task { await optionPorts.refresh() }
        for _ in 0..<100 where optionsCount.count == 0 { try? await Task.sleep(for: .milliseconds(2)) }
        optionPorts.includeUDP = true
        await optionRefresh.value
        check(publishedPorts == [9002] && optionsCount.count == 2,
              "old option results are discarded before latest options publish")
        optionPorts.stopPolling()

        let portCalls = TestCounter(), bandwidthCalls = TestCounter()
        let idlePorts = PortStore(defaults: defaults, collector: { _, _ in
            _ = portCalls.increment()
            return PortSnapshot(entries: [], stats: [:])
        }, bandwidthCollector: {
            _ = bandwidthCalls.increment()
            return NettopProvider.Result()
        }, dockerCollector: { DockerProvider.Snapshot(containers: [], byPort: [:], available: false) })
        idlePorts.startPolling()
        try? await Task.sleep(for: .milliseconds(50))
        check(portCalls.count == 0 && bandwidthCalls.count == 0, "paused ports and unused bandwidth spawn no collectors")
        await idlePorts.refresh()
        check(portCalls.count == 1, "manual refresh remains available while paused")
        let consumer = UUID()
        idlePorts.setBandwidthConsumer(consumer, active: true)
        for _ in 0..<100 where bandwidthCalls.count == 0 { try? await Task.sleep(for: .milliseconds(2)) }
        check(bandwidthCalls.count == 1, "visible port view enables bandwidth collection")
        idlePorts.setBandwidthConsumer(consumer, active: false)
        let beforeIdle = bandwidthCalls.count
        try? await Task.sleep(for: .milliseconds(30))
        check(bandwidthCalls.count == beforeIdle, "hiding the last port view stops bandwidth collection")
        idlePorts.bandwidthMonitoringEnabled = true
        for _ in 0..<100 where bandwidthCalls.count == beforeIdle { try? await Task.sleep(for: .milliseconds(2)) }
        check(bandwidthCalls.count == beforeIdle + 1, "enabled alert rules collect bandwidth without a view")
        idlePorts.stopPolling()

        let cancellationStarted = TestCounter()
        let cancelledPorts = PortStore(defaults: defaults, collector: { _, _ in
            _ = cancellationStarted.increment()
            _ = try Shell.run("/bin/sleep", ["10"])
            return PortSnapshot(entries: [listener], stats: [:])
        })
        let cancelledRefresh = Task { await cancelledPorts.refresh() }
        for _ in 0..<100 where cancellationStarted.count == 0 { try? await Task.sleep(for: .milliseconds(2)) }
        let cancelledAt = Foundation.ProcessInfo.processInfo.systemUptime
        cancelledPorts.stopPolling()
        await cancelledRefresh.value
        check(cancelledPorts.lastUpdated == nil && cancelledPorts.lastError == nil
                && Foundation.ProcessInfo.processInfo.systemUptime - cancelledAt < 2,
              "stopping a store cancels collection without publishing stale data")

        print("\nNetwork configuration cache")
        let configurationCalls = TestCounter()
        let interfaceState = TestInterfaces([NetInterface(name: "en0", displayName: "Ethernet", isUp: true,
                                                         isActive: true, ipv4: "10.0.0.1", bytesIn: 100, bytesOut: 200)])
        var time: TimeInterval = 1
        let network = NetworkStore(interfaceCollector: { interfaceState.get() }, configurationCollector: {
            _ = configurationCalls.increment()
            return NetworkConfiguration(gateway: "10.0.0.254", dns: ["1.1.1.1"])
        }, clock: { time })
        await network.refresh(forceConfiguration: false)
        time = 3
        await network.refresh(forceConfiguration: false)
        check(configurationCalls.count == 1, "polling reuses DNS/gateway configuration")
        time = 32
        await network.refresh(forceConfiguration: false)
        check(configurationCalls.count == 2, "network configuration expires after 30 seconds")
        await network.refresh()
        check(configurationCalls.count == 3, "manual network refresh bypasses the configuration cache")
        interfaceState.set([NetInterface(name: "en0", displayName: "Ethernet", isUp: true,
                                        isActive: true, ipv4: "10.0.0.2", bytesIn: 200, bytesOut: 300)])
        await network.refresh(forceConfiguration: false)
        check(configurationCalls.count == 4, "address changes invalidate the configuration cache")
        network.stopPolling()
    }
}

private final class TestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() -> Int { lock.withLock { value += 1; return value } }
}

private final class TestInterfaces: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [NetInterface]
    init(_ values: [NetInterface]) { self.values = values }
    func get() -> [NetInterface] { lock.withLock { values } }
    func set(_ values: [NetInterface]) { lock.withLock { self.values = values } }
}
