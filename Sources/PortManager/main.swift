import SwiftUI

if CommandLine.arguments.contains("--selftest-shell-helper") {
    SelfTest.shellStress()
} else if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in await SelfTest.run() }
    RunLoop.main.run()
} else {
    PortManagerApp.main()
}
