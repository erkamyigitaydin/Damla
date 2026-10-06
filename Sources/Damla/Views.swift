import SwiftUI
import CoreAudio
import AppKit
import UniformTypeIdentifiers

// MARK: - Theme

/// The accent follows the music: the album cover's colour, lifted bright enough to carry black text, or plain
/// white when nothing (or something grey) is playing. AppState refreshes the views when it changes.
enum Accent {
    nonisolated(unsafe) static var current: NSColor = .white
    static func update(from cover: NSColor?) {
        guard let rgb = cover?.usingColorSpace(.sRGB) else { current = .white; return }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        current = s < 0.15 ? .white : NSColor(hue: h, saturation: min(s, 0.62), brightness: max(b, 0.92), alpha: 1)
    }
}

enum Theme {
    static var accent: Color { Color(nsColor: Accent.current) }
    /// Agents keep their own colour, a pale water blue, whatever the music is.
    static let agent = Color(red: 0.8, green: 0.89, blue: 1.0)
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
        // Closing settles into the notch with the faintest give instead of stopping dead.
        return open ? .spring(duration: 0.5, bounce: 0.24) : .spring(duration: 0.4, bounce: 0.08)
    }
    static var basket: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.42, bounce: 0.3) }
    static var quick: Animation { reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.3, bounce: 0.1) }
    /// Moving between pages: the content and the pill's highlight travel together, with a touch of spring.
    static var page: Animation { reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.18) }
}

extension HUDItem {
    var tint: Color {
        switch kind {
        case .volume: return .white
        case .mute: return Theme.faint
        case .brightness: return Theme.amber
        case .battery: return Theme.green
        case .done: return Theme.accent
        case .agent: return phase == .waiting || phase == .failed ? Theme.amber : Theme.agent
        case .device: return Theme.green
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

    private struct Key: Equatable { var state: NotchState; var compact: Int; var dropping: Bool; var metrics: Layout.Metrics; var content: CGFloat; var video: Layout.VideoSpec?; var hidden: Bool }
    private var state: NotchState { model.state(for: screen.id) }
    private var metrics: Layout.Metrics { screen.metrics }
    private var open: Bool { state == .expanded }
    /// Glass surfaces: the open panel and a notification card; the closed notch and HUDs stay solid black.
    private var glassy: Bool { open || state == .notification }
    private var video: Layout.VideoSpec? { open ? nil : model.videoSpec(on: screen.id) }
    private var slots: Int { model.compactSlots(on: screen.id) }
    /// Idle on a notchless screen: the notch draws back up into the menu bar and fades out.
    private var hidden: Bool { model.idleHidden(on: screen.id, physicalNotch: screen.physicalNotch) }
    private var size: CGSize { Layout.shapeSize(state, metrics, compactSlots: slots, content: model.shapeContent(state), video: video) }
    private var shape: NotchShape {
        let bottom: CGFloat = open ? 26 : state == .drop || state == .notification ? 24 : video.map { $0.large ? 22 : 18 } ?? 13
        return metrics.hasNotch
            ? NotchShape(topEar: Layout.ear(metrics, open: open), topRadius: 0, bottomRadius: bottom)
            : NotchShape(topEar: 0, topRadius: open ? 24 : bottom, bottomRadius: open ? 24 : bottom)
    }

    var body: some View {
        ZStack(alignment: .top) {
            surface.frame(width: size.width, height: size.height)
                .scaleEffect(x: hidden ? 0.7 : 1, y: hidden ? 0.2 : 1, anchor: .top)
                .opacity(hidden ? 0 : 1)
            // Always present so its top padding animates with the shape: the pill rides down with the panel.
            TabPill(model: model)
                .opacity(open && !model.cleaning.active ? 1 : 0)
                .scaleEffect(open ? 1 : 0.86, anchor: .top)
                .blur(radius: open ? 0 : 4)
                // On the way out the pill goes first and fast, so it never hangs under a shrinking panel.
                .animation(open ? Theme.motion(open: true) : .easeIn(duration: Theme.reduceMotion ? 0.1 : 0.14), value: open)
                .padding(.top, size.height + Layout.pillGap)
                .allowsHitTesting(open && !model.cleaning.active)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(state == .drop ? Theme.basket : Theme.motion(open: glassy), value: Key(state: state, compact: slots, dropping: dropping, metrics: metrics, content: model.shapeContent(state), video: video, hidden: hidden))
        .onChange(of: glassy, initial: true) { _, isOpen in
            // Glass is invisible under the solid black closed notch, so drop it there to spare the compositor.
            if isOpen { glassVisible = true }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { if !model.expanded && model.notifications.current == nil { glassVisible = false } } }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .active)
    }

    private var ambientColor: Color { media.accent.map { Color(nsColor: $0) } ?? .clear }
    /// How strongly the artwork colour fills the panel: full on Özet, a hint on other tabs.
    private var ambientStrength: Double {
        guard open, media.accent != nil, !model.cleaning.active else { return 0 }
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
                .init(color: .black.opacity(glassy ? 0.78 : 1), location: notchEdge + bodyHeight * 0.20),
                .init(color: .black.opacity(glassy ? 0.38 : 1), location: notchEdge + bodyHeight * 0.50),
                .init(color: .black.opacity(glassy ? 0.32 : 1), location: notchEdge + bodyHeight * 0.74),
                .init(color: .black.opacity(glassy ? 0 : 1), location: notchEdge + bodyHeight * 0.97),
                .init(color: .black.opacity(glassy ? 0 : 1), location: 1)
            ], startPoint: .top, endPoint: .bottom))
            // The glass alone loses its text over a white window behind it. The open panel always carries a dark
            // veil so every page reads on any background; lyrics (long white text, tall panel) go a little deeper.
            shape.fill(Color.black.opacity(open ? (model.tallPanel ? 0.55 : 0.45) : glassy ? 0.4 : 0))
                .animation(.easeInOut(duration: 0.35), value: model.tallPanel)
            content.shadow(color: .black.opacity(glassy ? 0.5 : 0), radius: 3, y: 1)
            // Outside the state switch, so a HUD over the notch leaves the video playing under it.
            if let video, state == .closed || state == .hud {
                VideoNotchView(model: model, video: model.video, media: media, size: Layout.videoSize(video, metrics, compactSlots: slots))
                    .padding(.top, Layout.closedHeight(metrics) + Layout.videoGap)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .clipShape(shape)
        .overlay {
            if dropping { shape.strokeBorder(Theme.accent.opacity(0.9), lineWidth: 1.5) }
        }
        .shadow(color: .black.opacity(glassy ? 0.45 : 0), radius: 24, y: 12)
        .contentShape(shape)
        .accessibilityAction(named: Text("Paneli aç")) {
            model.activeScreenID = screen.id
            model.expanded = true; model.pinnedOpen = true
        }
        .onTapGesture { if state != .expanded && state != .notification { model.activeScreenID = screen.id; model.expanded = true } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropping) { providers in
            guard model.enabledTabs.contains(.files) else { return false }   // no shelf, no drop target
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
            if value && !model.dragActive && model.enabledTabs.contains(.files) { model.activeScreenID = screen.id; model.selectedTab = .files; model.expanded = true }
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
                .frame(width: Layout.panelWidth, height: Layout.headerHeight(metrics) + model.contentHeight)
                .transition(AnyTransition.asymmetric(
                    insertion: AnyTransition(.blurReplace),
                    // Closing: the page draws back up into the notch rather than just vanishing.
                    removal: Theme.reduceMotion ? .opacity.animation(.easeOut(duration: 0.12))
                        : .modifier(active: Retreat(amount: 1), identity: Retreat(amount: 0)).animation(.easeIn(duration: 0.18))
                ))
        case .hud:
            if let hud = model.hud { HUDRow(hud: hud, metrics: metrics).transition(.blurReplace) }
        case .notification:
            NotificationCard(model: model, mirror: model.notifications)
                .padding(.top, Layout.closedHeight(metrics))
                .transition(.asymmetric(insertion: AnyTransition(.blurReplace).animation(.easeOut(duration: 0.25).delay(Theme.reduceMotion ? 0 : 0.08)),
                                        removal: AnyTransition(.blurReplace).animation(.easeIn(duration: 0.14))))
        case .drop:
            DropRow(metrics: metrics, targeted: dropping, count: model.files.count, dragged: model.dragURLs).transition(.blurReplace)
        case .closed:
            // The closed notch's activities come back once the panel has nearly folded away.
            CompactRow(model: model, media: media, metrics: metrics, screenID: screen.id)
                .transition(.asymmetric(insertion: AnyTransition(.blurReplace).animation(.easeOut(duration: 0.24).delay(Theme.reduceMotion ? 0 : 0.16)),
                                        removal: AnyTransition(.blurReplace)))
        }
    }
}

// MARK: - Closed notch

/// A live activity the closed notch can show. Each has a glyph (identity) and a status (motion).
enum CompactActivity: Equatable {
    case mic, timer, meeting, agent(AgentSession), media
    /// Left-to-right order when two share the island: mic, timer, meeting, media, the agent last.
    var rank: Int {
        switch self {
        case .mic: return 0; case .timer: return 1; case .meeting: return 2; case .media: return 3; case .agent: return 4
        }
    }
}

struct CompactRow: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    let metrics: Layout.Metrics
    var screenID: UInt32? = nil

    /// Up to two activities, the most urgent first: a live microphone, the timer, a meeting about to start,
    /// an agent, then media.
    private var activities: [CompactActivity] {
        var list: [CompactActivity] = []
        if model.micActive { list.append(.mic) }
        if model.session.hasStarted { list.append(.timer) }
        if model.calendar.soon != nil { list.append(.meeting) }
        if !(screenID.map(model.videoShown(on:)) ?? false) {   // the video under this notch already says what is playing
            if let agent = model.agentBadge { list.append(.agent(agent)) }
            if model.mediaInNotch { list.append(.media) }
        }
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
            case .mic: return model.microphone.muted ? String(localized: "Mikrofon kapalı · tıkla: aç") : String(localized: "Mikrofon kullanımda · tıkla: sessize al")
            case .meeting:
                guard let meeting = model.calendar.soon else { return "" }
                return meeting.title + (meeting.joinURL == nil ? "" : String(localized: " · tıkla: katıl"))
            case .timer: return "Odak · \(model.timeLabel)"
            case .agent(let agent): return "\(agent.provider.title) · \(agent.project) · \(agent.phase.title)"
            case .media:
                guard media.hasTrack else { return String(localized: "Müzik") }
                let other = media.otherPlaying.map { "\n\($0.title) · \(MediaService.appName(for: $0.bundleID))" } ?? ""
                return "\(media.title) · \(media.artist)" + other
            }
        }.joined(separator: "\n")
    }

    @ViewBuilder private func glyph(_ activity: CompactActivity) -> some View {
        switch activity {
        case .mic:
            Image(systemName: model.microphone.muted ? "mic.slash.fill" : "mic.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.microphone.muted ? Color(red: 1, green: 0.47, blue: 0.47) : Theme.amber)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22).contentShape(Rectangle())
                .onTapGesture { model.toggleMicrophone() }
        case .meeting:
            Image(systemName: model.calendar.soon?.joinURL == nil ? "calendar" : "video.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22).contentShape(Rectangle())
                .onTapGesture { if let meeting = model.calendar.soon { model.calendar.open(meeting) } }
        case .timer:
            Text(model.timeLabel).font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
        case .agent(let agent):
            AgentMascot(session: agent, size: 22, pulse: model.agentAttention)
                .onTapGesture { model.agents.activate(agent) }
                .help("\(agent.provider.title) · \(agent.project) · tıkla: \(agent.hostName ?? agent.provider.title)")
        case .media:
            Group {
                if let art = media.artwork {
                    Image(nsImage: art).resizable().scaledToFill().frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                } else {
                    Image(systemName: "music.note").font(.system(size: 11, weight: .semibold))
                }
            }
            // A second player is audible too (music left running under a video, two browsers…): its icon rides the corner.
            .overlay(alignment: .bottomTrailing) {
                if let other = media.otherPlaying, let icon = MediaService.icon(for: other.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.6), radius: 1.5)
                        .offset(x: 4, y: 3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Theme.quick, value: media.otherPlaying?.bundleID)
        }
    }

    @ViewBuilder private func status(_ activity: CompactActivity) -> some View {
        switch activity {
        case .mic:
            Text(model.microphone.muted ? "Kapalı" : "Açık").font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(model.microphone.muted ? Color(red: 1, green: 0.47, blue: 0.47) : Theme.dim)
                .onTapGesture { model.toggleMicrophone() }
        case .meeting:
            Text(model.calendar.soon.map { CalendarService.countdown($0) } ?? "").font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit().contentTransition(.numericText())
                .onTapGesture { if let meeting = model.calendar.soon { model.calendar.open(meeting) } }
        case .timer:
            Image(systemName: model.session.running ? "timer" : "pause.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
        case .agent(let agent):
            AgentStatusMark(session: agent)
        case .media:
            Equalizer(playing: media.playing, color: media.accent.map { Color(nsColor: $0) } ?? .white).opacity(media.playing ? 1 : 0.55)
        }
    }
}

// MARK: - Agent mascot

/// Damla's drop mascot acting out the session's phase, with the agent's app icon (Claude, Codex) as a badge
/// and, when the session runs in another app (Terminal, VS Code…), that host's icon in the lower-left corner.
struct AgentMascot: View {
    let session: AgentSession
    var size: CGFloat = 22
    var pulse = false
    var showHost = false
    private var tint: Color { session.phase == .waiting || session.phase == .failed ? Theme.amber : Theme.agent }
    var body: some View {
        // Damla's drop acts out the phase; the agent's own app icon rides the corner as a badge.
        DropletMascot(phase: session.phase, size: size)
            .overlay(alignment: .bottomTrailing) {
                if let icon = session.provider.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.44, height: size * 0.44)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).strokeBorder(.black, lineWidth: max(0.8, size * 0.03)))
                        .offset(x: size * 0.14, y: size * 0.08)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // The host badge only adds something when the session runs elsewhere (Terminal, VS Code…).
                if showHost, let host = session.hostIcon, !session.provider.bundleIDs.contains(session.host ?? "") {
                    Image(nsImage: host).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.4, height: size * 0.4)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).strokeBorder(.black, lineWidth: max(0.8, size * 0.03)))
                        .offset(x: -size * 0.14, y: size * 0.08)
                }
            }
            .scaleEffect(pulse ? 1.3 : 1)
            .shadow(color: tint.opacity(pulse ? 0.9 : 0), radius: pulse ? 10 : 0)
            .animation(Theme.reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.45, bounce: 0.55), value: pulse)
            .animation(Theme.quick, value: session.phase)
            .accessibilityLabel("\(session.provider.title) · \(session.phase.title)")
    }
}

/// Right-hand status beside the mascot: three thinking dots while working, the waiting time in amber
/// while an approval is pending, a symbol otherwise.
struct AgentStatusMark: View {
    let phase: AgentPhase
    var waitingSince: Date? = nil
    init(phase: AgentPhase) { self.phase = phase }
    init(session: AgentSession) { phase = session.phase; waitingSince = session.waitingSince }
    private var tint: Color { phase == .waiting || phase == .failed ? Theme.amber : Theme.agent }
    var body: some View {
        if phase == .working {
            ThinkingDots(color: tint)
        } else if phase == .waiting, let since = waitingSince {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(AgentText.duration(context.date.timeIntervalSince(since)))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                    .contentTransition(.numericText())
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
                if hud.kind == .device {
                    Text(hud.detail).font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
                        .minimumScaleFactor(0.8).foregroundStyle(Theme.green)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if hud.kind == .agent {
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
                        Text(dragged.count > 1 ? String(localized: "\(dragged.count) öğe") : first.lastPathComponent)
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
                if let step = model.tour {
                    TourView(step: step, model: model, keys: model.keys)
                } else {
                switch model.selectedTab {
                case .home:
                    switch model.homePane {
                    case .player: HomeView(model: model, media: model.media, lyrics: model.lyrics)
                    case .outputs: OutputsView(model: model)
                    case .levels: MixerView(model: model, media: model.media, apps: model.appVolumes)
                    case .sources: SourcesView(model: model, media: model.media)
                    case .videoSetup: VideoSetupView(model: model, setup: model.videoSetup)
                    }
                case .files: ShelfView(model: model)
                case .clipboard: ClipboardView(model: model)
                case .focus: FocusView(model: model)
                case .mirror: MirrorView()
                case .shortcuts: ShortcutsView(shortcuts: model.shortcuts)
                case .notifications: NotificationsView(model: model, mirror: model.notifications)
                case .agents: AgentPanelView(service: model.agents, servers: model.devServers)
                }
                }
            }
            // Follows the fingers during a swipe, dimming a little as it goes.
            .offset(x: model.swipeOffset)
            .opacity(1 - min(abs(model.swipeOffset) / 320, 0.45))
            .blur(radius: min(abs(model.swipeOffset) / 45, 3))
            .transition(.page(model.pageDirection))
            .id(model.tour.map { "tour-\($0.rawValue)" } ?? (model.selectedTab == .home ? "home-\(model.homePane)" : model.selectedTab.rawValue))
            .padding(.horizontal, 24).padding(.top, m.hasNotch ? 8 : 4).padding(.bottom, 18)
            .frame(width: Layout.panelWidth, height: model.contentHeight)
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
        .animation(Theme.page, value: model.selectedTab)
        .animation(Theme.page, value: model.tour)
    }
}

/// The open panel's content on its way back into the notch: a little smaller toward the top, up, out of focus.
private struct Retreat: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.07 * amount, anchor: .top)
            .offset(y: -12 * amount)
            .blur(radius: 7 * amount)
            .opacity(1 - amount)
    }
}

extension AnyTransition {
    /// A page change: the new page slides in a little from the side it lies on, coming into focus; the old one
    /// just fades and blurs away (its direction would be stale by the time it leaves).
    static func page(_ direction: Int) -> AnyTransition {
        guard !Theme.reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: PageShift(x: CGFloat(direction) * 26, blur: 6, opacity: 0), identity: PageShift(x: 0, blur: 0, opacity: 1)),
            removal: .modifier(active: PageShift(x: 0, blur: 4, opacity: 0), identity: PageShift(x: 0, blur: 0, opacity: 1))
                .animation(.easeOut(duration: 0.14)))
    }
}
private struct PageShift: ViewModifier {
    let x: CGFloat, blur: CGFloat, opacity: Double
    func body(content: Content) -> some View { content.offset(x: x).blur(radius: blur).opacity(opacity) }
}

struct TabPill: View {
    @ObservedObject var model: AppState
    @Namespace private var selection
    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.visibleTabs) { tab in
                let selected = model.selectedTab == tab
                Button { model.select(tab) } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: tab.icon).font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                            .frame(width: 34, height: 28)
                        if tab == .files, !model.files.isEmpty {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(x: -6, y: 5)
                        }
                        if tab == .notifications, model.notifications.unread > 0 {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(x: -6, y: 5)
                        }
                        if tab == .agents, let badge = model.agentBadge {
                            Circle().fill(badge.phase == .waiting ? Theme.amber : Theme.agent).frame(width: 5, height: 5).offset(x: -6, y: 5)
                        }
                    }
                    .foregroundStyle(selected ? Color.white : Theme.dim)
                    .background {
                        // One highlight that glides from tab to tab instead of fading out and in.
                        if selected { Capsule().fill(Theme.fillStrong).matchedGeometryEffect(id: "selected", in: selection) }
                    }
                    .contentShape(Capsule())
                }.buttonStyle(.plain).help(tab.title).accessibilityLabel(tab.title)
            }
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 14).padding(.horizontal, 4)
            pillButton(model.pinnedOpen ? "pin.fill" : "pin", "Açık tut", active: model.pinnedOpen) { model.pinnedOpen.toggle() }
            pillButton("gearshape", "Ayarlar", active: false) { model.openSettings() }
        }
        .padding(.horizontal, 5)
        .frame(height: Layout.pillHeight)
        .glassEffect(.clear.tint(.black.opacity(0.62)).interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .animation(Theme.page, value: model.selectedTab)
    }
    private func pillButton(_ icon: String, _ label: LocalizedStringKey, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).frame(width: 30, height: 28)
                .foregroundStyle(active ? Color.white : Theme.dim)
                .background(active ? Theme.fillStrong : .clear, in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).help(label).accessibilityLabel(Text(label))
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var lyrics: LyricsService
    @State private var appeared = false
    /// Cover size; the sound controls below share its column.
    static let art: CGFloat = 100
    private var tint: Color { media.accent.map { Color(nsColor: $0) } ?? .white }
    private func entrance(_ order: Double) -> Animation {
        Theme.reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.55, bounce: 0.22).delay(0.04 + order * 0.05)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Artwork(image: media.artwork, placeholder: media.hasTrack ? "music.note" : "waveform", size: Self.art)
                    .scaleEffect(appeared ? 1 : 0.72, anchor: .bottomLeading).opacity(appeared ? 1 : 0)
                    .animation(entrance(0), value: appeared)
                VStack(alignment: .leading, spacing: 3) {
                    if media.hasTrack {
                        // Centred, so the heart and the equalizer sit level with the title.
                        HStack(alignment: .center, spacing: 8) {
                            Text(media.title).font(.system(size: 15, weight: .semibold)).tracking(-0.2).lineLimit(1)
                            Spacer(minLength: 6)
                            // A browser or video player: its picture can play on under the closed notch.
                            if VideoNotch.canShow(media.sourceBundleID) {
                                Button { model.video.active ? model.stopVideo() : model.requestVideo() } label: {
                                    Group {
                                        if model.video.starting { ProgressView().controlSize(.mini) }
                                        else {
                                            Image(systemName: model.video.active ? "pip.exit" : "pip.enter").font(.system(size: 11.5, weight: .semibold))
                                                .foregroundStyle(model.video.active ? tint : Theme.dim)
                                        }
                                    }
                                    .frame(width: 18, height: 18).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(model.video.starting)
                                .help(model.video.active ? "Videoyu çentikten kaldır" : "Videoyu çentikte izle")
                            }
                            if let favorited = media.favorited {
                                Button { media.toggleFavorite() } label: {
                                    Image(systemName: favorited ? "heart.fill" : "heart").font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(favorited ? Color.pink : Theme.dim).contentTransition(.symbolEffect(.replace))
                                        .frame(width: 18, height: 18).contentShape(Rectangle())
                                }.buttonStyle(.plain).help(favorited ? "Favorilerden çıkar" : "Favorilere ekle")
                            }
                            Equalizer(playing: media.playing, color: tint).opacity(media.playing ? 1 : 0)
                        }
                        // Which app is playing sits with the name it belongs to.
                        HStack(spacing: 6) {
                            sourceControl
                            Text(media.artist).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if media.controllable && media.duration <= 0 {
                            // Live streams report no (or infinite) duration: nothing to scrub.
                            HStack(spacing: 5) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("CANLI").font(.system(size: 9.5, weight: .bold, design: .rounded)).tracking(0.6)
                                Spacer(minLength: 10)
                                if let meeting = meetingInTimes { meetingLine(meeting) }
                            }
                            .foregroundStyle(Theme.dim).frame(height: 29, alignment: .bottomLeading)
                        } else if media.controllable {
                            ScrubBar(position: media.livePosition(at: model.now), duration: media.duration, tint: tint,
                                     middle: meetingInTimes.map { AnyView(meetingLine($0)) }) { media.seek($0) }
                        } else {
                            HStack(spacing: 10) {
                                Label("Arka planda · son bilinen durum", systemImage: "rectangle.stack")
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
                                Spacer(minLength: 0)
                                if let meeting = meetingInTimes { meetingLine(meeting).layoutPriority(1) }
                            }
                            .frame(height: 29, alignment: .bottomLeading)
                        }
                    } else {
                        Text("Müzik").font(.system(size: 15, weight: .semibold))
                        Text(media.status ?? (media.bridgeActive ? String(localized: "Bir şey çal: Müzik, Spotify, Safari…") : String(localized: "Apple Music veya Spotify’ı bağla.")))
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
            .frame(height: Self.art)
            if model.tallPanel { Color.clear.frame(height: 12) } else { Spacer(minLength: 10) }
            // Two columns matching the row above: under the artwork the sound controls (output, level); under
            // the text the transport, centred on the progress line, with a running timer at its right end.
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    // Plain buttons: a SwiftUI Menu would flatten these labels to their first text.
                    // The output's name rides in the capsule, scrolling when it is too long. When the timer or a
                    // meeting takes the space to the right, only the icon stays.
                    let named = !model.session.hasStarted && meetingInTransport == nil
                    Button { withAnimation(Theme.quick) { model.homePane = .outputs } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: outputIcon).font(.system(size: 10.5, weight: .semibold))
                            if named {
                                MarqueeText(text: outputName, width: 50)
                                    .transition(.opacity)
                            }
                        }
                        .foregroundStyle(.white).padding(.horizontal, named ? 8 : 0).frame(minWidth: 28, minHeight: 28)
                        .glassLook(AnyShape(Capsule()))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(outputHelp)
                    .animation(Theme.quick, value: named)
                    if let volume = model.volume {
                        Button { withAnimation(Theme.quick) { model.homePane = .levels } } label: {
                            HStack(spacing: 4) {
                                Image(systemName: model.muted ? "speaker.slash.fill" : volume < 0.34 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(model.muted ? "0" : "\(Int(volume * 100))")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                            }
                            .foregroundStyle(.white).padding(.horizontal, 8).frame(height: 28)
                            .glassLook(AnyShape(Capsule()))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Ses seviyesi · sistem ve uygulama sesleri")
                    }
                }
                .fixedSize()   // may reach past the cover's column into the empty start of the transport zone
                .frame(width: Self.art, alignment: .leading)
                .zIndex(1)
                // Three columns: equal flexible ends keep the transport centred on the progress line, and whatever
                // sits at an end (the timer, the next meeting) is cut to its column instead of running under it.
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        if model.session.hasStarted {
                            Button { model.select(.focus) } label: {
                                statusLabel("timer", model.timeLabel, tint: model.session.running ? Theme.accent : nil)
                            }.buttonStyle(.plain).help("Odak")
                        } else if let meeting = meetingInTransport {
                            // The next meeting in the coming hours; a tap joins the call or opens Calendar.
                            Button { model.calendar.open(meeting) } label: { meetingChip(meeting) }
                                .buttonStyle(.plain)
                                .help(meeting.title + " · " + (meeting.joinURL == nil ? String(localized: "Takvimde aç") : String(localized: "Toplantıya katıl")))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    if media.hasTrack && !media.controllable {
                        Button { media.activateSource() } label: {
                            Label("Oynatıcıyı aç", systemImage: "arrow.up.forward.app").font(.system(size: 10.5, weight: .medium))
                        }.buttonStyle(PillStyle()).help("Tarayıcı sekmesi artık sistemin Şimdi Çalıyor kaynağı değil; kontrol için oynatıcıya geç.")
                        .fixedSize()
                    } else if media.hasTrack {
                        HStack(spacing: 14) {
                            transport("backward.fill", "Önceki", size: 13) { media.command("previous track") }
                            Button { media.command("playpause") } label: {
                                Image(systemName: media.playing ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                                    .frame(width: 36, height: 36).contentShape(Circle())
                                    .contentTransition(.symbolEffect(.replace))
                            }.buttonStyle(GlassCircleStyle()).help(media.playing ? "Duraklat" : "Oynat")
                            transport("forward.fill", "Sonraki", size: 13) { media.command("next track") }
                        }
                        .fixedSize()
                    }
                    // A failed lookup must remain reachable for retry. Keep the close button while the pane is
                    // open, including during a lookup; confirmed misses still fold it away.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if media.hasTrack && (lyrics.state == .found || lyrics.state == .off || lyrics.state == .failed || model.lyricsExpanded) {
                            Button {
                                // Lyrics mode on/off; turning it on also allows the lookup if it was off.
                                withAnimation(Theme.motion(open: !model.lyricsExpanded)) { model.lyricsExpanded.toggle() }
                                if model.lyricsExpanded && !lyrics.enabled { lyrics.enabled = true }
                                if model.lyricsExpanded && !UserDefaults.standard.bool(forKey: "lyricsNoticeShown") {
                                    UserDefaults.standard.set(true, forKey: "lyricsNoticeShown")
                                    model.showNotice(String(localized: "Sözler lrclib.net’ten gelir · yalnızca şarkı adı, sanatçı, albüm ve süre gönderilir"), duration: 7)
                                }
                            } label: {
                                Image(systemName: model.lyricsExpanded ? "quote.bubble.fill" : "quote.bubble").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(model.lyricsExpanded ? tint : .white).contentTransition(.symbolEffect(.replace))
                                    .frame(width: 28, height: 28).contentShape(Circle())
                            }
                            .buttonStyle(GlassCircleStyle())
                            .help(model.lyricsExpanded ? "Şarkı sözlerini kapat" : "Şarkı sözlerini aç")
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    // With nothing in the middle there is nothing to balance: the left end gets the whole row.
                    .frame(maxWidth: media.hasTrack ? .infinity : 0)
                    .animation(Theme.quick, value: lyrics.state)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 36)
            .offset(y: appeared ? 0 : 10).opacity(appeared ? 1 : 0)
            .animation(entrance(2), value: appeared)
            if model.tallPanel {
                LyricsFlow(model: model, media: media, lyrics: lyrics)
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity.combined(with: .offset(y: -12)))
            }
        }
        .onAppear { appeared = true }
    }
    /// The playing app's icon (several overlap when more than one player is known); in the Apple Events
    /// fallback, the picker between Apple Music and Spotify.
    @ViewBuilder private var sourceControl: some View {
        if media.bridgeActive, !media.sessions.isEmpty {
            SourceChip(model: model, media: media)
        } else if !media.bridgeActive && media.connected {
            Menu {
                ForEach(MusicSource.allCases) { source in Button(source.rawValue) { media.connect(source) } }
                Divider(); Button("Bağlantıyı kes") { media.disconnect() }
            } label: {
                Image(systemName: media.source == .spotify ? "circle.hexagongrid.fill" : "music.note").font(.system(size: 10, weight: .semibold))
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(media.source.rawValue)
        }
    }
    private var outputHelp: String {
        let name = model.outputs.first { $0.id == model.currentOutput }?.name ?? "—"
        guard let battery = model.currentOutputBattery else { return String(localized: "Ses çıkışı: \(name) · değiştir") }
        return String(localized: "Ses çıkışı: \(name) (\(battery.summary)) · değiştir")
    }
    private var outputIcon: String {
        model.outputs.first(where: { $0.id == model.currentOutput })?.icon ?? "hifispeaker"
    }
    /// Short enough for the capsule: "Hoparlör", "AirPods Pro", a display's name.
    private var outputName: String {
        guard let output = model.outputs.first(where: { $0.id == model.currentOutput }) else { return "Ses" }
        return AudioOutput.shortName(output.name, transport: output.transport)
    }
    private func statusLabel(_ icon: String, _ text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .medium))
            Text(text).font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
        }.foregroundStyle(tint ?? Theme.dim)
    }
    /// The next meeting sits in the line under the progress bar (between the times, or beside the live / background
    /// note), where there is room for its title; with nothing playing it takes the transport row instead.
    private var meetingInTimes: CalendarService.Meeting? {
        model.session.hasStarted || !media.hasTrack ? nil : model.calendar.upcoming
    }
    private var meetingInTransport: CalendarService.Meeting? {
        model.session.hasStarted || media.hasTrack ? nil : model.calendar.upcoming
    }
    private func meetingLine(_ meeting: CalendarService.Meeting) -> some View {
        let soon = model.calendar.isSoon(meeting)
        return Button { model.calendar.open(meeting) } label: {
            HStack(spacing: 4) {
                Image(systemName: meeting.joinURL == nil ? "calendar" : "video.fill").font(.system(size: 9, weight: .semibold))
                Text(CalendarService.countdown(meeting)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                    .fixedSize()
                Text(verbatim: "·").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.faint)
                Text(meeting.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.dim)
                    .lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(soon ? Theme.accent : .white.opacity(0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(meeting.title + " · " + (meeting.joinURL == nil ? String(localized: "Takvimde aç") : String(localized: "Toplantıya katıl")))
    }
    /// The next meeting as a small capsule: countdown first (it is what matters), the title after it, cut short
    /// to fit. Tinted when the meeting is under ten minutes away.
    private func meetingChip(_ meeting: CalendarService.Meeting) -> some View {
        let soon = model.calendar.isSoon(meeting)
        return HStack(spacing: 5) {
            Image(systemName: meeting.joinURL == nil ? "calendar" : "video.fill").font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(soon ? Theme.accent : .white.opacity(0.7))
            Text(CalendarService.countdown(meeting))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(soon ? Theme.accent : .white)
                .fixedSize()
            Text(meeting.title)
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.dim)
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 9).frame(height: 28)
        .glassLook(AnyShape(Capsule()))
        .contentShape(Capsule())
    }
    private func transport(_ icon: String, _ label: LocalizedStringKey, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(GlassCircleStyle()).help(label)
    }
}

/// The playing app beside the artist. With one player a tap brings it forward; with several a count shows and a
/// tap opens the Kaynaklar list to switch between them.
struct SourceChip: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    var body: some View {
        let count = media.sessions.count
        Button {
            if count > 1 { withAnimation(Theme.quick) { model.homePane = .sources } } else { media.activateSource() }
        } label: {
            HStack(spacing: 4) {
                if let icon = media.sourceIcon {
                    Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                } else {
                    Image(systemName: "music.note").font(.system(size: 9, weight: .semibold)).frame(width: 15, height: 15)
                }
                if count > 1 {
                    HStack(spacing: 2) {
                        Text("\(count)").font(.system(size: 9.5, weight: .bold, design: .rounded)).monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 6.5, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 5).frame(height: 15)
                    .background(Theme.fillStrong, in: Capsule())
                    .overlay(alignment: .topTrailing) {
                        // Another source is playing too: a mint dot on the count.
                        if media.otherPlaying != nil { Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(x: 2, y: -1) }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(count > 1 ? "\(count) kaynak · geçiş yap" : "\(MediaService.appName(for: media.sourceBundleID ?? "")) · uygulamayı aç")
    }
}

/// One line that fits a fixed width: shown as is when short, otherwise scrolling slowly right to left with a pause
/// at the start, fading at both edges. The scroll is a Core Animation loop: a SwiftUI repeatForever animation
/// here re-ran the whole notch window's update every frame (measured +5.7% CPU with the panel open).
struct MarqueeText: NSViewRepresentable {
    let text: String
    let width: CGFloat
    var font: NSFont = MarqueeText.defaultFont
    static let defaultFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 10.5) } ?? base
    }()
    func makeNSView(context: Context) -> MarqueeLayerView { MarqueeLayerView() }
    func updateNSView(_ view: MarqueeLayerView, context: Context) {
        guard view.text != text || view.maxWidth != width || view.font != font else { return }
        view.text = text; view.maxWidth = width; view.font = font
        view.setAccessibilityLabel(text)
        view.install()
        view.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeLayerView, context: Context) -> CGSize? {
        CGSize(width: min(nsView.textSize.width, width), height: nsView.textSize.height)
    }
}

final class MarqueeLayerView: LoopLayerView {
    var text = ""
    var maxWidth: CGFloat = 50
    var font: NSFont = MarqueeText.defaultFont
    private static let gap: CGFloat = 22, speed: CGFloat = 22, pause: Double = 1.6
    var textSize: CGSize { (text as NSString).size(withAttributes: [.font: font]) }
    private let strip = CALayer()

    override var isFlipped: Bool { true }
    override func install() {
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let size = textSize
        let overflow = size.width > maxWidth
        strip.removeAllAnimations()
        strip.sublayers?.forEach { $0.removeFromSuperlayer() }
        if strip.superlayer == nil { layer.addSublayer(strip) }
        let scale = window?.backingScaleFactor ?? 2
        for copy in 0..<(overflow ? 2 : 1) {
            let label = CATextLayer()
            label.string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
            label.contentsScale = scale
            label.frame = CGRect(x: CGFloat(copy) * (size.width + Self.gap), y: 0, width: ceil(size.width) + 1, height: ceil(size.height))
            strip.addSublayer(label)
        }
        strip.frame = CGRect(x: 0, y: 0, width: size.width * 2 + Self.gap, height: size.height)
        layer.masksToBounds = true
        if overflow {
            let fade = CAGradientLayer()
            fade.frame = CGRect(x: 0, y: 0, width: maxWidth, height: size.height)
            fade.startPoint = CGPoint(x: 0, y: 0.5); fade.endPoint = CGPoint(x: 1, y: 0.5)
            fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            fade.locations = [0, 0.04, 0.9, 1]
            layer.mask = fade
            // Rest at the start, then one smooth pass; the copy behind makes the jump back invisible.
            let travel = size.width + Self.gap
            let move = Double(travel / Self.speed), total = Self.pause + move
            let scroll = CAKeyframeAnimation(keyPath: "position.x")
            let start = strip.frame.width / 2
            scroll.values = [start, start, start - travel]
            scroll.keyTimes = [0, NSNumber(value: Self.pause / total), 1]
            scroll.duration = total
            scroll.repeatCount = .infinity
            scroll.isRemovedOnCompletion = false
            strip.add(scroll, forKey: "marquee")
        } else {
            layer.mask = nil
        }
        CATransaction.commit()
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
    /// Something short between the two times (the next meeting); cut to the gap, never over the times.
    var middle: AnyView? = nil
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
            HStack(spacing: 10) {
                Text(Self.format(shown))
                Spacer(minLength: 0)
                Text("-" + Self.format(max(0, duration - shown)))
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Theme.faint)
            .overlay { middle.padding(.horizontal, 46) }
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
            let actions = ShelfAction.available(for: item.url, shelf: model.files.map(\.url))
            if !actions.isEmpty {
                Divider()
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { model.runShelfAction(action, on: item) }
                }
            }
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
    private var kindLabel: String { entry.kind == .image ? String(localized: "Görsel") : isColor ? String(localized: "Renk") : isLink ? String(localized: "Bağlantı") : String(localized: "Metin") }
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
    @State private var editing = false
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool
    // Turning the dial: the minutes under the finger, and where the drag has got to.
    @State private var dialMinutes: Int?
    @State private var dialBase = 0
    @State private var dialAngle: Double?
    @State private var dialTurned: Double = 0
    @State private var dialHover = false

    /// A fresh timer is set by turning the ring like a dial; a running or paused one shows its progress.
    private var dialMode: Bool { !model.session.running && !model.session.hasStarted && !editing }
    private var setMinutes: Int { dialMinutes ?? Int(model.session.duration / 60) }

    var body: some View {
        let running = model.session.running
        HStack(spacing: 26) {
            ZStack {
                Circle().stroke(.white.opacity(dialMode && setMinutes >= 60 ? 0.22 : 0.1), lineWidth: 4)
                if dialMode {
                    FocusDial(minutes: setMinutes, active: dialMinutes != nil || dialHover)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Circle().trim(from: 0, to: model.session.progress(at: model.now))
                        .stroke(running ? Theme.accent : .white.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(.linear(duration: 0.5), value: model.now)
                        .shadow(color: Theme.accent.opacity(running ? 0.5 : 0), radius: 6)
                        .transition(.opacity)
                }
                VStack(spacing: 4) {
                    Image(systemName: model.session.phase == .focus ? "brain.head.profile" : "cup.and.saucer").font(.system(size: 12)).foregroundStyle(Theme.dim)
                    if editing {
                        // Type any length: minutes, 1 to 240.
                        HStack(spacing: 3) {
                            TextField("", text: $typed)
                                .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                                .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                                .frame(width: 56).focused($fieldFocused)
                                .onSubmit(commit)
                                .onExitCommand { editing = false }
                                .onChange(of: typed) { _, value in
                                    let digits = String(value.filter(\.isNumber).prefix(3))
                                    if digits != value { typed = digits }
                                }
                            Text("dk").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
                        }
                    } else {
                        Text(dialMinutes.map { String(format: "%02d:00", $0) } ?? model.timeLabel)
                            .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit().tracking(-1)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.18), value: setMinutes)
                            .onTapGesture { startEditing() }
                            .help(running ? "" : String(localized: "Halkayı çevir, tıklayıp yaz ya da kaydır"))
                    }
                }
            }
            .frame(width: 128, height: 128)
            .contentShape(Circle().inset(by: -10))
            .gesture(dialGesture, including: dialMode ? .all : .subviews)
            .onHover { inside in withAnimation(.easeOut(duration: 0.2)) { dialHover = inside } }
            .animation(.spring(duration: 0.45, bounce: 0.25), value: dialMode)
            .overlay(ScrollCatcher { steps in model.adjustFocus(by: steps) }.allowsHitTesting(!running && !editing))
            .onChange(of: fieldFocused) { _, focused in if !focused && editing { commit() } }
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

    /// Dragging around the ring: 6° a minute, one turn is an hour, several turns up to four hours. The drag counts
    /// how far the finger turned, so the handle never jumps to where it was grabbed. Near the centre it is left
    /// to the time (tap to type).
    private var dialGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                let center = CGPoint(x: 64, y: 64)
                let dx = value.location.x - center.x, dy = value.location.y - center.y
                let start = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
                guard dialMode, start > 36 else { return }
                let angle = atan2(dx, -dy) * 180 / .pi
                if dialAngle == nil {
                    dialBase = Int(model.session.duration / 60); dialTurned = 0; dialAngle = angle
                    withAnimation(.spring(duration: 0.25)) { dialMinutes = dialBase }
                    return
                }
                var delta = angle - (dialAngle ?? angle)
                if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
                dialAngle = angle
                dialTurned += delta
                let minutes = min(max(dialBase + Int((dialTurned / 6).rounded()), AppState.focusMinutes.lowerBound), AppState.focusMinutes.upperBound)
                if minutes != dialMinutes {
                    dialMinutes = minutes
                    NSHapticFeedbackManager.defaultPerformer.perform(minutes % 5 == 0 ? .levelChange : .alignment, performanceTime: .now)
                }
            }
            .onEnded { _ in
                if let minutes = dialMinutes { model.setFocus(minutes: minutes) }
                withAnimation(.spring(duration: 0.3)) { dialMinutes = nil }
                dialAngle = nil
            }
    }

    private func startEditing() {
        guard !model.session.running else { return }
        typed = String(Int(model.session.duration / 60))
        editing = true
        model.requestKeyFocus?()
        DispatchQueue.main.async { fieldFocused = true }
    }
    private func commit() {
        if let minutes = Int(typed), minutes > 0 { model.setFocus(minutes: minutes, phase: model.session.phase) }
        editing = false
    }
}

/// The dial around a fresh timer: sixty ticks (every fifth longer), those up to the set minute lit, and a handle
/// on the ring at the set minute. One turn is an hour; the handle keeps going round for longer sessions.
struct FocusDial: View {
    let minutes: Int
    let active: Bool
    private var lap: Int { minutes % 60 == 0 && minutes > 0 ? 60 : minutes % 60 }
    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for tick in 0..<60 {
                    let angle = Double(tick) / 60 * 2 * .pi
                    let long = tick % 5 == 0
                    let outer = size.width / 2 - 9, inner = outer - (long ? 7 : 3.5)
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + sin(angle) * inner, y: center.y - cos(angle) * inner))
                    path.addLine(to: CGPoint(x: center.x + sin(angle) * outer, y: center.y - cos(angle) * outer))
                    let lit = tick < lap
                    let color = lit ? Theme.accent.opacity(active ? 1 : 0.75) : Color.white.opacity(active ? 0.35 : 0.16)
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: long ? 1.6 : 1, lineCap: .round))
                }
            }
            Circle().trim(from: 0, to: CGFloat(lap) / 60)
                .stroke(Theme.accent.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // The handle rides the ring.
            Circle().fill(.white)
                .frame(width: 14, height: 14)
                .shadow(color: Theme.accent.opacity(0.8), radius: active ? 7 : 3)
                .scaleEffect(active ? 1.25 : 1)
                .offset(y: -64)
                // Total minutes, not the lap: past the hour the handle keeps turning forward instead of unwinding.
                .rotationEffect(.degrees(Double(minutes) / 60 * 360))
                .animation(.spring(duration: 0.22, bounce: 0.2), value: minutes)
        }
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

/// Turns scrolling over a view into whole steps (up = +1) without taking its clicks: it only claims the pointer
/// for scroll events. A trackpad needs about 12 points of travel per step; a mouse wheel click is one step.
struct ScrollCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void
    func makeNSView(context: Context) -> CatcherView { CatcherView(onStep: onStep) }
    func updateNSView(_ view: CatcherView, context: Context) { view.onStep = onStep }

    final class CatcherView: NSView {
        var onStep: (Int) -> Void
        private var pending: CGFloat = 0
        init(onStep: @escaping (Int) -> Void) { self.onStep = onStep; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }
        override func scrollWheel(with event: NSEvent) {
            if !event.momentumPhase.isEmpty { return }
            let up = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            guard event.hasPreciseScrollingDeltas else { if up != 0 { onStep(up > 0 ? 1 : -1) }; return }
            if event.phase.contains(.began) { pending = 0 }
            pending += up
            let steps = Int(pending / 12)
            if steps != 0 { pending -= CGFloat(steps) * 12; onStep(steps) }
        }
    }
}

// MARK: - Settings

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
    let label: LocalizedStringKey
    var tint: Color = .white
    var size: CGFloat = 26
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(tint)
                .frame(width: size, height: size).contentShape(Circle())
        }
        .buttonStyle(GlassCircleStyle())
        .help(label).accessibilityLabel(Text(label))
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

/// Switch drawn in the panel's own glass language: mint track when on, white knob, no dependence on the
/// system accent (NSSwitch ignores `tint` inside this non-key panel on macOS 27).
struct GlassSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.accent : .white.opacity(0.14))
                    .overlay(Capsule().strokeBorder(.white.opacity(configuration.isOn ? 0.35 : 0.12), lineWidth: 0.6))
                Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .frame(width: 34, height: 20)
            .contentShape(Capsule())
            .animation(Theme.quick, value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text("açık") : Text("kapalı"))
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
