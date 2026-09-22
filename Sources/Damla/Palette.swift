import AppKit

enum Palette {
    /// A saturated, mid-brightness color that stands for the artwork, or nil for flat or grey images.
    /// Picks the hue bucket carrying the most colorful pixels, then normalises so the glow is neither
    /// muddy nor neon. Runs on a 24×24 downsample, so it is cheap enough for every track change.
    static func accent(for image: NSImage) -> NSColor? {
        let side = 24
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let binCount = 24
        var weights = [Double](repeating: 0, count: binCount)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: binCount)
        for index in 0..<(side * side) {
            let r = Double(pixels[index * 4]) / 255, g = Double(pixels[index * 4 + 1]) / 255, b = Double(pixels[index * 4 + 2]) / 255
            let (h, s, v) = hsv(r, g, b)
            let weight = pow(s, 1.4) * (1 - abs(v - 0.62))
            guard weight > 0.02 else { continue }
            let bin = min(binCount - 1, Int(h * Double(binCount)))
            weights[bin] += weight
            sums[bin].r += r * weight; sums[bin].g += g * weight; sums[bin].b += b * weight
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0.6 else { return nil }
        let w = weights[best]
        let (h, s, v) = hsv(sums[best].r / w, sums[best].g / w, sums[best].b / w)
        return NSColor(hue: h, saturation: min(0.85, max(0.5, s)), brightness: min(0.9, max(0.6, v)), alpha: 1)
    }

    private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        let v = maxC
        let s = maxC > 0 ? delta / maxC : 0
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = (g - b) / delta }
            else if maxC == g { h = 2 + (b - r) / delta }
            else { h = 4 + (r - g) / delta }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, s, v)
    }
}
