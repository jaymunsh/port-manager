import Foundation

enum ByteFormat {
    /// Compact rate: "0", "940", "42K", "1.2M", "3.4G"
    static func rate(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case ..<1: return "0"
        case ..<1_000: return String(format: "%.0f", bytesPerSec)
        case ..<1_000_000: return String(format: "%.0fK", bytesPerSec / 1_000)
        case ..<1_000_000_000: return String(format: "%.1fM", bytesPerSec / 1_000_000)
        default: return String(format: "%.1fG", bytesPerSec / 1_000_000_000)
        }
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
