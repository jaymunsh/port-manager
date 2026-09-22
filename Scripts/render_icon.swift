import AppKit

// Renders the app icon: rounded-rect gradient + white "network" SF Symbol.
// Usage: swift Scripts/render_icon.swift <output.png>

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "/tmp/portmanager-icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset: CGFloat = 60
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let clip = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.70, alpha: 1)
])!
gradient.draw(in: clip, angle: -90)

if let symbol = NSImage(systemSymbolName: "network", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let tinted = symbol.withSymbolConfiguration(config) {
        let s = tinted.size
        let r = NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 + 10,
                       width: s.width, height: s.height)
        clip.addClip()
        tinted.draw(in: r)
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
