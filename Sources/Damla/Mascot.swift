import AppKit
import SwiftUI

/// Damla's own mascot: a little water drop with a face that acts out what an agent is doing. Working, it hops
/// and glances left and right as if typing, blinking now and then; waiting, it turns amber, looks up wide-eyed
/// and waves its arm; done, it smiles with a sparkle; failed, it looks sad; idle, calm; out of date, asleep.
/// Only working and waiting move, and that motion runs in Core Animation (`MascotLoop`), so it costs the app
/// nothing per frame; every other phase is a still drawing.
///
/// Everything is drawn in a 100 × 100 box scaled to `size` (the same geometry as the website's mascot and the
/// app icon): a full drop whose tip leans a little to the right, lit from the top left, with light caught at
/// the bottom of the water, a curved glint, eyes with a catchlight and a touch of coral on the cheeks.
struct DropletMascot: View {
    let phase: AgentPhase
    var size: CGFloat = 22
    @Environment(\.mascotStill) private var still

    var live: Bool { phase == .working || phase == .waiting }

    var body: some View {
        Group {
            if live && !still && !Theme.reduceMotion { MascotLoop(mascot: self) }
            else { figure(at: 0) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    var color: Color {
        switch phase {
        case .working, .done: return Theme.agent
        case .waiting: return Theme.amber
        case .failed: return Theme.red
        case .interrupted: return Color(red: 0.62, green: 0.72, blue: 0.9)
        case .idle: return Color(red: 0.66, green: 0.78, blue: 0.94)
        case .stale: return Color(white: 0.62)
        }
    }

    /// The whole drop at time `t`; the still phases draw it at 0. `MascotLoop` animates the same pieces.
    @ViewBuilder func figure(at t: Double) -> some View {
        let s = size
        // Body motion: hop while working, sway while waiting.
        let hop = phase == .working ? abs(sin(t * 5.2)) : 0
        let squash = phase == .working ? 1 - 0.07 * (1 - hop) : 1
        let sway = phase == .waiting ? sin(t * 3.2) * 7 : 0
        ZStack {
            drop
            face(at: t)
            if phase == .waiting { hand(at: t) }
        }
        .frame(width: s, height: s)
        .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
        .offset(y: -hop * s * 0.08)
        .rotationEffect(.degrees(sway), anchor: .bottom)
    }

    @ViewBuilder private func face(at t: Double) -> some View {
        switch phase {
        case .done, .failed, .stale, .interrupted:
            Canvas { ctx, _ in stillFace(&ctx) }.frame(width: size, height: size)
        default:
            // a blink at the end of each 3.3 s, so a still drawing (t = 0) has its eyes open
            let blink = phase == .working && t.truncatingRemainder(dividingBy: 3.3) > 3.17
            let glance = phase == .working ? sin(t * 9) * eyeSize * 0.22 : 0
            ZStack {
                eyes(blink: blink).offset(x: glance, y: eyesCenter)
                mouth
            }
        }
    }

    // MARK: Geometry (a 100 × 100 box)

    private var k: CGFloat { size / 100 }
    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    private var ink: Color { Color(red: 0.06, green: 0.075, blue: 0.11).opacity(0.86) }
    private func line(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: max(0.7, width * k), lineCap: .round, lineJoin: .round) }

    /// The drop: full at the bottom, its tip leaning a little to the right.
    static func bodyPath(scale k: CGFloat) -> Path {
        var path = Path()
        let q = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * k, y: y * k) }
        path.move(to: q(55, 3))
        path.addCurve(to: q(86, 63), control1: q(61, 19), control2: q(86, 38))
        path.addCurve(to: q(50, 98), control1: q(86, 83), control2: q(70, 98))
        path.addCurve(to: q(14, 63), control1: q(30, 98), control2: q(14, 83))
        path.addCurve(to: q(55, 3), control1: q(14, 39), control2: q(40, 22))
        path.closeSubpath()
        return path
    }

    /// A 4-point sparkle.
    private func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        var path = Path()
        path.move(to: p(x, y - r))
        path.addQuadCurve(to: p(x + r, y), control: p(x, y))
        path.addQuadCurve(to: p(x, y + r), control: p(x, y))
        path.addQuadCurve(to: p(x - r, y), control: p(x, y))
        path.addQuadCurve(to: p(x, y - r), control: p(x, y))
        return path
    }

    // MARK: Pieces shared by the still figure and `MascotLoop`

    var eyeSize: CGFloat { size * 0.11 }
    /// Vertical offset of the eyes from the drop's centre.
    var eyesCenter: CGFloat { size * (phase == .waiting ? 0.12 : 0.14) }

    /// Both eyes in a band centred on them, so a blink squashes them about their own middle.
    func eyes(blink: Bool) -> some View {
        let wide = phase == .waiting, band = size * 0.24, k = self.k
        return Canvas { ctx, _ in
            for x: CGFloat in [39, 61] {
                let rx = (wide ? 6.2 : 5.2) * k, ry = (wide ? 8 : 6.6) * k * (blink ? 0.12 : 1)
                let cx = x * k, cy = band / 2
                ctx.fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)), with: .color(ink))
                if !blink {
                    let r = rx * 0.36
                    ctx.fill(Path(ellipseIn: CGRect(x: cx + rx * 0.38 - r, y: cy - ry * 0.42 - r, width: r * 2, height: r * 2)), with: .color(.white))
                }
            }
        }
        .frame(width: size, height: band)
    }

    /// The mouth of the open-eyed faces: a small "o" while waiting, a focused line while working, a smile at rest.
    var mouth: some View {
        Canvas { ctx, _ in
            var path = Path()
            switch phase {
            case .waiting:
                path.addEllipse(in: CGRect(x: (50 - 3.6) * k, y: (80 - 4.6) * k, width: 7.2 * k, height: 9.2 * k))
            case .working:
                path.move(to: p(46, 78)); path.addQuadCurve(to: p(56, 78), control: p(51, 81))
            default:
                path.move(to: p(43, 76)); path.addQuadCurve(to: p(57, 76), control: p(50, 83))
            }
            ctx.stroke(path, with: .color(ink), style: line(phase == .waiting ? 3.2 : 3.4))
        }
        .frame(width: size, height: size)
    }

    /// The drop itself with its light, glint and cheeks, no eyes or mouth.
    var drop: some View {
        let c = color, k = self.k, cheeks = ![.failed, .stale, .interrupted].contains(phase), waiting = phase == .waiting
        return Canvas { ctx, _ in
            let body = Self.bodyPath(scale: k)
            // Light from the top left, deeper water at the bottom right.
            ctx.fill(body, with: .linearGradient(Gradient(stops: [
                .init(color: c.shaded(0.35), location: 0), .init(color: c, location: 0.55), .init(color: c.shaded(-0.2), location: 1)
            ]), startPoint: p(30, 10), endPoint: p(70, 100)))
            // The bottom catches light through the water.
            var inner = ctx
            inner.clip(to: body)
            inner.fill(Path(CGRect(x: 0, y: 60 * k, width: 100 * k, height: 40 * k)),
                       with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]), center: p(50, 108), startRadius: 4 * k, endRadius: 34 * k))
            ctx.stroke(body, with: .color(.white.opacity(0.4)), lineWidth: max(0.5, 1.6 * k))
            // Glint: a curved stroke on the upper left and a dot above it.
            var glint = Path()
            for i in 0...12 {
                let a = Double.pi * (1.08 + 0.24 * Double(i) / 12)
                let point = CGPoint(x: (50 + 27 * cos(a)) * k, y: (63 + 27 * sin(a)) * k)
                if i == 0 { glint.move(to: point) } else { glint.addLine(to: point) }
            }
            ctx.stroke(glint, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: max(0.6, 4.6 * k), lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: (29 - 2.4) * k, y: (36 - 2.4) * k, width: 4.8 * k, height: 4.8 * k)), with: .color(.white.opacity(0.85)))
            // A touch of the cover coral on the cheeks (redder while it waits for you).
            if cheeks {
                let blush = waiting ? Color(red: 0.96, green: 0.47, blue: 0.35).opacity(0.4) : Color(red: 0.96, green: 0.63, blue: 0.55).opacity(0.55)
                for x: CGFloat in [30, 70] {
                    ctx.fill(Path(ellipseIn: CGRect(x: (x - 5.4) * k, y: (75 - 3.2) * k, width: 10.8 * k, height: 6.4 * k)), with: .color(blush))
                }
            }
        }
        .frame(width: size, height: size)
    }

    /// The faces that do not move: done, failed, stopped and asleep.
    private func stillFace(_ ctx: inout GraphicsContext) {
        switch phase {
        case .done:
            var happy = Path()
            for x: CGFloat in [39, 61] { happy.move(to: p(x - 6, 66)); happy.addQuadCurve(to: p(x + 6, 66), control: p(x, 57)) }
            ctx.stroke(happy, with: .color(ink), style: line(3.8))
            var grin = Path()
            grin.move(to: p(41, 76)); grin.addQuadCurve(to: p(59, 76), control: p(50, 87)); grin.closeSubpath()
            ctx.fill(grin, with: .color(ink))
            ctx.fill(star(84, 18, 9), with: .color(.white))
            ctx.fill(star(93, 33, 4.5), with: .color(.white))
        case .failed:
            var brows = Path()
            brows.move(to: p(33, 66)); brows.addLine(to: p(45, 60))
            brows.move(to: p(55, 60)); brows.addLine(to: p(67, 66))
            ctx.stroke(brows, with: .color(ink), style: line(3.6))
            for x: CGFloat in [39, 61] {
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 4) * k, y: (68 - 4.6) * k, width: 8 * k, height: 9.2 * k)), with: .color(ink))
            }
            var frown = Path()
            frown.move(to: p(43, 82)); frown.addQuadCurve(to: p(57, 82), control: p(50, 76))
            ctx.stroke(frown, with: .color(ink), style: line(3.4))
        default:   // stale, interrupted: eyes closed
            var shut = Path()
            for x: CGFloat in [39, 61] { shut.move(to: p(x - 6, 65)); shut.addQuadCurve(to: p(x + 6, 65), control: p(x, 69)) }
            shut.move(to: p(46, 79)); shut.addLine(to: p(54, 79))
            ctx.stroke(shut, with: .color(ink), style: line(3.4))
            if phase == .stale {
                ctx.draw(Text(verbatim: "z").font(.system(size: max(5, 15 * k), weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.9)), at: p(84, 26))
                ctx.draw(Text(verbatim: "z").font(.system(size: max(4, 10 * k), weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.9)), at: p(93, 14))
            }
        }
    }

    // MARK: The waving arm (waiting)

    /// Raised beside the drop while it waits for an answer, in the drop's own colour. It turns about its
    /// shoulder, the bottom centre of this frame.
    private func hand(at t: Double) -> some View {
        handSymbol
            .rotationEffect(.degrees(sin(t * 7) * 16 + 12), anchor: .bottom)
            .offset(x: handOffset.width, y: handOffset.height)
    }
    var handSymbol: some View {
        let s = size, c = color
        return Canvas { ctx, _ in
            var arm = Path()
            // short and stout, so it still reads as a raised hand at the notch's 22 pt
            arm.move(to: CGPoint(x: 0.25 * s, y: 0.42 * s))
            arm.addQuadCurve(to: CGPoint(x: 0.38 * s, y: 0.2 * s), control: CGPoint(x: 0.37 * s, y: 0.36 * s))
            ctx.stroke(arm, with: .color(c.shaded(-0.06)), style: StrokeStyle(lineWidth: 0.13 * s, lineCap: .round))
            let palm = Path(ellipseIn: CGRect(x: 0.295 * s, y: 0.075 * s, width: 0.17 * s, height: 0.17 * s))
            ctx.fill(palm, with: .color(c))
            ctx.stroke(palm, with: .color(.black.opacity(0.18)), lineWidth: max(0.4, 0.012 * s))
        }
        .frame(width: s * 0.5, height: s * 0.42)
    }
    /// Where the arm's frame sits: its bottom centre on the drop's right shoulder (80, 64 in the box).
    var handOffset: CGSize { CGSize(width: size * 0.3, height: -size * 0.07) }
}

extension Color {
    /// Lighter (k > 0, toward white) or darker (k < 0, toward black) in sRGB, like the website's ebru shades.
    func shaded(_ k: Double) -> Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        if k < 0 { r *= 1 + k; g *= 1 + k; b *= 1 + k }
        else { r += (1 - r) * k; g += (1 - g) * k; b += (1 - b) * k }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: c.alphaComponent)
    }
}
