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

    // Graphite tile with a soft top lift, matching AppTheme's dark background layers.
    NSGradient(
        starting: NSColor(srgbRed: 0x22 / 255, green: 0x25 / 255, blue: 0x2A / 255, alpha: 1),
        ending: NSColor(srgbRed: 0x0D / 255, green: 0x0E / 255, blue: 0x10 / 255, alpha: 1)
    )!.draw(in: shape, angle: -90)

    // Faint chartreuse glow from the top-right corner.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(
        starting: NSColor(srgbRed: 0xC6 / 255, green: 0xF3 / 255, blue: 0x5E / 255, alpha: 0.16),
        ending: NSColor(srgbRed: 0xC6 / 255, green: 0xF3 / 255, blue: 0x5E / 255, alpha: 0)
    )!.draw(fromCenter: NSPoint(x: tile.maxX, y: tile.maxY), radius: 0,
            toCenter: NSPoint(x: tile.maxX, y: tile.maxY), radius: tile.width * 0.9, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Hairline border.
    let inner = NSBezierPath(
        roundedRect: tile.insetBy(dx: size / 512, dy: size / 512),
        xRadius: tile.width * 0.225, yRadius: tile.width * 0.225
    )
    inner.lineWidth = max(size / 256, 0.5)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    inner.stroke()

    let configuration = NSImage.SymbolConfiguration(pointSize: tile.width * 0.5, weight: .medium)
        .applying(.init(paletteColors: [NSColor(srgbRed: 0xC6 / 255, green: 0xF3 / 255, blue: 0x5E / 255, alpha: 1)]))
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
