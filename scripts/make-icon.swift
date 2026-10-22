// Draws the app icon and writes packaging/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (only needed when the icon design changes)
import AppKit

let root = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 rounded square, centred.
    let inset = size * 100 / 1024
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(
        starting: NSColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1),
        ending: NSColor(red: 0.42, green: 0.27, blue: 0.86, alpha: 1)
    )!.draw(in: shape, angle: -70)

    let configuration = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "photo.stack", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let fit = tile.width * 0.56
        let scale = fit / max(symbol.size.width, symbol.size.height)
        let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        symbol.draw(in: NSRect(x: tile.midX - drawn.width / 2, y: tile.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let output = root.appending(path: "packaging/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
exit(iconutil.terminationStatus)
