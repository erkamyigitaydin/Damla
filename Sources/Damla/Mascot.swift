import SwiftUI

/// Damla's own mascot: a little water drop with a face that acts out what an agent is doing. Working, it hops
/// and glances left and right as if typing, blinking now and then; waiting, it turns amber, looks up wide-eyed
/// and waves; done, it smiles with a sparkle; failed, it looks sad; idle, calm; out of date, asleep. It only
/// animates while working or waiting, so a quiet notch costs nothing.
struct DropletMascot: View {
    let phase: AgentPhase
    var size: CGFloat = 22

    private var live: Bool { phase == .working || phase == .waiting }

    var body: some View {
        // The tiny notch copy runs at the equalizer's pace; the big card a little smoother.
        TimelineView(.animation(minimumInterval: size < 30 ? 1.0 / 12 : 1.0 / 24, paused: Theme.reduceMotion || !live)) { context in
            figure(at: live && !Theme.reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch phase {
        case .working, .done: return Theme.accent
        case .waiting: return Theme.amber
        case .failed: return Color(red: 1, green: 0.47, blue: 0.47)
        case .interrupted: return Color(red: 0.62, green: 0.72, blue: 0.9)
        case .idle: return Theme.accent.opacity(0.75)
        case .stale: return Color(white: 0.62)
        }
    }

    @ViewBuilder private func figure(at t: Double) -> some View {
        let s = size
        // Body motion: hop while working, sway while waiting.
        let hop = phase == .working ? abs(sin(t * 5.2)) : 0
        let squash = phase == .working ? 1 - 0.07 * (1 - hop) : 1
        let sway = phase == .waiting ? sin(t * 3.2) * 7 : 0
        ZStack {
            DropShape()
                .fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                .overlay(DropShape().stroke(.white.opacity(0.35), lineWidth: max(0.5, s * 0.025)))
            // Glint on the upper left, like light on water.
            Ellipse().fill(.white.opacity(0.55)).frame(width: s * 0.13, height: s * 0.2)
                .rotationEffect(.degrees(-25)).offset(x: -s * 0.17, y: s * 0.02)
            face(at: t)
            if phase == .waiting { hand(at: t) }
            if phase == .done { sparkle }
            if phase == .stale {
                Text("z").font(.system(size: s * 0.3, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                    .offset(x: s * 0.38, y: -s * 0.32)
            }
        }
        .frame(width: s, height: s)
        .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
        .offset(y: -hop * s * 0.08)
        .rotationEffect(.degrees(sway), anchor: .bottom)
    }

    @ViewBuilder private func face(at t: Double) -> some View {
        let s = size
        let ink = Color.black.opacity(0.78)
        let eye = s * 0.11
        let blink = phase == .working && t.truncatingRemainder(dividingBy: 3.3) < 0.13
        let glance = phase == .working ? sin(t * 9) * eye * 0.22 : 0
        let eyeY = s * 0.16
        ZStack {
            switch phase {
            case .done:
                HStack(spacing: s * 0.14) { HappyEye().stroke(ink, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round)).frame(width: eye * 1.3, height: eye * 0.8) ; HappyEye().stroke(ink, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round)).frame(width: eye * 1.3, height: eye * 0.8) }
                    .offset(y: eyeY)
                Smile(depth: 0.9).stroke(ink, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round)).frame(width: s * 0.22, height: s * 0.08).offset(y: eyeY + s * 0.14)
            case .failed:
                HStack(spacing: s * 0.14) {
                    Capsule().fill(ink).frame(width: eye * 1.2, height: s * 0.04).rotationEffect(.degrees(20))
                    Capsule().fill(ink).frame(width: eye * 1.2, height: s * 0.04).rotationEffect(.degrees(-20))
                }.offset(y: eyeY)
                Smile(depth: -0.8).stroke(ink, style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round)).frame(width: s * 0.2, height: s * 0.07).offset(y: eyeY + s * 0.16)
            case .stale, .interrupted:
                HStack(spacing: s * 0.16) {
                    Capsule().fill(ink).frame(width: eye * 1.1, height: s * 0.035)
                    Capsule().fill(ink).frame(width: eye * 1.1, height: s * 0.035)
                }.offset(y: eyeY)
                Capsule().fill(ink).frame(width: s * 0.1, height: s * 0.03).offset(y: eyeY + s * 0.14)
            default:
                let wide = phase == .waiting ? 1.3 : 1
                HStack(spacing: s * 0.14) {
                    Ellipse().fill(ink).frame(width: eye * wide, height: blink ? eye * 0.15 : eye * 1.25 * wide)
                    Ellipse().fill(ink).frame(width: eye * wide, height: blink ? eye * 0.15 : eye * 1.25 * wide)
                }
                .offset(x: glance, y: eyeY + (phase == .working ? eye * 0.3 : phase == .waiting ? -eye * 0.25 : 0))
                if phase == .waiting {
                    Ellipse().stroke(ink, lineWidth: s * 0.04).frame(width: s * 0.08, height: s * 0.1).offset(y: eyeY + s * 0.17)
                } else {
                    Smile(depth: phase == .working ? 0.35 : 0.6).stroke(ink, style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
                        .frame(width: s * 0.16, height: s * 0.05).offset(y: eyeY + s * 0.15)
                }
            }
        }
    }

    /// A small raised hand waving beside the drop while it waits for an answer.
    private func hand(at t: Double) -> some View {
        let s = size
        let wave = sin(t * 7) * 16
        return Image(systemName: "hand.raised.fill").font(.system(size: s * 0.3, weight: .semibold))
            .foregroundStyle(color).shadow(color: .black.opacity(0.35), radius: s * 0.02)
            .rotationEffect(.degrees(wave + 12), anchor: .bottom)
            .offset(x: s * 0.46, y: -s * 0.12)
    }

    private var sparkle: some View {
        Image(systemName: "sparkle").font(.system(size: size * 0.28, weight: .bold)).foregroundStyle(.white)
            .offset(x: size * 0.4, y: -size * 0.34)
    }
}

/// A teardrop: pointed on top, round at the bottom.
struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02))
        path.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.98),
                      control1: CGPoint(x: x + w * 1.02, y: y + h * 0.5), control2: CGPoint(x: x + w * 0.96, y: y + h * 0.98))
        path.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02),
                      control1: CGPoint(x: x + w * 0.04, y: y + h * 0.98), control2: CGPoint(x: x - w * 0.02, y: y + h * 0.5))
        path.closeSubpath()
        return path
    }
}

/// "^" shaped closed eye for a happy face.
private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return path
    }
}

/// A mouth: positive depth smiles, negative frowns.
private struct Smile: Shape {
    var depth: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = depth >= 0 ? rect.minY : rect.maxY
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: y), control: CGPoint(x: rect.midX, y: y + rect.height * 2 * depth))
        return path
    }
}
