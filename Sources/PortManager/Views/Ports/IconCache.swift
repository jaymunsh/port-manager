import AppKit

/// Lazily resolves the owning app's icon for a pid (via its executable path).
@MainActor
final class IconCache {
    static let shared = IconCache()

    private var cache: [pid_t: NSImage] = [:]

    func icon(for pid: pid_t) -> NSImage {
        if let image = cache[pid] { return image }
        var path = ProcessService().executablePath(for: pid)
        // Executables inside an .app bundle inherit the app's icon, not the
        // generic binary icon — resolve to the bundle for a recognizable look.
        if let range = path.range(of: ".app/") {
            path = String(path[..<range.lowerBound]) + ".app"
        }
        let image = NSWorkspace.shared.icon(forFile: path.isEmpty ? "/usr/bin" : path)
        image.size = NSSize(width: 16, height: 16)
        cache[pid] = image
        return image
    }
}
