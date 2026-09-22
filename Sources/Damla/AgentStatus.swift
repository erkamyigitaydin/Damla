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
    var id: String
    var provider: AgentProvider
    var project: String
    var phase: AgentPhase = .idle
    var updated: Date
    var pending: Set<String> = []
    var detail = ""
    func effectivePhase(at now: Date) -> AgentPhase {
        if (phase == .working || phase == .waiting), now.timeIntervalSince(updated) > 30 * 60 { return .stale }
        return phase
    }
    func visibleInNotch(at now: Date) -> Bool {
        let current = effectivePhase(at: now)
        return current == .working || current == .waiting || ((current == .done || current == .failed) && now.timeIntervalSince(updated) < 60)
    }
    static func identifier(provider: AgentProvider, session: String) -> String {
        provider.rawValue + "-" + SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    mutating func apply(_ event: [String: Any], at now: Date) -> Bool {
        let name = event["hook_event_name"] as? String ?? ""
        let key = event["tool_use_id"] as? String ?? event["tool_name"] as? String ?? "permission"
        switch name {
        case "SessionStart":
            // Compaction/resume can happen in the middle of a turn.
            if phase != .working && phase != .waiting { phase = .idle }
        case "UserPromptSubmit": phase = .working; pending = []; detail = ""
        case "PermissionRequest": pending.insert(key); phase = .waiting; detail = "Onay bekliyor"
        case "PreToolUse":
            if ["AskUserQuestion", "request_user_input", "request_user_input_async"].contains(event["tool_name"] as? String ?? "") {
                pending.insert(key); phase = .waiting; detail = "Yanıt bekliyor"
            } else { phase = pending.isEmpty ? .working : .waiting }
        case "PostToolUse", "PostToolUseFailure":
            pending.remove(key)
            // PermissionRequest may not include tool_use_id, but the completion does.
            if let tool = event["tool_name"] as? String { pending.remove(tool) }
            pending.remove("notification")
            phase = pending.isEmpty ? .working : .waiting
            if pending.isEmpty { detail = "" }
        case "Notification":
            guard ["permission_prompt", "elicitation_dialog"].contains(event["notification_type"] as? String ?? "") else { return false }
            pending.insert("notification"); phase = .waiting; detail = "Yanıt / onay bekliyor"
        case "Stop": phase = .done; pending = []; detail = ""
        case "StopFailure": phase = .failed; pending = []; detail = ""
        case "Interrupt": phase = .interrupted; pending = []; detail = ""
        case "SessionEnd": phase = .idle; pending = []; detail = ""
        default: return false
        }
        updated = now
        return true
    }
}

enum AgentEventStore {
    static var directory: URL { DiskStore.directory.appendingPathComponent("agents", isDirectory: true) }

    /// Hook entry point runs before NSApplication. It is silent and never makes an approval decision.
    static func receive(provider: AgentProvider, input: Data, directory: URL = directory, now: Date = Date()) throws {
        guard input.count <= 2 * 1024 * 1024,
              let event = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              let session = event["session_id"] as? String, !session.isEmpty, session.count <= 512 else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = AgentSession.identifier(provider: provider, session: session)
        let file = directory.appendingPathComponent(id + ".json")
        // Serialize read/modify/write across simultaneous hooks without blocking an agent for long.
        let fd = Darwin.open(directory.appendingPathComponent(id + ".lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return }
        defer { flock(fd, LOCK_UN); Darwin.close(fd) }
        var acquired = false
        for _ in 0..<100 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
            usleep(2_000)
        }
        guard acquired else { return }
        let cwd = event["cwd"] as? String ?? ""
        let name = cwd.isEmpty ? "Oturum" : URL(fileURLWithPath: cwd).lastPathComponent
        let project = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80).map(String.init).joined())
        var value = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(AgentSession.self, from: $0) }
            ?? AgentSession(id: id, provider: provider, project: project, updated: now)
        value.project = project
        guard value.apply(event, at: now) else { return }
        let data = try JSONEncoder().encode(value)
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func read(directory: URL = directory, now: Date = Date()) -> [AgentSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        // Records and their lock files from sessions older than a week are garbage.
        for url in files {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               now.timeIntervalSince(modified) > 7 * 24 * 3600 { try? FileManager.default.removeItem(at: url) }
        }
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> (URL, Date)? in
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
}

final class AgentStatusService: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
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
                self.onRefresh?()
            }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    func open(_ provider: AgentProvider) {
        guard let url = provider.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    deinit { timer?.cancel() }
}
