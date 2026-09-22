import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let rect = NSRect(x: 74, y: 74, width: 876, height: 876)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 206, yRadius: 206)
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.28); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -15)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.23, alpha: 1).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(calibratedRed: 0.29, green: 0.47, blue: 0.49, alpha: 1), NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.22, alpha: 1)])!.draw(in: shape, angle: -60)
    NSColor.white.withAlphaComponent(0.24).setStroke(); shape.lineWidth = 3; shape.stroke()
    let drop = NSBezierPath()
    drop.move(to: NSPoint(x: 510, y: 780))
    drop.curve(to: NSPoint(x: 286, y: 390), controlPoint1: NSPoint(x: 460, y: 700), controlPoint2: NSPoint(x: 286, y: 510))
    drop.curve(to: NSPoint(x: 738, y: 390), controlPoint1: NSPoint(x: 286, y: 116), controlPoint2: NSPoint(x: 738, y: 116))
    drop.curve(to: NSPoint(x: 510, y: 780), controlPoint1: NSPoint(x: 738, y: 510), controlPoint2: NSPoint(x: 560, y: 700))
    NSGradient(colors: [NSColor(calibratedRed: 0.86, green: 1, blue: 0.94, alpha: 1), NSColor(calibratedRed: 0.39, green: 0.72, blue: 0.68, alpha: 1)])!.draw(in: drop, angle: -70)
    NSColor.white.withAlphaComponent(0.6).setStroke(); drop.lineWidth = 3; drop.stroke()
    let highlight = NSBezierPath()
    highlight.move(to: NSPoint(x: 372, y: 421)); highlight.curve(to: NSPoint(x: 449, y: 290), controlPoint1: NSPoint(x: 355, y: 352), controlPoint2: NSPoint(x: 392, y: 299))
    highlight.lineCapStyle = .round; highlight.lineWidth = 22; NSColor.white.withAlphaComponent(0.62).setStroke(); highlight.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: destination.appendingPathComponent(name)) }
}
