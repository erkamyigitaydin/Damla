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
            else if let tool = s.waitingTool, AgentSession.permissionTools.contains(tool) { parts.append(String(localized: "Yetki için onay bekliyor")) }
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

    static func summary(_ sessions: [AgentSession], at now: Date) -> String {
        let phases = sessions.map { $0.effectivePhase(at: now) }
        let working = phases.filter { $0 == .working }.count
        let waiting = phases.filter { $0 == .waiting }.count
        var parts: [String] = []
        if working > 0 { parts.append(String(localized: "\(working) çalışıyor")) }
        if waiting > 0 { parts.append(String(localized: "\(waiting) onay bekliyor")) }
        if parts.isEmpty { parts.append(String(localized: "Aktif oturum yok")) }
        return parts.joined(separator: " · ")
    }

    /// "12 dk önce", "3 sa önce", "2 gün önce".
    static func ago(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 60 { return String(localized: "\(minutes) dk önce") }
        if minutes < 48 * 60 { return String(localized: "\(minutes / 60) sa önce") }
        return String(localized: "\(minutes / 1440) gün önce")
    }

    /// The suffix a Turkish clock time takes, by how its last number is read aloud: 14:30 "otuz" → da,
    /// 14:00 "on dört" → te, 13:40 "kırk" → ta.
    static func locative(_ time: String) -> String {
        let numbers = time.split { !$0.isNumber }.compactMap { Int($0) }
        guard var spoken = numbers.last else { return "da" }
        if spoken == 0, numbers.count > 1 { spoken = numbers[numbers.count - 2] }
        let units = ["da", "de", "de", "te", "te", "te", "da", "de", "de", "da"]  // sıfır bir iki üç dört beş altı yedi sekiz dokuz
        let tens = ["da", "da", "de", "da", "ta", "de"]                          // sıfır on yirmi otuz kırk elli
        return spoken % 10 != 0 ? units[spoken % 10] : tens[min(spoken / 10 % 10, 5)]
    }

    /// "14:30’da", or "Cum 14:00’te" when it is not today. Other languages drop the suffix in their strings.
    static func at(_ date: Date, now: Date) -> String {
        let time = Calendar.current.isDate(date, inSameDayAs: now) ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        switch locative(time) {
        case "de": return String(localized: "\(time)’de")
        case "ta": return String(localized: "\(time)’ta")
        case "te": return String(localized: "\(time)’te")
        default: return String(localized: "\(time)’da")
        }
    }

    /// The faint line under a usage bar: when it resets, or where the current pace leads.
    static func outlook(_ window: AgentUsage.Window, length: TimeInterval, at now: Date) -> String {
        switch window.outlook(length: length, at: now) {
        case .resets: return String(localized: "\(at(window.resetsAt, now: now)) sıfırlanır")
        case .fills(let date):
            // An estimate, so no false minutes: ten-minute steps for five hours, whole hours for the week.
            let step: TimeInterval = length > AgentUsage.fiveHourLength ? 3600 : 600
            let rounded = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded() * step)
            return String(localized: "bu hızla \(at(rounded, now: now)) dolar")
        case .leaves(let left): return String(localized: "sıfırlanınca ~%\(left) kalır")
        }
    }
}

/// How full a session's context window is; amber from 80 %, when Claude Code will soon compact it.
struct ContextBadge: View {
    let percent: Int
    let model: String?
    var body: some View {
        let high = percent >= 80
        HStack(spacing: 3) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward").font(.system(size: 8.5, weight: .semibold))
            Text("%\(percent)").font(.system(size: 9.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(high ? Theme.amber : Theme.dim)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(high ? Theme.amber.opacity(0.14) : Theme.fill, in: Capsule())
        .help(model.map { String(localized: "\($0) · bağlamın %\(percent) dolu") } ?? String(localized: "Bağlamın %\(percent) dolu"))
    }
}

/// One agent account's plan limits: per window a thin bar with a tick where even use would stand by now, and
/// under it when the window resets or, once it is under way, where the current pace leads.
struct UsageCard: View {
    let title: String
    let usage: AgentUsage
    let now: Date
    var body: some View {
        let age = now.timeIntervalSince(usage.updated)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(verbatim: title).font(.system(size: 10.5, weight: .semibold))
                if let plan = usage.planTitle {
                    Text(verbatim: plan).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Theme.dim)
                        .padding(.horizontal, 4).padding(.vertical, 1).background(Theme.fill, in: Capsule())
                }
                Spacer(minLength: 4)
                // Both only report while a session runs; old numbers say how old they are.
                if age > 15 * 60 { Text(AgentText.ago(age)).font(.system(size: 9)).foregroundStyle(Theme.faint) }
            }
            .lineLimit(1)
            if let window = usage.fiveHour { UsageWindowRow(title: String(localized: "5 saat"), window: window, length: AgentUsage.fiveHourLength, now: now) }
            if let window = usage.sevenDay { UsageWindowRow(title: String(localized: "Hafta"), window: window, length: AgentUsage.weekLength, now: now) }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct UsageWindowRow: View {
    let title: String
    let window: AgentUsage.Window
    let length: TimeInterval
    let now: Date
    var body: some View {
        let pace = window.elapsed(length: length, at: now)
        let tint = window.percent >= 90 ? Theme.red : window.percent >= 75 ? Theme.amber : Color.white.opacity(0.85)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(1)
                    .frame(width: 36, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fillStrong).frame(height: 3)
                        Capsule().fill(tint).frame(width: window.percent > 0 ? max(3, proxy.size.width * window.percent / 100) : 0, height: 3)
                        // Taller than the bar, so it shows over the fill as well as past it.
                        Capsule().fill(Theme.dim).frame(width: 1.5, height: 8).offset(x: (proxy.size.width - 1.5) * pace)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 8)
                Text("%\(Int(window.percent.rounded()))").font(.system(size: 9.5, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(window.percent >= 75 ? tint : .white.opacity(0.85))
            }
            Text(AgentText.outlook(window, length: length, at: now)).font(.system(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .help(String(localized: "\(AgentText.at(window.resetsAt, now: now)) sıfırlanır") + " · "
              + String(localized: "çentik: kullanım eşit yayılsaydı şu an %\(Int((pace * 100).rounded())) olurdu"))
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
        let tint = phase == .waiting ? Theme.amber : phase == .failed ? Theme.red : Theme.agent
        Button { service.activate(session) } label: {
            HStack(spacing: 14) {
                AgentMascot(session: session, size: 56, showHost: true).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(session.project).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(session.provider.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.faint)
                        Spacer(minLength: 4)
                        if let context = session.context { ContextBadge(percent: context, model: session.model) }
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
    @ObservedObject var servers: DevServerMonitor
    @State private var showHistory = false
    @State private var showServers = true
    var body: some View {
        content
            .onAppear { servers.start(); service.watchCodexUsage(true) }
            .onDisappear { servers.stop(); service.watchCodexUsage(false) }
    }

    /// Dev servers and databases listening on this Mac, folded like the history.
    @ViewBuilder private var serverSection: some View {
        if !servers.servers.isEmpty {
            Button { withAnimation(Theme.quick) { showServers.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showServers ? 90 : 0))
                    Text("Yerel sunucular · \(servers.servers.count)").font(.system(size: 10.5, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.dim).padding(.horizontal, 8).frame(height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if showServers {
                ForEach(servers.servers) { DevServerRow(server: $0, monitor: servers) }
            }
        }
    }

    /// Claude's and Codex's plan limits side by side; a provider with nothing (current) to say has no card.
    @ViewBuilder private func usageCards(at now: Date) -> some View {
        let claude = service.usage?.current(at: now), codex = service.codexUsage?.current(at: now)
        if claude != nil || codex != nil {
            HStack(spacing: 6) {
                if let claude { UsageCard(title: "Claude", usage: claude, now: now) }
                if let codex { UsageCard(title: "Codex", usage: codex, now: now) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var content: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let active = service.sessions.filter { $0.isActive(at: now) }
            let history = service.sessions.filter { !$0.isActive(at: now) }
            if let request = service.approvals.first(where: { $0.deadline > now }) {
                if let questions = request.questions {
                    QuestionCard(request: request, questions: questions, waiting: service.approvals.count, now: now, service: service)
                        .id(request.id)
                } else {
                    ApprovalCard(request: request, waiting: service.approvals.count, now: now, service: service)
                }
            } else {
            VStack(alignment: .leading, spacing: 6) {
                PageHeader(title: Text(AgentText.summary(service.sessions, at: now)),
                           detail: service.todayTurns > 0 ? Text("Bugün \(service.todayTurns) tur") : nil) {
                    IconButton(icon: service.soundEnabled ? "bell.fill" : "bell.slash", label: service.soundEnabled ? "Onay beklerken ses: açık" : "Onay beklerken ses: kapalı",
                               tint: service.soundEnabled ? Theme.accent : .white, size: 22) { service.soundEnabled.toggle() }
                }
                // The cards scroll with the list: pinned, they would leave the sessions too little room to read.
                ScrollView {
                    LazyVStack(spacing: 5) {
                        usageCards(at: now)
                        if service.sessions.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Henüz durum gelmedi", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 12, weight: .medium))
                                if servers.servers.isEmpty {
                                    Text("Bağlı bir Claude Code veya Codex oturumunda yeni bir mesajla başlar.")
                                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                                    Text("Codex ilk bağlantıda /hooks üzerinden güven onayı ister.")
                                        .font(.system(size: 10)).foregroundStyle(Theme.faint)
                                }
                            }
                            .padding(.top, 2).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
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
                        serverSection
                    }
                }.scrollIndicators(.hidden)
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
                if let rule = request.always?.first {
                    // Claude Code's own "don't ask again" suggestion, remembered where it proposed.
                    Button("Hep izin ver") { service.decide(request, .allowAlways(0)) }
                        .font(.system(size: 11, weight: .medium)).buttonStyle(PillStyle())
                        .help(String(localized: "İzin ver ve bir daha sorma: \(rule)"))
                } else {
                    Text(verbatim: "⌃⌥⌫ · ⌃⌥↩").font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(Theme.faint)
                        .help("Klavyeden: ⌃⌥⌫ reddet, ⌃⌥↩ izin ver")
                }
                Button("Reddet") { service.decide(request, .deny) }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(PillStyle())
                    .help("Reddet (⌃⌥⌫)")
                Button("İzin ver") { service.decide(request, .allow) }
                    .font(.system(size: 11, weight: .semibold)).buttonStyle(PillStyle(accent: true))
                    .help("İzin ver (⌃⌥↩)")
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
        case "AskUserQuestion": return String(localized: "bir şey soruyor")
        case "Bash": return String(localized: "komut çalıştırmak istiyor")
        case "Edit", "MultiEdit", "NotebookEdit", "apply_patch": return String(localized: "dosya düzenlemek istiyor")
        case "Write": return String(localized: "dosya yazmak istiyor")
        case "Read": return String(localized: "dosya okumak istiyor")
        case "WebFetch": return String(localized: "web sayfası açmak istiyor")
        case "WebSearch": return String(localized: "web’de aramak istiyor")
        default: return tool.hasPrefix("mcp__") ? String(localized: "\(tool.components(separatedBy: "__").dropFirst().first ?? "MCP") aracını kullanmak istiyor") : String(localized: "\(tool) kullanmak istiyor")
        }
    }
}

/// Claude Code's multiple-choice question, answered from the notch. One single-choice question is answered by
/// tapping an option; otherwise options are toggled and sent together. Anything else (typing a custom answer)
/// happens in the terminal, which gets the question back as soon as the user switches to it.
struct QuestionCard: View {
    let request: ApprovalRequest
    let questions: [QuestionPrompt]
    let waiting: Int
    let now: Date
    @ObservedObject var service: AgentStatusService
    @State private var chosen: [String: [String]] = [:]   // question → labels in tap order

    private var instant: Bool { questions.count == 1 && !questions[0].multiSelect }
    private var complete: Bool { questions.allSatisfy { !(chosen[$0.question] ?? []).isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let icon = request.provider.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                Text(request.project).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(ApprovalCard.title(for: request.tool)).font(.system(size: 11)).foregroundStyle(Theme.amber).lineLimit(1)
                Spacer(minLength: 4)
                if waiting > 1 {
                    Text("+\(waiting - 1)").font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.dim)
                        .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.fill, in: Capsule())
                }
                Text("\(max(0, Int(request.deadline.timeIntervalSince(now).rounded()))) sn")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Theme.faint)
                    .help("Süre dolunca soru terminalde sorulur")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(questions, id: \.question) { question in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(question.question).font(.system(size: 11.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            FlowOptions(options: question.options, selected: chosen[question.question] ?? []) { label in
                                pick(label, in: question)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 92)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button { activateHost() } label: {
                    Label(String(localized: "Terminalde yanıtla"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.dim)
                }.buttonStyle(.plain).help("Kendi cevabını yazmak için soruyu terminale bırak")
                Spacer()
                if !instant {
                    Button("Gönder") { send() }
                        .font(.system(size: 11, weight: .semibold)).buttonStyle(PillStyle(accent: true))
                        .disabled(!complete).opacity(complete ? 1 : 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func pick(_ label: String, in question: QuestionPrompt) {
        var labels = chosen[question.question] ?? []
        if question.multiSelect {
            if let index = labels.firstIndex(of: label) { labels.remove(at: index) } else { labels.append(label) }
        } else {
            labels = [label]
        }
        chosen[question.question] = labels
        if instant { send() }
    }

    private func send() {
        guard complete else { return }
        // Multi-select answers join the labels with commas, in the order the options are listed.
        var answers: [String: String] = [:]
        for question in questions {
            let picked = chosen[question.question] ?? []
            answers[question.question] = question.options.map(\.label).filter(picked.contains).joined(separator: ", ")
        }
        service.decide(request, .answer(answers))
    }

    private func activateHost() {
        // Withdrawing the request lets the hook step aside at once, so the question shows up in the terminal.
        service.withdraw(request)
        if let session = service.sessions.first(where: { $0.id == request.session }) { service.activate(session); return }
        if let host = request.host { NSRunningApplication.runningApplications(withBundleIdentifier: host).first?.activate() }
    }
}

/// Option pills that wrap onto as many lines as they need.
private struct FlowOptions: View {
    let options: [QuestionPrompt.Option]
    let selected: [String]
    let pick: (String) -> Void
    var body: some View {
        OptionFlowLayout(spacing: 5) {
            ForEach(options, id: \.label) { option in
                let on = selected.contains(option.label)
                Button { pick(option.label) } label: {
                    Text(option.label).font(.system(size: 10.5, weight: on ? .semibold : .medium)).lineLimit(1)
                }
                .buttonStyle(PillStyle(accent: on))
                .help(option.description ?? option.label)
            }
        }
    }
}

private struct OptionFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private func arrange(width: CGFloat, subviews: LayoutSubviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.items + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// One listening server: a tap opens it in the browser (databases have no page to open); on hover a stop button
/// asks once more before sending SIGTERM.
struct DevServerRow: View {
    let server: DevServer
    @ObservedObject var monitor: DevServerMonitor
    @State private var hovering = false
    @State private var confirming = false
    var body: some View {
        Button { open() } label: {
            HStack(spacing: 9) {
                Image(systemName: server.isDatabase ? "cylinder.split.1x2" : "globe").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(server.isDatabase ? Theme.dim : Theme.agent).frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(verbatim: ":\(server.port)").font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        Text(server.project).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    Text(server.name).font(.system(size: 9.5)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Spacer(minLength: 4)
                if hovering || confirming {
                    Button { if confirming { monitor.terminate(server) } else { confirming = true } } label: {
                        Text(confirming ? "Durdur?" : "Durdur").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(confirming ? Theme.red : Theme.dim)
                            .padding(.horizontal, 8).frame(height: 20).background(Theme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Sunucuya durmasını söyler (SIGTERM, terminalde Ctrl-C gibi)")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(hovering ? Theme.fillStrong : Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(server.isDatabase ? String(localized: "\(server.name) · port \(server.port)") : String(localized: "Tarayıcıda aç: localhost:\(server.port)"))
        .onHover { hovering = $0; if !$0 { confirming = false } }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
    private func open() {
        guard !server.isDatabase, let url = URL(string: "http://localhost:\(server.port)") else { return }
        NSWorkspace.shared.open(url)
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
                } else if let context = session.context, session.isActive(at: now) {
                    ContextBadge(percent: context, model: session.model)
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
