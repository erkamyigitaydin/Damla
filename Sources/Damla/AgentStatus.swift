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
        case .working: return String(localized: "Çalışıyor")
        case .waiting: return String(localized: "Seni bekliyor")
        case .done: return String(localized: "Yanıt tamamlandı")
        case .interrupted: return String(localized: "Durduruldu")
        case .failed: return String(localized: "Hata oluştu")
        case .idle: return String(localized: "Hazır")
        case .stale: return String(localized: "Durum güncel değil")
        }
    }
    /// Fits beside the notch in the HUD (about 90 pt).
    var shortTitle: String {
        switch self {
        case .working: return String(localized: "Çalışıyor")
        case .waiting: return String(localized: "Onay bekliyor")
        case .done: return String(localized: "Tamamlandı")
        case .interrupted: return String(localized: "Durduruldu")
        case .failed: return String(localized: "Hata")
        case .idle: return String(localized: "Hazır")
        case .stale: return String(localized: "Güncel değil")
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
    /// Codex's app asks for a turn's sandbox permissions through this tool, answered in its own window; no
    /// PermissionRequest hook runs for it, so its start is the only sign the session is waiting for approval.
    static let permissionTools: Set<String> = ["request_permissions"]

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
    var recentTools: [String]? = nil // names of the last few tools this turn (no arguments), newest last
    var context: Int? = nil          // % of the context window in use, from Claude Code's status line
    var model: String? = nil         // the model's display name, from the status line

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
        case "Bash": return String(localized: "Komut çalıştırıyor")
        case "Read": return String(localized: "Dosya okuyor")
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return String(localized: "Dosya düzenliyor")
        case "Grep", "Glob": return String(localized: "Kod arıyor")
        case "WebFetch", "WebSearch": return String(localized: "Web'de arıyor")
        case "Agent", "Task", "Workflow": return String(localized: "Alt görev çalıştırıyor")
        case "TodoWrite": return String(localized: "Plan yazıyor")
        case "Skill": return String(localized: "Beceri kullanıyor")
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                return String(localized: "\(parts.last.map(String.init) ?? tool) kullanıyor")
            }
            return String(localized: "\(tool) kullanıyor")
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
            phase = .working; pending = []; tool = nil; clearWaiting(); recentTools = nil
            turnStarted = now; toolCalls = 0
        case "PermissionRequest":
            pending.insert(key); phase = .waiting; detail = String(localized: "Onay bekliyor")
            waitingTool = toolName; if waitingSince == nil { waitingSince = now }
        case "PermissionDenied":
            pending.remove(key); if let toolName { pending.remove(toolName) }
            phase = pending.isEmpty ? .working : .waiting
            if pending.isEmpty { clearWaiting() }
        case "PreToolUse":
            if let toolName, Self.questionTools.contains(toolName) || Self.permissionTools.contains(toolName) {
                pending.insert(key); phase = .waiting
                detail = Self.permissionTools.contains(toolName) ? String(localized: "Onay bekliyor") : String(localized: "Yanıt bekliyor")
                waitingTool = toolName; if waitingSince == nil { waitingSince = now }
            } else {
                tool = toolName
                if let toolName { recentTools = Array(((recentTools ?? []) + [toolName]).suffix(6)) }
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
            pending.insert("notification"); phase = .waiting; detail = String(localized: "Yanıt / onay bekliyor")
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

    /// Claude Code's status line input: the session's context use and model go into its record (only if the
    /// hooks already created it), the account's rate limits into usage.json. Returns the line to print.
    @discardableResult
    static func receiveStatus(provider: AgentProvider, input: Data, directory: URL = directory, now: Date = Date()) -> String {
        guard input.count <= 2 * 1024 * 1024,
              let event = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { return "" }
        let model = ((event["model"] as? [String: Any])?["display_name"] as? String).map { AgentApprovals.clean($0, limit: 40) }
        let context = ((event["context_window"] as? [String: Any])?["used_percentage"] as? NSNumber).map { Int($0.doubleValue.rounded()) }
        let usage = AgentUsage(event["rate_limits"] as? [String: Any], now: now)
        if let session = event["session_id"] as? String, !session.isEmpty, session.count <= 512 {
            let id = AgentSession.identifier(provider: provider, session: session)
            let file = directory.appendingPathComponent(id + ".json")
            try? withLock(id + ".lock", in: directory) {
                guard var value = (try? Data(contentsOf: file)).flatMap({ try? JSONDecoder().decode(AgentSession.self, from: $0) }),
                      value.context != context || value.model != model else { return }
                value.context = context; value.model = model
                try JSONEncoder().encode(value).write(to: file, options: .atomic)
            }
        }
        if let usage {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? withLock("usage.lock", in: directory) {
                try JSONEncoder().encode(usage).write(to: directory.appendingPathComponent(AgentUsage.fileName), options: .atomic)
            }
        }
        var parts = [model, context.map { String(localized: "bağlam %\($0)") }].compactMap { $0 }
        if let window = usage?.fiveHour { parts.append(String(localized: "5 sa %\(Int(window.percent.rounded()))")) }
        return parts.joined(separator: " · ")
    }

    static func readUsage(directory: URL = directory, now: Date = Date()) -> AgentUsage? {
        let file = directory.appendingPathComponent(AgentUsage.fileName)
        guard let data = try? Data(contentsOf: file), data.count < 4096,
              let usage = try? JSONDecoder().decode(AgentUsage.self, from: data) else { return nil }
        return usage.current(at: now)
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
            let name = cwd.isEmpty ? String(localized: "Oturum") : URL(fileURLWithPath: cwd).lastPathComponent
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
        for url in files where url.lastPathComponent != "stats.json" && url.lastPathComponent != "stats.lock" && url.lastPathComponent != AgentUsage.fileName {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               now.timeIntervalSince(modified) > 7 * 24 * 3600 { try? FileManager.default.removeItem(at: url) }
        }
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "stats.json" && $0.lastPathComponent != AgentUsage.fileName }.compactMap { url -> (URL, Date)? in
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

/// An agent account's rate limits: Claude's as the status line last reported them (Pro and Max only), Codex's
/// from its newest session rollout.
struct AgentUsage: Codable, Equatable {
    static let fileName = "usage.json"
    static let fiveHourLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 24 * 3600
    struct Window: Codable, Equatable {
        var percent: Double
        var resetsAt: Date
    }
    var fiveHour: Window?
    var sevenDay: Window?
    var updated: Date
    var plan: String? = nil   // Codex's plan_type; Claude's status line does not say

    init?(_ limits: [String: Any]?, now: Date) {
        func window(_ key: String) -> Window? {
            guard let raw = limits?[key] as? [String: Any], let percent = (raw["used_percentage"] as? NSNumber)?.doubleValue,
                  let resets = (raw["resets_at"] as? NSNumber)?.doubleValue else { return nil }
            return Window(percent: min(max(percent, 0), 100), resetsAt: Date(timeIntervalSince1970: resets))
        }
        fiveHour = window("five_hour"); sevenDay = window("seven_day"); updated = now
        if fiveHour == nil && sevenDay == nil { return nil }
    }
    /// Codex's `rate_limits`: two slots, primary and secondary, either one null; the window's length tells
    /// which is the five-hour one and which the week.
    init?(codex limits: [String: Any], updated: Date) {
        for key in ["primary", "secondary"] {
            guard let raw = limits[key] as? [String: Any], let percent = (raw["used_percent"] as? NSNumber)?.doubleValue,
                  let minutes = (raw["window_minutes"] as? NSNumber)?.intValue,
                  let resets = (raw["resets_at"] as? NSNumber)?.doubleValue else { continue }
            let window = Window(percent: min(max(percent, 0), 100), resetsAt: Date(timeIntervalSince1970: resets))
            if minutes == 300 { fiveHour = window } else if minutes == 10080 { sevenDay = window }
        }
        plan = (limits["plan_type"] as? String).map { AgentApprovals.clean($0, limit: 20) }
        self.updated = updated
        if fiveHour == nil && sevenDay == nil { return nil }
    }
    /// "prolite" reads as "Pro Lite"; the rest ("plus", "pro", "team") just get a capital.
    var planTitle: String? {
        guard let plan, !plan.isEmpty else { return nil }
        return plan == "prolite" ? "Pro Lite" : plan.prefix(1).uppercased() + plan.dropFirst()
    }
    /// Drops windows that have already reset: their percentage no longer means anything.
    func current(at now: Date) -> AgentUsage? {
        var copy = self
        if let window = copy.fiveHour, window.resetsAt <= now { copy.fiveHour = nil }
        if let window = copy.sevenDay, window.resetsAt <= now { copy.sevenDay = nil }
        return copy.fiveHour == nil && copy.sevenDay == nil ? nil : copy
    }
    /// The notch warns once per window when the five-hour use passes these.
    static let warnAt: [Double] = [80, 95]
}

extension AgentUsage.Window {
    /// How far through its window we are, 0…1: where the bar would stand now if use were spread evenly.
    func elapsed(length: TimeInterval, at now: Date) -> Double {
        min(max(1 - resetsAt.timeIntervalSince(now) / length, 0), 1)
    }
    enum Outlook: Equatable { case resets, fills(Date), leaves(Int) }
    /// Where the current pace leads. In the first tenth of a window a pace means little, and a full window can
    /// only wait for its reset; both just tell the reset time.
    func outlook(length: TimeInterval, at now: Date) -> Outlook {
        let elapsed = elapsed(length: length, at: now)
        guard elapsed > 0.1, percent < 100 else { return .resets }
        let projected = percent / elapsed
        guard projected > 100 else { return .leaves(Int((100 - projected).rounded())) }
        // `percent` took `elapsed * length` seconds, so the rest goes in (100 - percent) / percent of that.
        return .fills(now.addingTimeInterval((100 - percent) / percent * elapsed * length))
    }
}

/// Codex keeps no usage file: each token_count event in a session's rollout
/// (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl) carries the plan's limits, so the newest rollout has the
/// newest numbers.
enum CodexUsage {
    static var sessions: URL {
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
        return (configured ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true))
            .appendingPathComponent("sessions", isDirectory: true)
    }

    /// Tries the newest few rollouts until one has limits, reading only the last 256 KB of each.
    static func read(root: URL = sessions) -> AgentUsage? {
        for (url, modified) in recentRollouts(in: root).prefix(3) {
            if let tail = tail(of: url), let usage = parse(tail: tail, updated: modified) { return usage }
        }
        return nil
    }

    /// Rollouts of the last few day folders, newest written first. The tree keeps every session ever, so only
    /// those folders are listed; a session started yesterday may still be the one being written today.
    static func recentRollouts(in root: URL, days: Int = 3) -> [(url: URL, modified: Date)] {
        let fm = FileManager.default
        func numbered(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).compactMap { name in Int(name).map { (name, $0) } }
                .sorted { $0.1 > $1.1 }.map { url.appendingPathComponent($0.0, isDirectory: true) }
        }
        var folders: [URL] = []
        search: for year in numbered(root) {
            for month in numbered(year) {
                for day in numbered(month) {
                    folders.append(day)
                    if folders.count == days { break search }
                }
            }
        }
        let files: [URL] = folders.flatMap { folder -> [URL] in
            (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        }
        return files.filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
            .map { url -> (url: URL, modified: Date) in
                (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    static func tail(of url: URL, bytes: UInt64 = 256 * 1024) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), (try? handle.seek(toOffset: size > bytes ? size - bytes : 0)) != nil else { return nil }
        return try? handle.readToEnd()
    }

    /// The last account-wide limits in a rollout's tail, newest line first (the first line may be cut; it just
    /// fails to parse). Limits of a single model, under another `limit_id`, are not the plan's and are skipped.
    static func parse(tail: Data, updated: Date) -> AgentUsage? {
        let marker = Data("\"rate_limits\"".utf8)
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() where line.range(of: marker) != nil {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let limits = (event["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] ?? event["rate_limits"] as? [String: Any],
                  (limits["limit_id"] as? String ?? "codex") == "codex" else { continue }
            if let usage = AgentUsage(codex: limits, updated: updated) { return usage }
        }
        return nil
    }
}

final class AgentStatusService: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var todayTurns = 0
    @Published private(set) var usage: AgentUsage?
    /// Codex's plan limits, read only while the Agents page is on screen.
    @Published private(set) var codexUsage: AgentUsage?
    private var codexWatchers = 0             // queue only
    private var codexRead = Date.distantPast  // queue only
    /// Five-hour use passed 80 % or 95 %: (percent, resets at).
    var onUsageWarning: ((Int, Date) -> Void)?
    private var usageWarned: (resetsAt: Date, threshold: Double)?
    /// Permission prompts waiting for an answer from the notch, oldest first.
    @Published private(set) var approvals: [ApprovalRequest] = []
    @Published var approvalsEnabled = AgentApprovals.enabled {
        didSet { UserDefaults.standard.set(approvalsEnabled, forKey: AgentApprovals.enabledKey) }
    }
    @Published var approvalWait = AgentApprovals.wait {
        didSet { UserDefaults.standard.set(approvalWait, forKey: AgentApprovals.waitKey) }
    }
    /// Called with each request that just arrived.
    var onApproval: ((ApprovalRequest) -> Void)?
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
            let usage = AgentEventStore.readUsage()
            // Hooks wait for the notch only while this heartbeat is fresh; with the setting off they never do.
            if AgentApprovals.enabled { AgentApprovals.heartbeat() }
            let approvals = AgentApprovals.enabled ? AgentApprovals.pending() : []
            // Rollouts are large and Codex's limits move slowly: at most once a minute, and only while watched.
            let readCodex = self.map { $0.codexWatchers > 0 && Date().timeIntervalSince($0.codexRead) >= 60 } ?? false
            if readCodex { self?.codexRead = Date() }
            let codex: AgentUsage?? = readCodex ? .some(CodexUsage.read()) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                let known = Set(self.approvals.map(\.id))
                if approvals != self.approvals { self.approvals = approvals }
                for request in approvals where !known.contains(request.id) { self.onApproval?(request) }
                if self.loaded {
                    for record in records where record.phase == .waiting || record.phase == .done || record.phase == .failed {
                        if let old = self.sessions.first(where: { $0.id == record.id }), old.phase != record.phase,
                           Date().timeIntervalSince(record.updated) < 5 { self.onChange?(record) }
                    }
                }
                self.loaded = true
                if records != self.sessions { self.sessions = records }
                if turns != self.todayTurns { self.todayTurns = turns }
                if usage != self.usage { self.usage = usage; self.checkUsage(usage) }
                if case .some(let codex) = codex, codex != self.codexUsage { self.codexUsage = codex }
                self.onRefresh?()
            }
        }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    /// The Agents page came on screen or left it; the heartbeat above picks Codex's limits up meanwhile. A count,
    /// since a page transition can show the new view before the old one is gone.
    func watchCodexUsage(_ on: Bool) {
        queue.async { self.codexWatchers = max(0, self.codexWatchers + (on ? 1 : -1)) }
    }

    /// Warns once per window and threshold. What was already true when Damla started is not news.
    func checkUsage(_ usage: AgentUsage?) {
        defer { loadedUsage = true }
        guard let window = usage?.fiveHour,
              let threshold = AgentUsage.warnAt.last(where: { window.percent >= $0 }) else { return }
        if let warned = usageWarned, warned.resetsAt == window.resetsAt, warned.threshold >= threshold { return }
        usageWarned = (window.resetsAt, threshold)
        if loadedUsage { onUsageWarning?(Int(window.percent.rounded()), window.resetsAt) }
    }
    private var loadedUsage = false

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
    /// Answers a waiting prompt; the hook picks the decision up within 0.2 s.
    func decide(_ request: ApprovalRequest, _ decision: ApprovalDecision) {
        AgentApprovals.decide(request.id, decision)
        approvals.removeAll { $0.id == request.id }
        onRefresh?()
    }
    /// Takes a request back from the notch: its hook sees the file gone and steps aside, so the agent asks in
    /// its own window instead.
    func withdraw(_ request: ApprovalRequest) {
        try? FileManager.default.removeItem(at: AgentApprovals.directory.appendingPathComponent(request.id + ".json"))
        approvals.removeAll { $0.id == request.id }
        onRefresh?()
    }
    func remove(_ session: AgentSession) {
        AgentEventStore.remove(id: session.id)
        sessions.removeAll { $0.id == session.id }
        onRefresh?()
    }
    deinit { timer?.cancel() }
}
