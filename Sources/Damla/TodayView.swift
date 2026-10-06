import AppKit
import SwiftUI

/// Özet when nothing was playing as the panel opened: a greeting, the day at a glance (next meeting, focus
/// rounds, agents) and the paused track one tap from playing again. Each tile leads to the page behind it.
struct TodayView: View {
    @ObservedObject var model: AppState
    @ObservedObject var media: MediaService
    @ObservedObject var agents: AgentStatusService
    @ObservedObject var calendar: CalendarService

    var body: some View {
        let tiles = visibleTiles
        VStack(alignment: .leading, spacing: 8) {
            header
            if tiles.isEmpty {
                // Nothing else to report: the paused track (or the way to start one) takes the room.
                Spacer(minLength: 0)
                bigPlayer
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 7) {
                    // Fewer tiles share the row between them; a lone one spreads out and brings its action along.
                    let wide = tiles.count == 1
                    ForEach(tiles, id: \.self) { kind in
                        switch kind {
                        case .meeting: meetingTile(wide: wide)
                        case .focus: focusTile(wide: wide)
                        case .agents: agentTile(wide: wide)
                        }
                    }
                }
                .frame(height: 74)
                playerRow.frame(height: 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A lone agents tile shows the limits; Codex's are read only while someone is looking (a counted watch).
        .onAppear { agents.watchCodexUsage(true) }
        .onDisappear { agents.watchCodexUsage(false) }
    }

    // MARK: Which tiles

    enum Tile { case meeting, focus, agents }

    /// Only what is in use earns a tile: a meeting today, a timer running or rounds done today, agents at work
    /// today. A waiting approval always shows, whatever the pages.
    private var visibleTiles: [Tile] {
        var tiles: [Tile] = []
        if todaysMeeting != nil { tiles.append(.meeting) }
        if model.session.hasStarted || (model.completedSessions > 0 && model.visibleTabs.contains(.focus)) { tiles.append(.focus) }
        let counts = agentCounts
        if counts.waiting > 0 || (model.visibleTabs.contains(.agents) && (counts.working > 0 || agents.todayTurns > 0)) {
            tiles.append(.agents)
        }
        return tiles
    }

    private var todaysMeeting: CalendarService.Meeting? {
        guard calendar.enabled else { return nil }
        return calendar.next.flatMap { Calendar.current.isDateInToday($0.start) || $0.start < Date() ? $0 : nil }
    }

    private var agentCounts: (waiting: Int, working: Int) {
        let phases = agents.sessions.map { $0.effectivePhase(at: model.now) }
        return (max(agents.approvals.count, phases.filter { $0 == .waiting }.count), phases.filter { $0 == .working }.count)
    }

    // MARK: Greeting

    private var header: some View {
        HStack(spacing: 7) {
            // The drop mirrors the agents: amber and waving when one waits, hopping while one works.
            DropletMascot(phase: mascotPhase, size: 22)
            Text(verbatim: Self.greeting()).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text(verbatim: "· " + Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 26)
    }

    /// "Günaydın, Erkam": the part of the day, then the first name of the Mac's account when there is one.
    static func greeting(at date: Date = Date(), fullName: String = NSFullUserName()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = switch hour {
        case 5..<12: String(localized: "Günaydın")
        case 12..<18: String(localized: "İyi günler")
        case 18..<22: String(localized: "İyi akşamlar")
        default: String(localized: "İyi geceler")
        }
        guard let first = fullName.split(separator: " ").first, !first.isEmpty else { return part }
        return "\(part), \(first)"
    }

    private var mascotPhase: AgentPhase {
        let phases = agents.sessions.map { $0.effectivePhase(at: model.now) }
        if !agents.approvals.isEmpty || phases.contains(.waiting) { return .waiting }
        return phases.contains(.working) ? .working : .idle
    }

    // MARK: Tiles

    private func meetingTile(wide: Bool) -> some View {
        let meeting = todaysMeeting
        return tile(icon: meeting?.joinURL == nil ? "calendar" : "video.fill", label: Text("Sıradaki"),
                    help: meeting.map { _ in String(localized: "Toplantıyı aç") } ?? String(localized: "Takvim")) {
            if let meeting { calendar.open(meeting) } else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
        } accessory: {
            if wide, let meeting, meeting.joinURL != nil {
                Button { calendar.open(meeting) } label: { Label("Katıl", systemImage: "video.fill").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(PillStyle(accent: true))
            }
        } content: {
            if let meeting {
                Text(meeting.start <= Date() ? String(localized: "Şimdi") : meeting.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(meeting.title).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            } else {
                Text("Boş").font(.system(size: 15, weight: .semibold))
                Text("Bugün başka yok").font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
        }
    }

    private func focusTile(wide: Bool) -> some View {
        let session = model.session
        let completed = model.completedSessions
        return tile(icon: session.phase == .rest && session.hasStarted ? "cup.and.saucer" : "timer", label: Text("Odak"),
                    help: String(localized: "Odak sayfasını aç")) {
            model.select(.focus)
        } accessory: {
            if wide {
                Button { model.toggleFocus() } label: {
                    Image(systemName: session.running ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34).contentShape(Circle())
                }
                .buttonStyle(GlassCircleStyle(prominent: true)).help(session.running ? "Duraklat" : "Başlat")
            }
        } content: {
            if session.hasStarted {
                Text(model.timeLabel).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(session.running ? (session.phase == .focus ? LocalizedStringKey("Odakta") : "Molada") : "Duraklatıldı")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(completed)").font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("tur").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
                }
                HStack(spacing: 4) {
                    let lit = FocusCycle.filled(completed: completed, phase: .focus)
                    ForEach(0..<FocusCycle.length, id: \.self) { index in
                        Circle().fill(index < lit ? Color.white : .clear)
                            .overlay(Circle().strokeBorder(.white.opacity(index < lit ? 0 : 0.4), lineWidth: 1.1))
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 13)
            }
        }
    }

    private func agentTile(wide: Bool) -> some View {
        let (waiting, working) = agentCounts
        // Amber only when something waits on the user; otherwise the tile stays quiet.
        return tile(icon: "terminal", label: Text("Agent’lar"), tint: waiting > 0 ? Theme.amber : nil,
                    help: String(localized: "Agent’lar sayfasını aç")) {
            model.select(.agents)
        } accessory: {
            if wide {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach([("Claude", agents.usage), ("Codex", agents.codexUsage)], id: \.0) { name, usage in
                        if let percent = usage.flatMap({ [$0.fiveHour?.percent, $0.sevenDay?.percent].compactMap { $0 }.max() }) {
                            Text(verbatim: "\(name) %\(Int(percent.rounded()))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(percent >= 90 ? Theme.red : percent >= 75 ? Theme.amber : Theme.dim)
                        }
                    }
                }
            }
        } content: {
            Group {
                if waiting > 0 { Text("\(waiting) onay") }
                else if working > 0 { Text("\(working) çalışıyor") }
                else { Text("Sakin") }
            }
            .font(.system(size: waiting > 0 || working > 0 ? 17 : 15, weight: .semibold)).lineLimit(1)
            .foregroundStyle(waiting > 0 ? Theme.amber : .white)
            Text(agents.todayTurns > 0 ? String(localized: "Bugün \(agents.todayTurns) tur") : String(localized: "Bugün tur yok"))
                .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
        }
    }

    /// A tile opens its page when tapped; its accessory (a lone tile's own action) sits apart on the right, so the
    /// two never swallow each other's clicks.
    private func tile<Content: View, Accessory: View>(icon: String, label: Text, tint: Color? = nil, help: String,
                                                      action: @escaping () -> Void, @ViewBuilder accessory: () -> Accessory,
                                                      @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
                    label.font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(tint ?? Theme.dim)
                Spacer(minLength: 0)
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .help(help)
            accessory()
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.6))
    }

    // MARK: Paused track

    /// The paused track as a card of its own when there are no tiles above it.
    @ViewBuilder private var bigPlayer: some View {
        if media.hasTrack {
            HStack(spacing: 14) {
                Button { model.homeShowsToday = false } label: {
                    HStack(spacing: 14) {
                        Artwork(image: media.artwork, placeholder: "music.note", size: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(media.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(media.artist).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                            Text("duraklatıldı").font(.system(size: 11)).foregroundStyle(Theme.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Oynatıcıyı göster")
                Button { media.command("playpause") } label: {
                    Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(GlassCircleStyle(prominent: true)).help("Çal").accessibilityLabel("Çal")
            }
        } else {
            playerRow
        }
    }

    @ViewBuilder private var playerRow: some View {
        if media.hasTrack {
            HStack(spacing: 10) {
                Button { model.homeShowsToday = false } label: {
                    HStack(spacing: 10) {
                        Artwork(image: media.artwork, placeholder: "music.note", size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(media.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Text(verbatim: "\(media.artist) · \(String(localized: "duraklatıldı"))")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.faint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Oynatıcıyı göster")
                Button { media.command("playpause") } label: {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32).contentShape(Circle())
                }
                .buttonStyle(GlassCircleStyle(prominent: true)).help("Çal").accessibilityLabel("Çal")
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "music.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                Text(media.bridgeActive ? LocalizedStringKey("Bir şey çal: Müzik, Spotify, Safari…") : "Müziği bağla")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(1)
                Spacer(minLength: 0)
                if !media.bridgeActive {
                    ForEach(MusicSource.allCases) { source in
                        Button(source.rawValue) { media.connect(source) }.font(.system(size: 10.5, weight: .medium)).buttonStyle(PillStyle())
                    }
                }
            }
        }
    }
}
