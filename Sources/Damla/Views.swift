import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.62, green: 0.93, blue: 0.82)
    static let amber = Color(red: 1.0, green: 0.80, blue: 0.36)
    static let green = Color(red: 0.45, green: 0.87, blue: 0.55)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let fill = Color.white.opacity(0.08)
    static let fillStrong = Color.white.opacity(0.16)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Opening gets a touch of bounce like the Dynamic Island; closing is quick and settled.
    static func motion(open: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        return open ? .spring(duration: 0.5, bounce: 0.24) : .spring(duration: 0.36, bounce: 0.02)
    }
    static var basket: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.42, bounce: 0.3) }
    static var quick: Animation { reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.3, bounce: 0.1) }
}

extension HUDItem {
    var tint: Color {
        switch kind {
        case .volume: return .white
        case .mute: return Theme.faint
        case .brightness: return Theme.amber
        case .battery: return Theme.green
        case .done: return Theme.accent
        case .agent: return phase == .waiting || phase == .failed ? Theme.amber : Theme.accent
        }
    }
}

// MARK: - Notch shape

/// The MacBook notch outline: concave "ears" at the top corners that melt into the screen edge,
/// convex rounded corners at the bottom. With `topEar == 0` it becomes a plain rounded rect
/// (used as a floating island on screens without a notch).
struct NotchShape: InsettableShape {
    var topEar: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0
    func inset(by amount: CGFloat) -> NotchShape { var copy = self; copy.insetAmount += amount; return copy }
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(topEar, AnimatablePair(topRadius, bottomRadius)) }
        set { topEar = newValue.first; topRadius = newValue.second.first; bottomRadius = newValue.second.second }
    }
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let k: CGFloat = 0.5523
        let e = max(0, topEar)
        let tr = min(max(0, topRadius), rect.height / 2)
        let br = min(max(0, bottomRadius), rect.height / 2, (rect.width - 2 * e) / 2)
        let left = rect.minX + e, right = rect.maxX - e
        let top = rect.minY, bottom = rect.maxY
        var p = Path()
        if e > 0 {
            p.move(to: CGPoint(x: rect.minX, y: top))
            p.addLine(to: CGPoint(x: rect.maxX, y: top))
            p.addQuadCurve(to: CGPoint(x: right, y: top + e), control: CGPoint(x: right, y: top))
        } else {
            p.move(to: CGPoint(x: left + tr, y: top))
            p.addLine(to: CGPoint(x: right - tr, y: top))
            p.addCurve(to: CGPoint(x: right, y: top + tr),
                       control1: CGPoint(x: right - tr * (1 - k), y: top), control2: CGPoint(x: right, y: top + tr * (1 - k)))
        }
        p.addLine(to: CGPoint(x: right, y: bottom - br))
        p.addCurve(to: CGPoint(x: right - br, y: bottom),
                   control1: CGPoint(x: right, y: bottom - br * (1 - k)), control2: CGPoint(x: right - br * (1 - k), y: bottom))
        p.addLine(to: CGPoint(x: left + br, y: bottom))
        p.addCurve(to: CGPoint(x: left, y: bottom - br),
                   control1: CGPoint(x: left + br * (1 - k), y: bottom), control2: CGPoint(x: left, y: bottom - br * (1 - k)))
        if e > 0 {
            p.addLine(to: CGPoint(x: left, y: top + e))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: left, y: top))
        } else {
            p.addLine(to: CGPoint(x: left, y: top + tr))
            p.addCurve(to: CGPoint(x: left + tr, y: top),
                       control1: CGPoint(x: left, y: top + tr * (1 - k)), control2: CGPoint(x: left + tr * (1 - k), y: top))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Root

struct DamlaView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var screen: ScreenMetrics
    @State private var dropping = false
    @State private var glassVisible = false
    init(model: AppState, screen: ScreenMetrics) { self.model = model; media = model.media; self.screen = screen }

    private struct Key: Equatable { var state: NotchState; var compact: Int; var dropping: Bool; var metrics: Layout.Metrics }
    private var state: NotchState { model.state(for: screen.id) }
    private var metrics: Layout.Metrics { screen.metrics }
    private var open: Bool { state == .expanded }
    private var size: CGSize { Layout.shapeSize(state, metrics, compactSlots: model.compactSlots) }
    private var shape: NotchShape {
        let bottom: CGFloat = open ? 26 : state == .drop ? 24 : 13
        return metrics.hasNotch
            ? NotchShape(topEar: Layout.ear(metrics, open: open), topRadius: 0, bottomRadius: bottom)
            : NotchShape(topEar: 0, topRadius: open ? 24 : bottom, bottomRadius: open ? 24 : bottom)
    }

    var body: some View {
        ZStack(alignment: .top) {
            surface.frame(width: size.width, height: size.height)
            // Always present so its top padding animates with the shape: the pill rides down with the panel.
            TabPill(model: model)
                .padding(.top, size.height + Layout.pillGap)
                .opacity(open && !model.cleaning.active ? 1 : 0)
                .scaleEffect(open ? 1 : 0.8, anchor: .top)
                .allowsHitTesting(open && !model.cleaning.active)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(state == .drop ? Theme.basket : Theme.motion(open: open), value: Key(state: state, compact: model.compactSlots, dropping: dropping, metrics: metrics))
        .onChange(of: open, initial: true) { _, isOpen in
            // Glass is invisible under the solid black closed notch, so drop it there to spare the compositor.
            if isOpen { glassVisible = true }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { if !model.expanded { glassVisible = false } } }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .active)
    }

    private var ambientColor: Color { media.accent.map { Color(nsColor: $0) } ?? .clear }
    /// How strongly the artwork colour fills the panel: full on Özet, a hint on other tabs, none in settings.
    private var ambientStrength: Double {
        guard open, media.accent != nil, !model.settingsVisible, !model.cleaning.active else { return 0 }
        return model.selectedTab == .home ? 1 : 0.45
    }

    /// Opaque at the notch, artwork colour through the middle, native clear glass at the foot.
    /// The artwork also tints the glass itself, carrying its colour into the exposed lower rim.
    /// One shared clip keeps the glass and outgoing media inside the same animated silhouette.
    private var surface: some View {
        let notchEdge = min(1, Layout.headerHeight(metrics) / size.height)
        let bodyHeight = 1 - notchEdge
        return ZStack(alignment: .top) {
            if glassVisible {
                Color.clear
                    .glassEffect(.clear.tint(ambientColor.opacity(0.28 * ambientStrength)), in: shape)
                    .animation(.easeInOut(duration: 0.9), value: media.accent)
            }
            shape.inset(by: 1.5).fill(LinearGradient(stops: [
                .init(color: .clear, location: notchEdge),
                .init(color: ambientColor.opacity(0.78), location: notchEdge + bodyHeight * 0.28),
                .init(color: ambientColor.opacity(0.72), location: notchEdge + bodyHeight * 0.48),
                .init(color: ambientColor.opacity(0.28), location: notchEdge + bodyHeight * 0.70),
                .init(color: .clear, location: notchEdge + bodyHeight * 0.94),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom))
                .animation(.easeInOut(duration: 0.9), value: media.accent)
                .opacity(ambientStrength)
            shape.fill(LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: notchEdge),
                .init(color: .black.opacity(open ? 0.78 : 1), location: notchEdge + bodyHeight * 0.20),
                .init(color: .black.opacity(open ? 0.38 : 1), location: notchEdge + bodyHeight * 0.50),
                .init(color: .black.opacity(open ? 0.32 : 1), location: notchEdge + bodyHeight * 0.74),
                .init(color: .black.opacity(open ? 0 : 1), location: notchEdge + bodyHeight * 0.97),
                .init(color: .black.opacity(open ? 0 : 1), location: 1)
            ], startPoint: .top, endPoint: .bottom))
            content.shadow(color: .black.opacity(open ? 0.5 : 0), radius: 3, y: 1)
        }
        .clipShape(shape)
        .overlay {
            if dropping { shape.strokeBorder(Theme.accent.opacity(0.9), lineWidth: 1.5) }
        }
        .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 24, y: 12)
        .contentShape(shape)
        .accessibilityAction(named: Text("Paneli aç")) {
            model.activeScreenID = screen.id
            model.expanded = true; model.pinnedOpen = true
        }
        .onTapGesture { if state != .expanded { model.activeScreenID = screen.id; model.expanded = true } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropping) { providers in
            model.activeScreenID = screen.id
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { model.addFiles([url]) }
                }
            }
            return !providers.isEmpty
        }
        .onChange(of: dropping) { _, value in
            // Without the basket (drag started before we noticed), open the shelf so there is a target.
            if value && !model.dragActive { model.activeScreenID = screen.id; model.selectedTab = .files; model.settingsVisible = false; model.expanded = true }
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .expanded:
            Group {
                if model.cleaning.active {
                    CleaningPanelView(cleaning: model.cleaning)
                        .padding(.top, Layout.headerHeight(metrics))
                } else { ExpandedView(model: model, metrics: metrics) }
            }
                .frame(width: Layout.panelWidth, height: Layout.headerHeight(metrics) + Layout.contentHeight)
                .transition(AnyTransition.asymmetric(
                    insertion: AnyTransition(.blurReplace),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        case .hud:
            if let hud = model.hud { HUDRow(hud: hud, metrics: metrics).transition(.blurReplace) }
        case .drop:
            DropRow(metrics: metrics, targeted: dropping, count: model.files.count, dragged: model.dragURLs).transition(.blurReplace)
        case .closed:
            CompactRow(model: model, media: media, metrics: metrics).transition(.blurReplace)
        }
    }
}

// MARK: - Closed notch

/// A live activity the closed notch can show. Each has a glyph (identity) and a status (motion).
enum CompactActivity: Equatable {
    case timer, agent(AgentSession), media
    /// Left-to-right order when two share the island: the timer first, media next, the agent last.
    var rank: Int { switch self { case .timer: return 0; case .media: return 1; case .agent: return 2 } }
}

struct CompactRow: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    let metrics: Layout.Metrics

    /// Up to two activities; when three compete the timer and the agent win because both need attention.
    private var activities: [CompactActivity] {
        var list: [CompactActivity] = []
        if model.session.hasStarted { list.append(.timer) }
        if let agent = model.agentBadge { list.append(.agent(agent)) }
        if media.hasTrack { list.append(.media) }
        return Array(list.prefix(2)).sorted { $0.rank < $1.rank }
    }

    var body: some View {
        let m = metrics
        let ear = Layout.ear(m, open: false)
        let list = activities
        let side = Layout.compactSide(slots: list.count) - ear
        if let first = list.first {
            HStack(spacing: 0) {
                Group {
                    if list.count == 1 { glyph(first) }
                    else { HStack(spacing: 7) { glyph(first); status(first) } }
                }
                .frame(width: side)
                Spacer(minLength: 0).frame(width: m.notchWidth)
                Group {
                    if list.count == 1 { status(first) }
                    else if let second = list.dropFirst().first { HStack(spacing: 7) { status(second); glyph(second) } }
                }
                .frame(width: side)
            }
            .help(helpText)
            .foregroundStyle(.white)
            .padding(.horizontal, ear)
            .frame(height: Layout.closedHeight(m))
            .accessibilityLabel("Damla panelini aç")
        } else if !m.hasNotch {
            Image(systemName: "drop.fill").font(.system(size: 9)).foregroundStyle(Theme.faint)
                .frame(height: Layout.closedHeight(m))
        } else {
            Color.clear.frame(height: Layout.closedHeight(m))
        }
    }

    private var helpText: String {
        activities.map { activity -> String in
            switch activity {
            case .timer: return "Odak · \(model.timeLabel)"
            case .agent(let agent): return "\(agent.provider.title) · \(agent.project) · \(agent.phase.title)"
            case .media: return media.hasTrack ? "\(media.title) · \(media.artist)" : "Müzik"
            }
        }.joined(separator: "\n")
    }

    @ViewBuilder private func glyph(_ activity: CompactActivity) -> some View {
        switch activity {
        case .timer:
            Text(model.timeLabel).font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
        case .agent(let agent):
            AgentMascot(session: agent, size: 22)
        case .media:
            if let art = media.artwork {
                Image(nsImage: art).resizable().scaledToFill().frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
            } else {
                Image(systemName: "music.note").font(.system(size: 11, weight: .semibold))
            }
        }
    }

    @ViewBuilder private func status(_ activity: CompactActivity) -> some View {
        switch activity {
        case .timer:
            Image(systemName: model.session.running ? "timer" : "pause.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
        case .agent(let agent):
            AgentStatusMark(phase: agent.phase)
        case .media:
            Equalizer(playing: media.playing, color: media.accent.map { Color(nsColor: $0) } ?? .white).opacity(media.playing ? 1 : 0.55)
        }
    }
}

/// Four bars breathing with the music. Driven by a paused-capable timeline, so it costs nothing when stopped.
struct Equalizer: View {
    var playing: Bool
    var color: Color = .white
    private let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]
    private let offsets: [Double] = [0, 1.3, 2.1, 0.7]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 14, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(color)
                        .frame(width: 2.5, height: playing ? 4 + 10 * abs(sin(t * speeds[i] / 2 + offsets[i])) : 3)
                }
            }
            .frame(height: 14)
            .animation(.linear(duration: 0.07), value: t)
        }
    }
}

// MARK: - Agent mascot

/// The agent app's icon, alive while it works: a slow breath and a soft ring in the status colour,
/// plus a small badge for waiting / done / failed.
struct AgentMascot: View {
    let session: AgentSession
    var size: CGFloat = 22
    private var tint: Color { session.phase == .waiting || session.phase == .failed ? Theme.amber : Theme.accent }
    private var working: Bool { session.phase == .working }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon = session.provider.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "terminal").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(tint.opacity(working ? 0.9 : 0.55), lineWidth: 1))
            .phaseAnimator([false, true], trigger: working) { view, breathe in
                view.scaleEffect(working && breathe ? 1.06 : 1)
                    .shadow(color: tint.opacity(working && breathe ? 0.65 : 0.2), radius: working && breathe ? 6 : 2)
            } animation: { _ in Theme.reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 1.1).repeatForever(autoreverses: true) }
            if session.phase != .working {
                Image(systemName: session.phase.icon).font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.black)
                    .frame(width: size * 0.5, height: size * 0.5).background(tint, in: Circle())
                    .overlay(Circle().strokeBorder(.black, lineWidth: 1))
                    .offset(x: size * 0.16, y: size * 0.16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Theme.quick, value: session.phase)
        .accessibilityLabel("\(session.provider.title) · \(session.phase.title)")
    }
}

/// Right-hand status beside the mascot: three thinking dots while working, a symbol otherwise.
struct AgentStatusMark: View {
    let phase: AgentPhase
    private var tint: Color { phase == .waiting || phase == .failed ? Theme.amber : Theme.accent }
    var body: some View {
        if phase == .working {
            TimelineView(.animation(minimumInterval: 1 / 12, paused: Theme.reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(tint).frame(width: 4.5, height: 4.5)
                            .opacity(0.35 + 0.65 * max(0, sin(t * 2.6 - Double(i) * 0.9)))
                    }
                }
            }
        } else {
            Image(systemName: phase.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

// MARK: - HUD

struct HUDRow: View {
    let hud: HUDItem
    let metrics: Layout.Metrics
    var body: some View {
        let ear = Layout.ear(metrics, open: false)
        let side = (metrics.hasNotch ? Layout.hudSide : 128) - ear
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                if let image = hud.image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                } else {
                    Image(systemName: hud.icon).font(.system(size: 12, weight: .semibold)).frame(width: 16)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(hud.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .padding(.leading, 14).frame(width: side, alignment: .leading)
            Spacer(minLength: 0).frame(width: metrics.notchWidth)
            Group {
                if hud.kind == .agent {
                    HStack(spacing: 6) {
                        if let phase = hud.phase { AgentStatusMark(phase: phase) }
                        Text(hud.detail).font(.system(size: 11, weight: .semibold)).lineLimit(1).foregroundStyle(hud.tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    HStack(spacing: 8) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.18))
                                Capsule().fill(hud.tint).frame(width: max(4, g.size.width * hud.level))
                            }
                        }.frame(height: 4)
                        Text("\(Int((hud.level * 100).rounded()))").font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 22, alignment: .trailing).contentTransition(.numericText())
                    }
                }
            }
            .padding(.trailing, 14).frame(width: side)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ear)
        .frame(height: Layout.closedHeight(metrics))
        .animation(.easeOut(duration: 0.18), value: hud.level)
    }
}

// MARK: - Basket

/// The notch while a file is being dragged: a deep tray under the notch so the drop never has to
/// touch the screen edge (where macOS would spring Mission Control).
struct DropRow: View {
    let metrics: Layout.Metrics
    let targeted: Bool
    let count: Int
    var dragged: [URL] = []
    @ObservedObject private var store = ThumbnailStore.shared
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Layout.closedHeight(metrics))
            HStack(spacing: 12) {
                if let first = dragged.first {
                    let thumb = store.thumbnail(for: first, size: CGSize(width: 44, height: 44))
                    ZStack {
                        if let thumb, thumb.isPreview {
                            Image(nsImage: thumb.image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: first.path)).resizable().padding(4)
                        }
                    }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dragged.count > 1 ? "\(dragged.count) öğe" : first.lastPathComponent)
                            .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(targeted ? "Bırak" : "Buraya bırak").font(.system(size: 10.5, weight: .medium)).foregroundStyle(targeted ? Theme.accent : Theme.dim)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                } else {
                    Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 24, weight: .regular)).contentTransition(.symbolEffect(.replace))
                    HStack(spacing: 6) {
                        Text(targeted ? "Bırak" : "Buraya bırak").font(.system(size: 12.5, weight: .semibold))
                        if count > 0 && !targeted {
                            Text("\(count)").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.fillStrong, in: Capsule())
                        }
                    }
                }
            }
            .foregroundStyle(targeted ? Theme.accent : Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(targeted ? Theme.accent.opacity(0.12) : .white.opacity(0.04))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                    .foregroundStyle(targeted ? Theme.accent.opacity(0.9) : .white.opacity(0.35))
            }
            .scaleEffect(targeted ? 1.02 : 1)
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 14)
            .frame(height: Layout.dropBandHeight)
            .animation(Theme.quick, value: targeted)
        }
        .padding(.horizontal, Layout.ear(metrics, open: false))
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var model: AppState
    let metrics: Layout.Metrics
    var body: some View {
        let m = metrics
        VStack(spacing: 0) {
            Color.clear.frame(height: Layout.headerHeight(m)).contentShape(Rectangle())
                .onTapGesture { model.pinnedOpen = false; model.expanded = false }
                .help("Kapat")
            Group {
                if model.settingsVisible { SettingsView(model: model) }
                else {
                    switch model.selectedTab {
                    case .home: HomeView(model: model, media: model.media)
                    case .files: ShelfView(model: model)
                    case .clipboard: ClipboardView(model: model)
                    case .focus: FocusView(model: model)
                    case .agents: AgentPanelView(service: model.agents)
                    }
                }
            }
            .transition(.blurReplace)
            .id(model.settingsVisible ? "settings" : model.selectedTab.rawValue)
            .padding(.horizontal, 24).padding(.top, m.hasNotch ? 8 : 4).padding(.bottom, 18)
            .frame(width: Layout.panelWidth, height: Layout.contentHeight)
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Button { model.noticeAction?(); model.notice = nil } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.noticeAction == nil ? "info.circle.fill" : "arrow.up.forward.circle.fill").font(.system(size: 10, weight: .semibold))
                        Text(notice).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(.plain).padding(.bottom, 10)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(Theme.quick, value: model.notice)
        .foregroundStyle(.white)
        .animation(Theme.quick, value: model.selectedTab)
        .animation(Theme.quick, value: model.settingsVisible)
    }
}

struct TabPill: View {
    @ObservedObject var model: AppState
    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { tab in
                let selected = model.selectedTab == tab && !model.settingsVisible
                Button { model.select(tab) } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: tab.icon).font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                            .frame(width: 34, height: 28)
                        if tab == .files, !model.files.isEmpty {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(x: -6, y: 5)
                        }
                        if tab == .agents, let badge = model.agentBadge {
                            Circle().fill(badge.phase == .waiting ? Theme.amber : Theme.accent).frame(width: 5, height: 5).offset(x: -6, y: 5)
                        }
                    }
                    .foregroundStyle(selected ? Color.white : Theme.dim)
                    .background(selected ? Theme.fillStrong : .clear, in: Capsule())
                    .contentShape(Capsule())
                }.buttonStyle(.plain).help(tab.rawValue).accessibilityLabel(tab.rawValue)
            }
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 14).padding(.horizontal, 4)
            pillButton(model.pinnedOpen ? "pin.fill" : "pin", "Açık tut", active: model.pinnedOpen) { model.pinnedOpen.toggle() }
            pillButton("gearshape", "Ayarlar", active: model.settingsVisible) { model.settingsVisible.toggle() }
        }
        .padding(.horizontal, 5)
        .frame(height: Layout.pillHeight)
        .glassEffect(.clear.tint(.black.opacity(0.5)).interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .animation(Theme.quick, value: model.selectedTab)
        .animation(Theme.quick, value: model.settingsVisible)
    }
    private func pillButton(_ icon: String, _ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).frame(width: 30, height: 28)
                .foregroundStyle(active ? Color.white : Theme.dim)
                .background(active ? Theme.fillStrong : .clear, in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @State private var appeared = false
    private var tint: Color { media.accent.map { Color(nsColor: $0) } ?? .white }
    private func entrance(_ order: Double) -> Animation {
        Theme.reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.55, bounce: 0.22).delay(0.04 + order * 0.05)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Artwork(image: media.artwork, placeholder: media.hasTrack ? "music.note" : "waveform", size: 88)
                    .scaleEffect(appeared ? 1 : 0.72, anchor: .bottomLeading).opacity(appeared ? 1 : 0)
                    .animation(entrance(0), value: appeared)
                VStack(alignment: .leading, spacing: 3) {
                    if media.hasTrack {
                        HStack(alignment: .firstTextBaseline) {
                            Text(media.title).font(.system(size: 15, weight: .semibold)).tracking(-0.2).lineLimit(1)
                            Spacer(minLength: 6)
                            Equalizer(playing: media.playing, color: tint).opacity(media.playing ? 1 : 0)
                        }
                        Text(media.artist).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1)
                        Spacer(minLength: 4)
                        ScrubBar(position: media.livePosition(at: model.now), duration: media.duration, tint: tint) { media.seek($0) }
                    } else {
                        Text("Müzik").font(.system(size: 15, weight: .semibold))
                        Text(media.status ?? (media.bridgeActive ? "Bir şey çal: Müzik, Spotify, Safari…" : "Apple Music veya Spotify’ı bağla."))
                            .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(2)
                        Spacer(minLength: 4)
                        if !media.bridgeActive {
                            HStack(spacing: 6) {
                                ForEach(MusicSource.allCases) { source in
                                    Button(source.rawValue) { media.connect(source) }.font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: appeared ? 0 : 14).opacity(appeared ? 1 : 0)
                .animation(entrance(1), value: appeared)
            }
            .frame(height: 88)
            Spacer(minLength: 10)
            ZStack {
                HStack(spacing: 14) {
                    if model.battery.available {
                        statusLabel(model.battery.symbol, "\(model.battery.percentage)%", tint: model.battery.plugged ? Theme.green : nil)
                    }
                    if let volume = model.volume {
                        statusLabel(model.muted ? "speaker.slash" : "speaker.wave.2", model.muted ? "0" : "\(Int(volume * 100))")
                    }
                    Spacer()
                    if media.bridgeActive, let icon = media.sourceIcon {
                        Button { media.activateSource() } label: {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20).contentShape(Circle())
                        }.buttonStyle(.plain).help(media.sourceBundleID ?? "")
                    } else if media.connected {
                        Menu {
                            ForEach(MusicSource.allCases) { source in Button(source.rawValue) { media.connect(source) } }
                            Divider(); Button("Bağlantıyı kes") { media.disconnect() }
                        } label: {
                            Image(systemName: media.source == .spotify ? "circle.hexagongrid.fill" : "music.note").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white).frame(width: 26, height: 26).contentShape(Circle())
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26)
                            .glassLook(AnyShape(Circle())).help(media.source.rawValue)
                    }
                    Button { model.select(.focus) } label: {
                        statusLabel(model.session.running ? "timer" : "timer", model.timeLabel, tint: model.session.running ? Theme.accent : nil)
                    }.buttonStyle(.plain).help("Odak")
                }
                if media.hasTrack {
                    HStack(spacing: 18) {
                        transport("backward.fill", "Önceki", size: 13) { media.command("previous track") }
                        Button { media.command("playpause") } label: {
                            Image(systemName: media.playing ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                                .frame(width: 36, height: 36).contentShape(Circle())
                                .contentTransition(.symbolEffect(.replace))
                        }.buttonStyle(GlassCircleStyle()).help(media.playing ? "Duraklat" : "Oynat")
                        transport("forward.fill", "Sonraki", size: 13) { media.command("next track") }
                    }
                }
            }
            .frame(height: 36)
            .offset(y: appeared ? 0 : 10).opacity(appeared ? 1 : 0)
            .animation(entrance(2), value: appeared)
        }
        .onAppear { appeared = true }
    }
    private func statusLabel(_ icon: String, _ text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .medium))
            Text(text).font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
        }.foregroundStyle(tint ?? Theme.dim)
    }
    private func transport(_ icon: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(GlassCircleStyle()).help(label)
    }
}

struct Artwork: View {
    var image: NSImage?
    var placeholder: String
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).fill(Theme.fill)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: placeholder).font(.system(size: size * 0.34, weight: .ultraLight)).foregroundStyle(Theme.dim)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(image == nil ? 0 : 0.5), radius: 10, y: 5)
    }
}

/// Thin progress bar that thickens on hover and scrubs with a drag.
struct ScrubBar: View {
    var position: Double
    var duration: Double
    var tint: Color = .white
    var onSeek: (Double) -> Void
    @State private var dragging = false
    @State private var dragValue = 0.0
    @State private var hovering = false
    var body: some View {
        let shown = dragging ? dragValue : position
        VStack(spacing: 5) {
            GeometryReader { g in
                let fraction = duration > 0 ? min(1, max(0, shown / duration)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(tint).frame(width: max(0, g.size.width * fraction))
                        .shadow(color: tint.opacity(0.6), radius: 4)
                }
                .frame(height: hovering || dragging ? 6 : 3.5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        dragValue = Double(min(max(0, value.location.x / g.size.width), 1)) * duration
                    }
                    .onEnded { _ in onSeek(dragValue); dragging = false })
            }
            .frame(height: 12)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            HStack {
                Text(Self.format(shown))
                Spacer()
                Text("-" + Self.format(max(0, duration - shown)))
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Theme.faint)
        }
    }
    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Files

struct ShelfView: View {
    @ObservedObject var model: AppState
    var body: some View {
        VStack(spacing: 8) {
            if model.files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(Theme.dim)
                    Text("Dosyaları buraya bırak").font(.system(size: 11)).foregroundStyle(Theme.faint)
                    Button { model.chooseFiles() } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28).contentShape(Circle())
                    }.buttonStyle(GlassCircleStyle()).help("Dosya ekle").accessibilityLabel("Dosya ekle")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5])).foregroundStyle(.white.opacity(0.14))
                }
            } else {
                HStack {
                    Text("\(model.files.count) öğe").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Theme.dim)
                    Spacer()
                    IconButton(icon: "trash", label: "Rafı boşalt") { model.clearFiles() }
                    IconButton(icon: "square.and.arrow.up", label: "Seçili dosyayı paylaş") { model.shareFile() }
                    IconButton(icon: "plus", label: "Dosya ekle") { model.chooseFiles() }
                }.frame(height: 18)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(model.files) { item in FileTile(item: item, model: model) }
                    }.padding(.vertical, 2).frame(maxHeight: .infinity)
                }.scrollIndicators(.hidden).edgeFade().frame(maxHeight: .infinity)
            }
        }
    }
}

struct FileTile: View {
    let item: ShelfItem
    @ObservedObject var model: AppState
    @ObservedObject private var store = ThumbnailStore.shared
    @State private var hovering = false
    private var selected: Bool { model.selectedFile == item.id }
    var body: some View {
        let thumb = store.thumbnail(for: item.url)
        VStack(spacing: 6) {
            ZStack {
                if let thumb, thumb.isPreview {
                    Image(nsImage: thumb.image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 74, height: 58).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                } else {
                    Image(nsImage: thumb?.image ?? NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 46, height: 46)
                }
            }
            .frame(width: 74, height: 58)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            Text(item.url.lastPathComponent).font(.system(size: 10, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 26, alignment: .top)
        }
        .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 8)
        .frame(width: 92).frame(maxHeight: .infinity)
        .background(hovering || selected ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Theme.accent.opacity(0.9) : .clear, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 2) {
                    Button { model.quickLook(item) } label: {
                        Image(systemName: "eye").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 18)
                            .background(.black.opacity(0.6), in: Circle()).contentShape(Circle())
                    }.buttonStyle(.plain).help("Önizle (Boşluk)")
                    Button { model.removeFile(item) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 18)
                            .background(.black.opacity(0.6), in: Circle()).contentShape(Circle())
                    }.buttonStyle(.plain).help("Raftan kaldır")
                }.padding(4).transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture(count: 2) { model.openFile(item) }
        .onTapGesture(count: 1) { model.selectedFile = item.id; model.requestKeyFocus?() }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Aç") { model.openFile(item) }
            Button("Önizle") { model.quickLook(item) }
            Button("Paylaş…") { model.shareFile(item) }
            Button("Finder’da göster") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Raftan kaldır") { model.removeFile(item) }
        }
        .help(item.url.path)
    }
}

// MARK: - Clipboard

struct ClipboardView: View {
    @ObservedObject var model: AppState
    @State private var search = ""
    @State private var copied: UUID?
    var entries: [ClipEntry] { model.clips.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 8) {
            if !model.clipboardEnabled, model.clips.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(Theme.dim)
                    Text("Kopyaladıkların burada birikir").font(.system(size: 11)).foregroundStyle(Theme.faint)
                    Button("Pano geçmişini aç") { model.toggleClipboard(true) }.font(.system(size: 11, weight: .medium)).buttonStyle(PillStyle(accent: true))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
                    TextField("Ara", text: $search).textFieldStyle(.plain).font(.system(size: 11.5)).onTapGesture { model.requestKeyFocus?() }
                    if !search.isEmpty { IconButton(icon: "xmark.circle.fill", label: "Temizle") { search = "" } }
                    IconButton(icon: model.clipboardEnabled ? "record.circle" : "pause.circle", label: model.clipboardEnabled ? "Kaydı duraklat" : "Kaydı sürdür",
                               tint: model.clipboardEnabled ? Theme.accent : Theme.dim) { model.toggleClipboard(!model.clipboardEnabled) }
                }.padding(.horizontal, 10).frame(height: 28).background(Theme.fill, in: Capsule())
                if entries.isEmpty {
                    Image(systemName: search.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(Theme.faint).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(entries) { entry in
                                ClipCard(entry: entry, copied: copied == entry.id, model: model) {
                                    model.copy(entry); copied = entry.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copied == entry.id { copied = nil } }
                                }
                            }
                        }.padding(.vertical, 2)
                    }.scrollIndicators(.hidden).edgeFade()
                }
            }
        }
    }
}

struct ClipCard: View {
    let entry: ClipEntry
    let copied: Bool
    @ObservedObject var model: AppState
    let onCopy: () -> Void
    @State private var hovering = false
    private var isLink: Bool { entry.text?.hasPrefix("http") == true }
    private var isColor: Bool {
        guard let t = entry.text?.trimmingCharacters(in: .whitespaces), t.hasPrefix("#"), t.count == 7 || t.count == 4 else { return false }
        return t.dropFirst().allSatisfy(\.isHexDigit)
    }
    private var kindLabel: String { entry.kind == .image ? "Görsel" : isColor ? "Renk" : isLink ? "Bağlantı" : "Metin" }
    private var kindIcon: String { entry.kind == .image ? "photo" : isColor ? "paintpalette" : isLink ? "link" : "text.alignleft" }
    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let data = entry.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else if isColor, let color = Color(hex: entry.text ?? "") {
                        color
                        Text(entry.title.uppercased()).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    } else {
                        Text(entry.title).font(.system(size: 10)).lineLimit(5).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(9)
                    }
                    if copied {
                        Color.black.opacity(0.5)
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                HStack(spacing: 5) {
                    Image(systemName: kindIcon).font(.system(size: 8.5, weight: .semibold))
                    Text(kindLabel).font(.system(size: 9, weight: .medium))
                    Spacer(minLength: 0)
                    if entry.pinned && !hovering { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    if hovering {
                        IconButton(icon: entry.pinned ? "pin.fill" : "pin", label: entry.pinned ? "Sabitlemeyi kaldır" : "Sabitle", size: 18) { model.pinClip(entry) }
                        IconButton(icon: "xmark", label: "Kaldır", size: 18) { model.removeClip(entry) }
                    }
                }
                .foregroundStyle(Theme.dim).padding(.horizontal, 8).frame(height: 24).background(.black.opacity(0.25))
            }
            .frame(width: 128, height: 124)
            .background(hovering ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(entry.pinned ? 0.22 : 0.06), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).help("Kopyala")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: copied)
    }
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces); text.removeFirst()
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Focus

struct FocusView: View {
    @ObservedObject var model: AppState
    var body: some View {
        let running = model.session.running
        HStack(spacing: 26) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 4)
                Circle().trim(from: 0, to: model.session.progress(at: model.now))
                    .stroke(running ? Theme.accent : .white.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).animation(.linear(duration: 0.5), value: model.now)
                    .shadow(color: Theme.accent.opacity(running ? 0.5 : 0), radius: 6)
                VStack(spacing: 4) {
                    Image(systemName: model.session.phase == .focus ? "brain.head.profile" : "cup.and.saucer").font(.system(size: 12)).foregroundStyle(Theme.dim)
                    Text(model.timeLabel).font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit().tracking(-1)
                        .contentTransition(.numericText())
                }
            }.frame(width: 128, height: 128)
            VStack(spacing: 16) {
                HStack(spacing: 5) {
                    ForEach([25, 45, 50], id: \.self) { minutes in
                        Button("\(minutes)") { model.setFocus(minutes: minutes) }
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .buttonStyle(PillStyle(accent: model.session.phase == .focus && Int(model.session.duration) == minutes * 60))
                            .disabled(running).help("\(minutes) dakika")
                    }
                }
                HStack(spacing: 14) {
                    IconButton(icon: "arrow.counterclockwise", label: "Sıfırla", size: 32) { model.resetFocus() }
                    Button { model.toggleFocus() } label: {
                        Image(systemName: running ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .bold))
                            .frame(width: 44, height: 44).contentShape(Circle()).contentTransition(.symbolEffect(.replace))
                    }.buttonStyle(GlassCircleStyle(prominent: running))
                        .help(running ? "Duraklat" : "Başlat").accessibilityLabel(running ? "Duraklat" : "Başlat")
                    IconButton(icon: "cup.and.saucer", label: "5 dakika mola", size: 32) { model.setFocus(minutes: 5, phase: .rest); model.toggleFocus() }.disabled(running)
                }
                if model.completedSessions > 0 {
                    Text("Bugün \(model.completedSessions) tur").font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(Theme.faint)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: AppState
    @ObservedObject var keys: MediaKeyInterceptor
    init(model: AppState) { self.model = model; keys = model.keys }

    var body: some View {
        VStack(spacing: 0) {
            // Switches in a two-column grid, every switch flush right in its cell.
            Grid(horizontalSpacing: 18, verticalSpacing: 0) {
                GridRow {
                    switchRow("Üzerine gelince aç", isOn: $model.automaticOpen)
                    switchRow("Girişte başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
                GridRow {
                    switchRow("Pano geçmişi", isOn: Binding(get: { model.clipboardEnabled }, set: { model.toggleClipboard($0) }))
                    switchRow("Sistem HUD’unu gizle", isOn: Binding(get: { model.hideSystemHUD }, set: { model.setHideSystemHUD($0) }))
                        .help("Ses, sessiz ve parlaklık tuşlarını Damla uygular; macOS kendi göstergesini çizmez. Erişilebilirlik izni ister.")
                }
            }
            .onChange(of: model.automaticOpen) { _, _ in model.savePreferences() }
            divider
            choiceRow("Ekran") {
                ForEach(DisplayMode.allCases) { mode in
                    Button(mode.rawValue) { model.displayMode = mode; model.savePreferences() }
                        .buttonStyle(PillStyle(accent: model.displayMode == mode))
                }
            }
            divider
            choiceRow("Çentiksiz ekran") {
                ForEach(ExternalStyle.allCases) { style in
                    Button(style.rawValue) { model.externalStyle = style; model.savePreferences() }
                        .buttonStyle(PillStyle(accent: model.externalStyle == style))
                }
            }
            divider
            choiceRow("Temizlik modu") {
                Button("Klavyeyi kilitle · 60 sn") { model.startCleaning() }.buttonStyle(PillStyle())
                    .help("Tüm klavyeler 60 saniye kilitlenir. Fare çalışır. Esc’yi 2 saniye tutarak çıkabilirsin.")
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if model.hideSystemHUD && !keys.active {
                    Button { MediaKeyInterceptor.openAccessibilitySettings() } label: {
                        Label("Erişilebilirlik izni bekleniyor · Sistem Ayarları’nı aç", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.amber).lineLimit(1)
                    }.buttonStyle(.plain)
                } else {
                    Text("Damla 0.3 · ⌃⌥Space").font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(Theme.faint)
                }
                Spacer()
                Button("Çıkış") { NSApp.terminate(nil) }.font(.system(size: 10.5, weight: .medium)).buttonStyle(.plain).foregroundStyle(Theme.dim)
            }
            .frame(height: 16)
        }
        .font(.system(size: 11.5))
        .tint(Theme.accent)
        .padding(.top, 2)
        .frame(maxHeight: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
            Spacer(minLength: 6)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .tint(Theme.accent).environment(\.controlActiveState, .active)
        }
        .frame(height: 24)
        .frame(maxWidth: .infinity)
    }

    private func choiceRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 8)
            HStack(spacing: 4, content: content).font(.system(size: 10.5, weight: .medium))
        }
        .frame(height: 30)
    }
}

// MARK: - Controls

extension View {
    /// Softens the trailing edge of a horizontal shelf so a cut-off card reads as "more to scroll".
    func edgeFade() -> some View {
        mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                            startPoint: .leading, endPoint: .trailing))
    }
}

/// Small round Liquid Glass button used for secondary actions.
struct IconButton: View {
    let icon: String
    let label: String
    var tint: Color = .white
    var size: CGFloat = 26
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(tint)
                .frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(GlassCircleStyle())
        .help(label).accessibilityLabel(label)
    }
}

/// Glass-looking chrome drawn with plain layers. A real `glassEffect` inside the panel's glass would be
/// glass-in-glass, which makes the compositor pull the backdrop through the panel's black top.
struct GlassLook: ViewModifier {
    var shape: AnyShape
    var prominent = false
    var pressed = false
    func body(content: Content) -> some View {
        content
            .background {
                if prominent { shape.fill(Theme.accent) }
                else {
                    shape.fill(LinearGradient(colors: [.white.opacity(pressed ? 0.24 : 0.16), .white.opacity(pressed ? 0.14 : 0.06)],
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay {
                shape.stroke(LinearGradient(colors: [.white.opacity(prominent ? 0.6 : 0.38), .white.opacity(0.03)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .opacity(pressed ? 0.85 : 1)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

extension View {
    func glassLook(_ shape: AnyShape, prominent: Bool = false, pressed: Bool = false) -> some View {
        modifier(GlassLook(shape: shape, prominent: prominent, pressed: pressed))
    }
}

struct GlassCircleStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(prominent ? Color.black : Color.white)
            .glassLook(AnyShape(Circle()), prominent: prominent, pressed: configuration.isPressed)
    }
}

/// Capsule glass-look button; `accent` switches to the mint-filled variant.
struct PillStyle: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundStyle(accent ? Color.black : Color.white)
            .glassLook(AnyShape(Capsule()), prominent: accent, pressed: configuration.isPressed)
    }
}
