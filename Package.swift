// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortManager",
    platforms: [.macOS(.v15)],
    targets: [
        // Single executable; self-tests run inside the binary via `--selftest`
        // (CLT ships no usable `swift test` runner).
        .executableTarget(
            name: "PortManager",
            path: "Sources/PortManager",
            linkerSettings: [.linkedFramework("CoreWLAN")]
        )
    ]
)
