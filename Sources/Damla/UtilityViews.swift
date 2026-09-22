import SwiftUI

struct CleaningPanelView: View {
    @ObservedObject var cleaning: KeyboardCleaning
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 24)).foregroundStyle(Theme.accent)
                Text("Klavye kilitli").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(cleaning.remaining) sn").font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
            }
            Text("Fare çalışır. Süre sonunda klavye otomatik açılır.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("Esc’yi 2 sn basılı tut veya").font(.system(size: 11)).foregroundStyle(Theme.dim)
                Button("Kilidi aç") { cleaning.stop() }.font(.system(size: 12, weight: .semibold)).buttonStyle(PillStyle(accent: true))
            }
            Text("Güç / Touch ID tuşu kilitlenmez.").font(.system(size: 10)).foregroundStyle(Theme.faint)
        }
        .foregroundStyle(.white).padding(.horizontal, 28).frame(height: Layout.contentHeight)
    }
}

// MARK: - Agents

enum AgentText {
    /// "42 sn", "4 dk", "1 sa 12 dk"; with `seconds` on, "3 dk 12 sn" for the waiting timer.
    static func duration(_ interval: TimeInterval, seconds: Bool = false) -> String {
        let total = max(0, Int(interval))
        if total < 60 { return "\(total) sn" }
        if total < 3600 { return seconds ? "\(total / 60) dk \(total % 60) sn" : "\(total / 60) dk" }
        return "\(total / 3600) sa \(total % 3600 / 60) dk"
    }

    /// One line under the project name: what the agent is doing, for how long, how much it has done.
    static func activity(_ s: AgentSession, at now: Date) -> (text: String, urgent: Bool) {
        let phase = s.effectivePhase(at: now)
        var parts: [String] = []
        switch phase {
        case .working:
            parts.append(s.tool.map(AgentSession.toolLabel) ?? "Düşünüyor")
            if let start = s.turnStarted { parts.append(duration(now.timeIntervalSince(start))) }
        case .waiting:
            if let tool = s.waitingTool, AgentSession.questionTools.contains(tool) { parts.append("Yanıt bekliyor") }
            else if let tool = s.waitingTool { parts.append("\(tool) için onay bekliyor") }
            else { parts.append(s.detail.isEmpty ? "Onay bekliyor" : s.detail) }
            if let since = s.waitingSince { parts.append(duration(now.timeIntervalSince(since), seconds: true)) }
        case .done, .failed, .interrupted:
            parts.append(phase.shortTitle)
            if let start = s.turnStarted { parts.append(duration(s.updated.timeIntervalSince(start))) }
        case .idle, .stale:
            parts.append(phase.title)
        }
        if let calls = s.toolCalls, calls > 0, phase != .idle { parts.append("\(calls) çağrı") }
        return (parts.joined(separator: " · "), phase == .waiting || phase == .failed)
    }

    static func summary(_ sessions: [AgentSession], turns: Int, at now: Date) -> String {
        let phases = sessions.map { $0.effectivePhase(at: now) }
        let working = phases.filter { $0 == .working }.count
        let waiting = phases.filter { $0 == .waiting }.count
        var parts: [String] = []
        if working > 0 { parts.append("\(working) çalışıyor") }
        if waiting > 0 { parts.append("\(waiting) onay bekliyor") }
        if parts.isEmpty { parts.append("Aktif oturum yok") }
        if turns > 0 { parts.append("bugün \(turns) tur") }
        return parts.joined(separator: " · ")
    }
}

struct AgentPanelView: View {
    @ObservedObject var service: AgentStatusService
    @State private var showHistory = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let active = service.sessions.filter { $0.isActive(at: now) }
            let history = service.sessions.filter { !$0.isActive(at: now) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(AgentText.summary(service.sessions, turns: service.todayTurns, at: now))
                        .font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    Spacer()
                    IconButton(icon: service.soundEnabled ? "bell.fill" : "bell.slash", label: service.soundEnabled ? "Onay beklerken ses: açık" : "Onay beklerken ses: kapalı",
                               tint: service.soundEnabled ? Theme.accent : .white, size: 22) { service.soundEnabled.toggle() }
                }
                if service.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Henüz durum gelmedi", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .medium))
                        Text("Bağlı bir Claude Code veya Codex oturumunda yeni bir mesajla başlar.")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim)
                        Text("Codex ilk bağlantıda /hooks üzerinden güven onayı ister.")
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(active) { AgentRow(session: $0, now: now, service: service) }
                            if !history.isEmpty {
                                Button { withAnimation(Theme.quick) { showHistory.toggle() } } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                            .rotationEffect(.degrees(showHistory ? 90 : 0))
                                        Text("Geçmiş · \(history.count)").font(.system(size: 10.5, weight: .medium))
                                        Spacer()
                                    }
                                    .foregroundStyle(Theme.dim).padding(.horizontal, 8).frame(height: 22).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if showHistory {
                                    ForEach(history) { AgentRow(session: $0, now: now, service: service).opacity(0.75) }
                                }
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }
        }
    }
}

struct AgentRow: View {
    let session: AgentSession
    let now: Date
    @ObservedObject var service: AgentStatusService
    @State private var hovering = false
    var body: some View {
        let activity = AgentText.activity(session, at: now)
        Button { service.activate(session) } label: {
            HStack(spacing: 9) {
                AgentMascot(session: session, size: 24, showHost: true).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(session.project).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        Text(session.provider.title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.faint)
                    }
                    Text(activity.text).font(.system(size: 10)).foregroundStyle(activity.urgent ? Theme.amber : Theme.dim).lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 4)
                if hovering {
                    IconButton(icon: "xmark", label: "Listeden kaldır", size: 18) { service.remove(session) }
                } else {
                    Text(session.updated, style: .relative).font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.faint)
                }
            }
            .padding(8)
            .background(hovering ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Tıkla: \(session.hostName ?? session.provider.title) öne gelsin")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("\(session.hostName ?? session.provider.title) uygulamasına git") { service.activate(session) }
            Divider()
            Button("Listeden kaldır") { service.remove(session) }
        }
    }
}
