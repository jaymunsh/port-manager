import SwiftUI

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
} else {
    PortManagerApp.main()
}
