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
        if total < 60 { return String(localized: "\(total) sn") }
        if total < 3600 { return seconds ? String(localized: "\(total / 60) dk \(total % 60) sn") : String(localized: "\(total / 60) dk") }
        return String(localized: "\(total / 3600) sa \(total % 3600 / 60) dk")
    }

    /// One line under the project name: what the agent is doing, for how long, how much it has done.
    static func activity(_ s: AgentSession, at now: Date) -> (text: String, urgent: Bool) {
        let phase = s.effectivePhase(at: now)
        var parts: [String] = []
        switch phase {
        case .working:
            parts.append(s.tool.map(AgentSession.toolLabel) ?? String(localized: "Düşünüyor"))
            if let start = s.turnStarted { parts.append(duration(now.timeIntervalSince(start))) }
        case .waiting:
            if let tool = s.waitingTool, AgentSession.questionTools.contains(tool) { parts.append(String(localized: "Yanıt bekliyor")) }
            else if let tool = s.waitingTool { parts.append(String(localized: "\(tool) için onay bekliyor")) }
            else { parts.append(s.detail.isEmpty ? String(localized: "Onay bekliyor") : s.detail) }
            if let since = s.waitingSince { parts.append(duration(now.timeIntervalSince(since), seconds: true)) }
        case .done, .failed, .interrupted:
            parts.append(phase.shortTitle)
            if let start = s.turnStarted { parts.append(duration(s.updated.timeIntervalSince(start))) }
        case .idle, .stale:
            parts.append(phase.title)
        }
        if let calls = s.toolCalls, calls > 0, phase != .idle { parts.append(String(localized: "\(calls) çağrı")) }
        return (parts.joined(separator: " · "), phase == .waiting || phase == .failed)
    }

    /// A small picture for a tool in the trail on the big card.
    static func symbol(for tool: String) -> String {
        switch tool {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebFetch", "WebSearch": return "globe"
        case "Agent", "Task", "Workflow": return "person.2"
        case "TodoWrite": return "checklist"
        case "Skill": return "wand.and.stars"
        default: return tool.hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver"
        }
    }

    static func summary(_ sessions: [AgentSession], turns: Int, at now: Date) -> String {
        let phases = sessions.map { $0.effectivePhase(at: now) }
        let working = phases.filter { $0 == .working }.count
        let waiting = phases.filter { $0 == .waiting }.count
        var parts: [String] = []
        if working > 0 { parts.append(String(localized: "\(working) çalışıyor")) }
        if waiting > 0 { parts.append(String(localized: "\(waiting) onay bekliyor")) }
        if parts.isEmpty { parts.append(String(localized: "Aktif oturum yok")) }
        if turns > 0 { parts.append(String(localized: "bugün \(turns) tur")) }
        return parts.joined(separator: " · ")
    }
}

/// The session that matters right now, large: the mascot acting it out, the project, what it is doing and for
/// how long, and a trail of the tools it used this turn (oldest faintest). A tap brings its app forward.
struct HeroAgentCard: View {
    let session: AgentSession
    let now: Date
    @ObservedObject var service: AgentStatusService
    var body: some View {
        let phase = session.effectivePhase(at: now)
        let activity = AgentText.activity(session, at: now)
        let tint = phase == .waiting ? Theme.amber : phase == .failed ? Color(red: 1, green: 0.47, blue: 0.47) : Theme.agent
        Button { service.activate(session) } label: {
            HStack(spacing: 14) {
                AgentMascot(session: session, size: 56, showHost: true).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(session.project).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(session.provider.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.faint)
                        Spacer(minLength: 4)
                        Text(session.updated, style: .relative).font(.system(size: 9, design: .rounded)).foregroundStyle(Theme.faint)
                    }
                    Text(activity.text).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .foregroundStyle(activity.urgent ? Theme.amber : .white.opacity(0.85))
                        .contentTransition(.numericText())
                    if let tools = session.recentTools, !tools.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                                Image(systemName: AgentText.symbol(for: tool)).font(.system(size: 9.5, weight: .semibold))
                                    .frame(width: 20, height: 20).background(Theme.fill, in: Circle())
                                    .opacity(0.35 + 0.65 * Double(index + 1) / Double(tools.count))
                                    .help(AgentSession.toolLabel(tool))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .padding(12)
            .background(LinearGradient(colors: [tint.opacity(0.16), Theme.fill], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.8))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Tıkla: \(session.hostName ?? session.provider.title) öne gelsin")
        .animation(Theme.quick, value: phase)
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
            if let request = service.approvals.first(where: { $0.deadline > now }) {
                ApprovalCard(request: request, waiting: service.approvals.count, now: now, service: service)
            } else {
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
                            // The session that needs eyes (working or waiting, else the latest) gets the big card.
                            let hero = active.first { [.working, .waiting].contains($0.effectivePhase(at: now)) } ?? active.first
                            if let hero { HeroAgentCard(session: hero, now: now, service: service) }
                            ForEach(active.filter { $0.id != hero?.id }) { AgentRow(session: $0, now: now, service: service) }
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
}

/// A permission prompt answered from the notch. The exact command or path is always shown in full (scrollable,
/// selectable): allowing something unseen would defeat the point of asking.
struct ApprovalCard: View {
    let request: ApprovalRequest
    let waiting: Int
    let now: Date
    @ObservedObject var service: AgentStatusService
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let icon = request.provider.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(request.project).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(Self.title(for: request.tool)).font(.system(size: 11)).foregroundStyle(Theme.amber).lineLimit(1)
                Spacer(minLength: 4)
                if waiting > 1 {
                    Text("+\(waiting - 1)").font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.fill, in: Capsule())
                        .help("\(waiting - 1) istek daha bekliyor")
                }
                Text("\(max(0, Int(request.deadline.timeIntervalSince(now).rounded()))) sn")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Theme.faint)
                    .help("Süre dolunca soru terminalde sorulur")
            }
            ScrollView {
                Text(request.summary.isEmpty ? request.tool : request.summary)
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 66)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            if !request.detail.isEmpty {
                Text(request.detail).font(.system(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button { activateHost() } label: {
                    Label(hostName.map { String(localized: "\($0)’a git") } ?? String(localized: "Terminale git"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.dim)
                }.buttonStyle(.plain).help("Soruyu orada yanıtla")
                Spacer()
                Button("Reddet") { service.decide(request, .deny) }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(PillStyle())
                Button("İzin ver") { service.decide(request, .allow) }
                    .font(.system(size: 11, weight: .semibold)).buttonStyle(PillStyle(accent: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var hostName: String? { request.host.flatMap(AppIcons.name(bundleID:)) }

    private func activateHost() {
        if let session = service.sessions.first(where: { $0.id == request.session }) { service.activate(session); return }
        if let host = request.host { NSRunningApplication.runningApplications(withBundleIdentifier: host).first?.activate() }
    }

    static func title(for tool: String) -> String {
        switch tool {
        case "Bash": return String(localized: "komut çalıştırmak istiyor")
        case "Edit", "MultiEdit", "NotebookEdit": return String(localized: "dosya düzenlemek istiyor")
        case "Write": return String(localized: "dosya yazmak istiyor")
        case "Read": return String(localized: "dosya okumak istiyor")
        case "WebFetch": return String(localized: "web sayfası açmak istiyor")
        case "WebSearch": return String(localized: "web’de aramak istiyor")
        default: return tool.hasPrefix("mcp__") ? String(localized: "\(tool.components(separatedBy: "__").dropFirst().first ?? "MCP") aracını kullanmak istiyor") : String(localized: "\(tool) kullanmak istiyor")
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
