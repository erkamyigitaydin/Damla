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
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 7) {
                if calendar.enabled { meetingTile }
                focusTile
                agentTile
            }
            .frame(height: 74)
            playerRow.frame(height: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var meetingTile: some View {
        let meeting = calendar.next.flatMap { Calendar.current.isDateInToday($0.start) || $0.start < Date() ? $0 : nil }
        return tile(icon: meeting?.joinURL == nil ? "calendar" : "video.fill", label: Text("Sıradaki"),
                    help: meeting.map { _ in String(localized: "Toplantıyı aç") } ?? String(localized: "Takvim")) {
            if let meeting { calendar.open(meeting) } else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
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

    private var focusTile: some View {
        let session = model.session
        let completed = model.completedSessions
        return tile(icon: session.phase == .rest && session.hasStarted ? "cup.and.saucer" : "timer", label: Text("Odak"),
                    help: String(localized: "Odak sayfasını aç")) {
            model.select(.focus)
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

    private var agentTile: some View {
        let phases = agents.sessions.map { $0.effectivePhase(at: model.now) }
        let waiting = max(agents.approvals.count, phases.filter { $0 == .waiting }.count)
        let working = phases.filter { $0 == .working }.count
        // Amber only when something waits on the user; otherwise the tile stays quiet.
        return tile(icon: "terminal", label: Text("Agent’lar"), tint: waiting > 0 ? Theme.amber : nil,
                    help: String(localized: "Agent’lar sayfasını aç")) {
            model.select(.agents)
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

    private func tile<Content: View>(icon: String, label: Text, tint: Color? = nil, help: String,
                                     action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
                    label.font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(tint ?? Theme.dim)
                Spacer(minLength: 0)
                content()
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.6))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Paused track

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
