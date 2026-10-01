import AppKit

/// Executable-path cache, bounded by NSCache. PIDs are resolved afresh so a
/// reused PID can never inherit a previous process's icon.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 256 }

    func icon(for pid: pid_t) -> NSImage {
        var path = ProcessService().identity(for: pid)?.executablePath ?? ""
        if let range = path.range(of: ".app/") {
            path = String(path[..<range.lowerBound]) + ".app"
        }
        if path.isEmpty { path = "/usr/bin" }
        let key = path as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        cache.setObject(image, forKey: key)
        return image
    }
}
