import AppKit
import Combine
import CryptoKit
import Darwin

enum AgentProvider: String, Codable, CaseIterable {
    case claude, codex
    var title: String { self == .claude ? "Claude Code" : "Codex" }
    /// Apps that host the agent, in preference order (Codex also lives inside the ChatGPT app).
    var bundleIDs: [String] { self == .claude ? ["com.anthropic.claudefordesktop"] : ["com.openai.codex", "com.openai.chat"] }
    var appURL: URL? { bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first }
    /// The installed app's own icon (Claude's spark, the Codex/ChatGPT mark), read at runtime so no brand
    /// asset ships with Damla. Nil when the app is not installed.
    var icon: NSImage? { appURL.map { AppIcons.icon(for: $0) } }
}

/// Runtime app icons, cached per path.
enum AppIcons {
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    static func icon(for url: URL) -> NSImage {
        if let cached = cache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 64, height: 64)
        cache[url.path] = image
        return image
    }
    static func icon(bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map(icon(for:))
    }
    static func name(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum AgentPhase: String, Codable {
    case working, waiting, done, interrupted, failed, idle, stale
    var title: String {
        switch self {
        case .working: return "Çalışıyor"
        case .waiting: return "Seni bekliyor"
        case .done: return "Yanıt tamamlandı"
        case .interrupted: return "Durduruldu"
        case .failed: return "Hata oluştu"
        case .idle: return "Hazır"
        case .stale: return "Durum güncel değil"
        }
    }
    /// Fits beside the notch in the HUD (about 90 pt).
    var shortTitle: String {
        switch self {
        case .working: return "Çalışıyor"
        case .waiting: return "Onay bekliyor"
        case .done: return "Tamamlandı"
        case .interrupted: return "Durduruldu"
        case .failed: return "Hata"
        case .idle: return "Hazır"
        case .stale: return "Güncel değil"
        }
    }
    var icon: String {
        switch self {
        case .working: return "ellipsis"
        case .waiting: return "hand.raised.fill"
        case .done: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        case .interrupted: return "pause.fill"
        case .idle, .stale: return "minus"
        }
    }
    var priority: Int {
        switch self { case .waiting: return 0; case .working: return 1; case .failed: return 2; case .done: return 3; default: return 4 }
    }
}

/// Only state metadata is retained: no prompts, tool arguments, outputs or transcripts.
struct AgentSession: Codable, Identifiable, Equatable {
    static let questionTools: Set<String> = ["AskUserQuestion", "request_user_input", "request_user_input_async"]

    var id: String
    var provider: AgentProvider
    var project: String
    var phase: AgentPhase = .idle
    var updated: Date
    var pending: Set<String> = []
    var detail = ""
    var tool: String? = nil          // tool running right now
    var waitingTool: String? = nil   // tool that asked for approval, or the question tool
    var turnStarted: Date? = nil
    var toolCalls: Int? = nil
    var waitingSince: Date? = nil
    var host: String? = nil          // bundle id of the app hosting the session: Terminal, Claude, VS Code, ChatGPT…

    func effectivePhase(at now: Date) -> AgentPhase {
        if (phase == .working || phase == .waiting), now.timeIntervalSince(updated) > 30 * 60 { return .stale }
        return phase
    }
    func visibleInNotch(at now: Date) -> Bool {
        let current = effectivePhase(at: now)
        return current == .working || current == .waiting || ((current == .done || current == .failed) && now.timeIntervalSince(updated) < 60)
    }
    /// Sessions that belong in the main list; the rest fold into "Geçmiş".
    func isActive(at now: Date) -> Bool {
        let current = effectivePhase(at: now)
        return current == .working || current == .waiting
            || ((current == .done || current == .failed || current == .interrupted) && now.timeIntervalSince(updated) < 15 * 60)
    }
    var hostIcon: NSImage? { host.flatMap(AppIcons.icon(bundleID:)) }
    var hostName: String? { host.flatMap(AppIcons.name(bundleID:)) }

    static func identifier(provider: AgentProvider, session: String) -> String {
        provider.rawValue + "-" + SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Turkish verb for what a tool does; unknown tools keep their name.
    static func toolLabel(_ tool: String) -> String {
        switch tool {
        case "Bash": return "Komut çalıştırıyor"
        case "Read": return "Dosya okuyor"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "Dosya düzenliyor"
        case "Grep", "Glob": return "Kod arıyor"
        case "WebFetch", "WebSearch": return "Web'de arıyor"
        case "Agent", "Task", "Workflow": return "Alt görev çalıştırıyor"
        case "TodoWrite": return "Plan yazıyor"
        case "Skill": return "Beceri kullanıyor"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                return "\(parts.last.map(String.init) ?? tool) kullanıyor"
            }
            return "\(tool) kullanıyor"
        }
    }

    private mutating func clearWaiting() { waitingTool = nil; waitingSince = nil; detail = "" }
    private mutating func finishTurn(_ result: AgentPhase) {
        phase = result; pending = []; tool = nil; clearWaiting()
    }

    mutating func apply(_ event: [String: Any], at now: Date) -> Bool {
        let name = event["hook_event_name"] as? String ?? ""
        let toolName = event["tool_name"] as? String
        let key = event["tool_use_id"] as? String ?? toolName ?? "permission"
        switch name {
        case "SessionStart":
            // Compaction/resume can happen in the middle of a turn.
            if phase != .working && phase != .waiting { phase = .idle }
        case "UserPromptSubmit":
            phase = .working; pending = []; tool = nil; clearWaiting()
            turnStarted = now; toolCalls = 0
        case "PermissionRequest":
            pending.insert(key); phase = .waiting; detail = "Onay bekliyor"
            waitingTool = toolName; if waitingSince == nil { waitingSince = now }
        case "PermissionDenied":
            pending.remove(key); if let toolName { pending.remove(toolName) }
            phase = pending.isEmpty ? .working : .waiting
            if pending.isEmpty { clearWaiting() }
        case "PreToolUse":
            if let toolName, Self.questionTools.contains(toolName) {
                pending.insert(key); phase = .waiting; detail = "Yanıt bekliyor"
                waitingTool = toolName; if waitingSince == nil { waitingSince = now }
            } else {
                tool = toolName
                phase = pending.isEmpty ? .working : .waiting
            }
        case "PostToolUse", "PostToolUseFailure":
            pending.remove(key)
            // PermissionRequest may not include tool_use_id, but the completion does.
            if let toolName { pending.remove(toolName) }
            pending.remove("notification")
            tool = nil
            toolCalls = (toolCalls ?? 0) + 1
            phase = pending.isEmpty ? .working : .waiting
            if pending.isEmpty { clearWaiting() }
        case "Notification":
            guard ["permission_prompt", "elicitation_dialog"].contains(event["notification_type"] as? String ?? "") else { return false }
            pending.insert("notification"); phase = .waiting; detail = "Yanıt / onay bekliyor"
            if waitingSince == nil { waitingSince = now }
        case "Stop": finishTurn(.done)
        case "StopFailure": finishTurn(.failed)
        case "Interrupt": finishTurn(.interrupted)
        case "SessionEnd": finishTurn(.idle); turnStarted = nil; toolCalls = nil
        default: return false
        }
        updated = now
        return true
    }
}

/// Finds the app that hosts the agent process (Terminal, iTerm, VS Code, Claude, ChatGPT…) by walking the
/// hook process's ancestors until one is a regular, Dock-visible application.
enum ProcessAncestry {
    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
    static func hostBundleID(from start: pid_t = getppid()) -> String? {
        var pid = start
        for _ in 0..<24 {
            guard pid > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, let id = app.bundleIdentifier { return id }
            guard let next = parent(of: pid), next != pid else { return nil }
            pid = next
        }
        return nil
    }
}

enum AgentEventStore {
    static var directory: URL { DiskStore.directory.appendingPathComponent("agents", isDirectory: true) }
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    /// Runs `body` while holding an exclusive lock on `name`, waiting at most ~200 ms so a hook never stalls an agent.
    private static func withLock(_ name: String, in directory: URL, _ body: () throws -> Void) rethrows {
        let fd = Darwin.open(directory.appendingPathComponent(name).path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return }
        defer { flock(fd, LOCK_UN); Darwin.close(fd) }
        var acquired = false
        for _ in 0..<100 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
            usleep(2_000)
        }
        guard acquired else { return }
        try body()
    }

    /// Hook entry point runs before NSApplication. It is silent and never makes an approval decision.
    static func receive(provider: AgentProvider, input: Data, directory: URL = directory, now: Date = Date(), host: String? = nil) throws {
        guard input.count <= 2 * 1024 * 1024,
              let event = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              let session = event["session_id"] as? String, !session.isEmpty, session.count <= 512 else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = AgentSession.identifier(provider: provider, session: session)
        let file = directory.appendingPathComponent(id + ".json")
        var completedTurn = false
        try withLock(id + ".lock", in: directory) {
            let cwd = event["cwd"] as? String ?? ""
            let name = cwd.isEmpty ? "Oturum" : URL(fileURLWithPath: cwd).lastPathComponent
            let project = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80).map(String.init).joined())
            var value = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(AgentSession.self, from: $0) }
                ?? AgentSession(id: id, provider: provider, project: project, updated: now)
            value.project = project
            if let host { value.host = host }
            guard value.apply(event, at: now) else { return }
            completedTurn = (event["hook_event_name"] as? String) == "Stop"
            let data = try JSONEncoder().encode(value)
            try data.write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        if completedTurn { try recordTurn(directory: directory, now: now) }
    }

    /// Daily counter of completed turns, kept beside the session records.
    static func recordTurn(directory: URL = directory, now: Date = Date()) throws {
        let file = directory.appendingPathComponent("stats.json")
        try withLock("stats.lock", in: directory) {
            let day = dayFormatter.string(from: now)
            var stats = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            let turns = stats["day"] == day ? (Int(stats["turns"] ?? "0") ?? 0) : 0
            stats = ["day": day, "turns": String(turns + 1)]
            try JSONEncoder().encode(stats).write(to: file, options: .atomic)
        }
    }
    static func todayTurns(directory: URL = directory, now: Date = Date()) -> Int {
        let file = directory.appendingPathComponent("stats.json")
        guard let stats = (try? Data(contentsOf: file)).flatMap({ try? JSONDecoder().decode([String: String].self, from: $0) }),
              stats["day"] == dayFormatter.string(from: now) else { return 0 }
        return Int(stats["turns"] ?? "0") ?? 0
    }

    static func read(directory: URL = directory, now: Date = Date()) -> [AgentSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        // Records and their lock files from sessions older than a week are garbage.
        for url in files where url.lastPathComponent != "stats.json" && url.lastPathComponent != "stats.lock" {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               now.timeIntervalSince(modified) > 7 * 24 * 3600 { try? FileManager.default.removeItem(at: url) }
        }
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "stats.json" }.compactMap { url -> (URL, Date)? in
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = attrs.contentModificationDate, now.timeIntervalSince(modified) < 24 * 3600,
                  (attrs.fileSize ?? Int.max) < 32_768 else { return nil }
            return (url, modified)
        }.sorted { $0.1 > $1.1 }.prefix(64).compactMap {
            guard let data = try? Data(contentsOf: $0.0), let record = try? JSONDecoder().decode(AgentSession.self, from: data) else { return nil }
            return record
        }.sorted {
            let p0 = $0.effectivePhase(at: now).priority, p1 = $1.effectivePhase(at: now).priority
            return p0 == p1 ? $0.updated > $1.updated : p0 < p1
        }
    }

    static func remove(id: String, directory: URL = directory) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".json"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".lock"))
    }
}

final class AgentStatusService: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var todayTurns = 0
    @Published var soundEnabled = UserDefaults.standard.bool(forKey: "agentSound") {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "agentSound") }
    }
    var onChange: ((AgentSession) -> Void)?
    var onRefresh: (() -> Void)?
    private let queue = DispatchQueue(label: "app.local.damla.agents", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var loaded = false
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            let records = AgentEventStore.read()
            let turns = AgentEventStore.todayTurns()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.loaded {
                    for record in records where record.phase == .waiting || record.phase == .done || record.phase == .failed {
                        if let old = self.sessions.first(where: { $0.id == record.id }), old.phase != record.phase,
                           Date().timeIntervalSince(record.updated) < 5 { self.onChange?(record) }
                    }
                }
                self.loaded = true
                if records != self.sessions { self.sessions = records }
                if turns != self.todayTurns { self.todayTurns = turns }
                self.onRefresh?()
            }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }

    /// Brings the app that hosts the session to the front; falls back to the provider's app.
    func activate(_ session: AgentSession) {
        if let host = session.host, let app = NSRunningApplication.runningApplications(withBundleIdentifier: host).first {
            app.activate(); return
        }
        open(session.provider)
    }
    func open(_ provider: AgentProvider) {
        guard let url = provider.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    func remove(_ session: AgentSession) {
        AgentEventStore.remove(id: session.id)
        sessions.removeAll { $0.id == session.id }
        onRefresh?()
    }
    deinit { timer?.cancel() }
}
