import SwiftUI
import QuartzCore

// Looping notch animations handed to Core Animation. Once a keyframe loop is installed the render server
// plays it on its own, so the app does no work per frame. A TimelineView (or a per-tick implicit animation)
// instead re-runs SwiftUI's update and layout pass for the whole notch window on every tick; with the
// equalizer and an agent live on two screens that measured ~20% CPU with the panel closed.

/// A layer-hosting view whose loops are reinstalled whenever it (re)joins a window, because AppKit may drop
/// running animations when a view leaves the window.
class LoopLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { install() } }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); install() }
    /// Rebuilds sublayers and animations from the current properties.
    func install() {}

    /// A seamless loop through `value(t)` sampled evenly over `period` seconds.
    static func loop(_ keyPath: String, period: Double, samples: Int = 24, _ value: (Double) -> Double) -> CAKeyframeAnimation {
        loop(keyPath, period: period, samples: samples) { NSNumber(value: value($0)) as Any }
    }
    static func loop(_ keyPath: String, period: Double, samples: Int = 24, _ value: (Double) -> CATransform3D) -> CAKeyframeAnimation {
        loop(keyPath, period: period, samples: samples) { NSValue(caTransform3D: value($0)) as Any }
    }
    private static func loop(_ keyPath: String, period: Double, samples: Int, _ value: (Double) -> Any) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0...samples).map { value(period * Double($0) / Double(samples)) }
        animation.duration = period
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.calculationMode = .linear
        return animation
    }
}

/// Four bars breathing with the music.
struct Equalizer: NSViewRepresentable {
    var playing: Bool
    var color: Color = .white
    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView() }
    func updateNSView(_ view: EqualizerLayerView, context: Context) {
        let color = NSColor(color).cgColor
        guard view.playing != playing || view.color != color else { return }
        view.playing = playing; view.color = color
        view.install()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerLayerView, context: Context) -> CGSize? {
        CGSize(width: EqualizerLayerView.width, height: EqualizerLayerView.height)
    }
}

final class EqualizerLayerView: LoopLayerView {
    static let bar: CGFloat = 2.5, gap: CGFloat = 2.5, height: CGFloat = 14
    static let width = bar * 4 + gap * 3
    private static let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]
    private static let offsets: [Double] = [0, 1.3, 2.1, 0.7]
    var playing = false
    var color = NSColor.white.cgColor
    private var bars: [CALayer] = []

    override func install() {
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if bars.isEmpty {
            bars = (0..<4).map { _ in CALayer() }
            bars.forEach(layer.addSublayer)
        }
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.backgroundColor = color
            bar.cornerRadius = Self.bar / 2
            bar.bounds = CGRect(x: 0, y: 0, width: Self.bar, height: 3)
            bar.position = CGPoint(x: CGFloat(i) * (Self.bar + Self.gap) + Self.bar / 2, y: Self.height / 2)
            guard playing else { continue }
            // Height 4…14 following |sin|, whose period is π / (speed / 2).
            let omega = Self.speeds[i] / 2, phase = Self.offsets[i]
            bar.add(Self.loop("bounds.size.height", period: .pi / omega) { 4 + 10 * abs(sin($0 * omega + phase)) }, forKey: "eq")
        }
        CATransaction.commit()
    }
}

/// Three thinking dots rippling left to right.
struct ThinkingDots: NSViewRepresentable {
    var color: Color
    func makeNSView(context: Context) -> ThinkingDotsLayerView { ThinkingDotsLayerView() }
    func updateNSView(_ view: ThinkingDotsLayerView, context: Context) {
        let color = NSColor(color).cgColor
        guard view.color != color else { return }
        view.color = color
        view.install()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ThinkingDotsLayerView, context: Context) -> CGSize? {
        CGSize(width: ThinkingDotsLayerView.width, height: ThinkingDotsLayerView.dot)
    }
}

final class ThinkingDotsLayerView: LoopLayerView {
    static let dot: CGFloat = 4.5, gap: CGFloat = 3
    static let width = dot * 3 + gap * 2
    var color = NSColor.white.cgColor
    private var dots: [CALayer] = []

    override func install() {
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if dots.isEmpty {
            dots = (0..<3).map { _ in CALayer() }
            dots.forEach(layer.addSublayer)
        }
        let speed = 2.6
        for (i, dot) in dots.enumerated() {
            dot.removeAllAnimations()
            dot.backgroundColor = color
            dot.cornerRadius = Self.dot / 2
            dot.frame = CGRect(x: CGFloat(i) * (Self.dot + Self.gap), y: 0, width: Self.dot, height: Self.dot)
            let opacity = { (t: Double) in 0.35 + 0.65 * max(0, sin(t * speed - Double(i) * 0.9)) }
            dot.opacity = Float(opacity(0))
            if !Theme.reduceMotion { dot.add(Self.loop("opacity", period: 2 * .pi / speed, samples: 32, opacity), forKey: "dots") }
        }
        CATransaction.commit()
    }
}

extension EnvironmentValues {
    /// Draws the mascot as a still SwiftUI figure, for `ImageRenderer`, which cannot capture layer views.
    @Entry var mascotStill = false
}

/// The working / waiting mascot. Its pieces are drawn once by SwiftUI (`DropletMascot`'s own drawing code,
/// rendered to images) and moved by Core Animation along the same curves as `DropletMascot.figure(at:)`:
/// working hops with a squash, glances and blinks; waiting sways and waves.
struct MascotLoop: NSViewRepresentable {
    let mascot: DropletMascot
    func makeNSView(context: Context) -> MascotLayerView { MascotLayerView() }
    func updateNSView(_ view: MascotLayerView, context: Context) {
        guard view.mascot?.phase != mascot.phase || view.mascot?.size != mascot.size else { return }
        view.mascot = mascot
        view.install()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MascotLayerView, context: Context) -> CGSize? {
        CGSize(width: mascot.size, height: mascot.size)
    }
}

final class MascotLayerView: LoopLayerView {
    var mascot: DropletMascot?
    private let figure = CALayer(), body = CALayer(), glance = CALayer(), eyes = CALayer(), hand = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.addSublayer(figure)
        [body, glance, hand].forEach(figure.addSublayer)
        glance.addSublayer(eyes)
    }
    required init?(coder: NSCoder) { fatalError() }
    /// y grows downward, as in SwiftUI, so the figure's offsets and anchors carry over unchanged.
    override var isFlipped: Bool { true }

    /// Rendered pieces, shared by every notch window: (phase, size, scale) → image.
    @MainActor private static var images: [String: CGImage] = [:]
    @MainActor private static func image<V: View>(_ key: String, scale: CGFloat, _ view: V) -> CGImage? {
        let key = "\(key)@\(scale)"
        if let cached = images[key] { return cached }
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = renderer.cgImage
        images[key] = image
        return image
    }

    override func install() {
        guard let mascot else { return }
        let s = mascot.size, scale = window?.backingScaleFactor ?? 2
        let id = "\(mascot.phase.rawValue)-\(s)"
        let pad = (s * 0.1).rounded(.up)   // room for the stroke and the hand's shadow
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for piece in [figure, body, glance, eyes, hand] {
            piece.removeAllAnimations()
            piece.contentsScale = scale
            piece.contentsGravity = .resize
        }
        // The figure squashes and sways about its bottom centre, like the SwiftUI modifiers' .bottom anchor.
        figure.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        figure.anchorPoint = CGPoint(x: 0.5, y: 1)
        figure.position = CGPoint(x: s / 2, y: s)
        figure.transform = CATransform3DIdentity

        body.contents = Self.image("body-\(id)", scale: scale, ZStack { mascot.drop; mascot.mouth }.frame(width: s, height: s).padding(pad))
        body.frame = CGRect(x: -pad, y: -pad, width: s + pad * 2, height: s + pad * 2)

        glance.frame = CGRect(x: 0, y: 0, width: s, height: s)
        let eyesImage = Self.image("eyes-\(id)", scale: scale, mascot.eyes(blink: false).padding(pad))
        eyes.contents = eyesImage
        eyes.bounds = CGRect(x: 0, y: 0, width: CGFloat(eyesImage?.width ?? 0) / scale, height: CGFloat(eyesImage?.height ?? 0) / scale)
        eyes.position = CGPoint(x: s / 2, y: s / 2 + mascot.eyesCenter)   // blinks about the eyes' own centre

        hand.isHidden = mascot.phase != .waiting
        if mascot.phase == .waiting, let symbol = Self.image("hand-\(id)", scale: scale, mascot.handSymbol.padding(pad)) {
            // Rotates about the bottom of the symbol itself (not of the padded image).
            let size = CGSize(width: CGFloat(symbol.width) / scale, height: CGFloat(symbol.height) / scale)
            hand.contents = symbol
            hand.bounds = CGRect(origin: .zero, size: size)
            hand.anchorPoint = CGPoint(x: 0.5, y: (size.height - pad) / size.height)
            hand.position = CGPoint(x: s / 2 + mascot.handOffset.width, y: s / 2 + mascot.handOffset.height + (size.height - pad * 2) / 2)
            hand.transform = CATransform3DMakeRotation(12 * .pi / 180, 0, 0, 1)
            hand.add(Self.loop("transform.rotation.z", period: 2 * .pi / 7) { (sin($0 * 7) * 16 + 12) * .pi / 180 }, forKey: "wave")
            figure.add(Self.loop("transform.rotation.z", period: 2 * .pi / 3.2, samples: 32) { sin($0 * 3.2) * 7 * .pi / 180 }, forKey: "sway")
        }
        if mascot.phase == .working {
            figure.add(Self.loop("transform", period: .pi / 5.2) { t in
                let hop = abs(sin(t * 5.2)), squash = 1 - 0.07 * (1 - hop)
                return CATransform3DConcat(CATransform3DMakeScale(2 - squash, squash, 1), CATransform3DMakeTranslation(0, -hop * s * 0.08, 0))
            }, forKey: "hop")
            glance.add(Self.loop("transform.translation.x", period: 2 * .pi / 9) { sin($0 * 9) * mascot.eyeSize * 0.22 }, forKey: "glance")
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [0.12, 1]
            blink.keyTimes = [0, NSNumber(value: 0.13 / 3.3), 1]
            blink.calculationMode = .discrete
            blink.duration = 3.3
            blink.repeatCount = .infinity
            blink.isRemovedOnCompletion = false
            eyes.add(blink, forKey: "blink")
        }
        CATransaction.commit()
    }
}
