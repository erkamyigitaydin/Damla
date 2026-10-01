import AppKit

// Damla's app icon: a graphite screen with the black notch at its top, and the mascot (the same drop as
// DropletMascot, at rest) just melted out of it, its tip still touching the notch.
// Run: swift Resources/MakeIcon.swift <dir>.iconset && iconutil -c icns <dir>.iconset -o Resources/AppIcon.icns
// Drawn in a 1024 canvas with y growing downward; the mascot uses its own 100 × 100 box, like Mascot.swift.

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor { rgb(CGFloat(v >> 16 & 255) / 255, CGFloat(v >> 8 & 255) / 255, CGFloat(v & 255) / 255, a) }
/// Toward white (k > 0) or black (k < 0), as `Color.shaded` does.
func shade(_ c: CGColor, _ k: CGFloat) -> CGColor {
    let p = c.components!
    return k < 0 ? rgb(p[0] * (1 + k), p[1] * (1 + k), p[2] * (1 + k)) : rgb(p[0] + (1 - p[0]) * k, p[1] + (1 - p[1]) * k, p[2] + (1 - p[2]) * k)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
}

func draw(_ ctx: CGContext) {
    let squircle = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil)
    // The screen, lifted off the Dock by a soft shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 40, color: rgb(0.12, 0.09, 0.04, 0.3))
    ctx.addPath(squircle); ctx.setFillColor(hex(0x1a1c21)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    ctx.drawLinearGradient(gradient([hex(0x2c3038), hex(0x0c0d10)], [0, 1]), start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

    // The mascot: tip at (512, 190), 600 px tall.
    ctx.saveGState()
    ctx.translateBy(x: 182, y: 172)
    ctx.scaleBy(x: 6, y: 6)
    let c = rgb(0.66, 0.78, 0.94)   // the drop at rest (idle)
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 55, y: 3))
    body.addCurve(to: CGPoint(x: 86, y: 63), control1: CGPoint(x: 61, y: 19), control2: CGPoint(x: 86, y: 38))
    body.addCurve(to: CGPoint(x: 50, y: 98), control1: CGPoint(x: 86, y: 83), control2: CGPoint(x: 70, y: 98))
    body.addCurve(to: CGPoint(x: 14, y: 63), control1: CGPoint(x: 30, y: 98), control2: CGPoint(x: 14, y: 83))
    body.addCurve(to: CGPoint(x: 55, y: 3), control1: CGPoint(x: 14, y: 39), control2: CGPoint(x: 40, y: 22))
    body.closeSubpath()
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(gradient([shade(c, 0.35), c, shade(c, -0.2)], [0, 0.55, 1]), start: CGPoint(x: 30, y: 10), end: CGPoint(x: 70, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.clip(to: CGRect(x: 0, y: 60, width: 100, height: 40))
    ctx.drawRadialGradient(gradient([rgb(1, 1, 1, 0.55), rgb(1, 1, 1, 0)], [0, 1]), startCenter: CGPoint(x: 50, y: 108), startRadius: 4, endCenter: CGPoint(x: 50, y: 108), endRadius: 34, options: [])
    ctx.restoreGState()
    ctx.addPath(body); ctx.setStrokeColor(rgb(1, 1, 1, 0.4)); ctx.setLineWidth(1.6); ctx.strokePath()
    // glint
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let glint = CGMutablePath()
    for i in 0...24 {
        let a = Double.pi * (1.08 + 0.24 * Double(i) / 24)
        let p = CGPoint(x: 50 + 27 * cos(a), y: 63 + 27 * sin(a))
        if i == 0 { glint.move(to: p) } else { glint.addLine(to: p) }
    }
    ctx.addPath(glint); ctx.setStrokeColor(rgb(1, 1, 1, 0.85)); ctx.setLineWidth(4.6); ctx.strokePath()
    ctx.addPath(ellipse(29, 36, 2.4, 2.4)); ctx.setFillColor(rgb(1, 1, 1, 0.85)); ctx.fillPath()
    // cheeks
    for x: CGFloat in [30, 70] { ctx.addPath(ellipse(x, 75, 5.4, 3.2)) }
    ctx.setFillColor(rgb(0.96, 0.63, 0.55, 0.55)); ctx.fillPath()
    // eyes with their catchlights
    let ink = rgb(0.06, 0.075, 0.11, 0.86)
    for x: CGFloat in [39, 61] {
        ctx.addPath(ellipse(x, 64, 5.2, 6.6)); ctx.setFillColor(ink); ctx.fillPath()
        ctx.addPath(ellipse(x + 5.2 * 0.38, 64 - 6.6 * 0.42, 5.2 * 0.36, 5.2 * 0.36)); ctx.setFillColor(rgb(1, 1, 1)); ctx.fillPath()
    }
    // smile
    ctx.move(to: CGPoint(x: 43, y: 76)); ctx.addQuadCurve(to: CGPoint(x: 57, y: 76), control: CGPoint(x: 50, y: 83))
    ctx.setStrokeColor(ink); ctx.setLineWidth(3.4); ctx.strokePath()
    ctx.restoreGState()

    // The notch, with the inverted fillets where it meets the top edge.
    let notch = CGMutablePath(), x0: CGFloat = 352, x1: CGFloat = 672, top: CGFloat = 100, h: CGFloat = 100, r: CGFloat = 46, f: CGFloat = 26
    notch.move(to: CGPoint(x: x0 - f, y: top))
    notch.addQuadCurve(to: CGPoint(x: x0, y: top + f), control: CGPoint(x: x0, y: top))
    notch.addLine(to: CGPoint(x: x0, y: top + h - r)); notch.addQuadCurve(to: CGPoint(x: x0 + r, y: top + h), control: CGPoint(x: x0, y: top + h))
    notch.addLine(to: CGPoint(x: x1 - r, y: top + h)); notch.addQuadCurve(to: CGPoint(x: x1, y: top + h - r), control: CGPoint(x: x1, y: top + h))
    notch.addLine(to: CGPoint(x: x1, y: top + f)); notch.addQuadCurve(to: CGPoint(x: x1 + f, y: top), control: CGPoint(x: x1, y: top))
    notch.closeSubpath()
    ctx.addPath(notch); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()
    // a thin rim of light around the screen
    ctx.addPath(squircle); ctx.setStrokeColor(rgb(1, 1, 1, 0.14)); ctx.setLineWidth(3); ctx.strokePath()
}

for size in [16, 32, 64, 128, 180, 256, 512, 1024] {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: scale, y: -scale)   // y down, as in the drawing
    draw(ctx)
    let data = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 180: names = []   // the website's apple-touch-icon, written next to the iconset
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: destination.appendingPathComponent(name)) }
    if size == 64 || size == 180 || size == 256 {
        try data.write(to: destination.deletingLastPathComponent().appendingPathComponent("damla-icon-\(size).png"))
    }
}
