import AppKit

/// A tool call waiting for the user's permission, written by the `--agent-approval` hook while it waits and
/// removed as soon as it returns. It holds the command or path being approved (the user has to see what they
/// allow), but never the prompt, the transcript or tool output.
struct ApprovalRequest: Codable, Identifiable, Equatable {
    var id: String            // random UUID, also the file name
    var session: String       // AgentSession.id of the asking session
    var provider: AgentProvider
    var project: String
    var tool: String
    var summary: String       // the command, file path, URL…
    var detail: String        // Claude's own description of a command, when given
    var host: String?         // app hosting the session (Terminal, Claude, VS Code…)
    var created: Date
    var deadline: Date
}

enum ApprovalDecision: String { case allow, deny }

/// Lets the notch answer Claude Code's permission prompts. The hook process (`Damla --agent-approval claude`,
/// installed only with `install-agent-hooks.py --approvals`) writes a request file and waits for a decision
/// file from the app. It steps aside, printing nothing so the normal terminal prompt appears, when:
/// the setting is off, Damla is not running, the app hosting the session is in front (the user is looking at
/// the prompt already), the prompt was answered in the terminal, or no decision came before the deadline.
enum AgentApprovals {
    static let enabledKey = "agentApprovals"
    static let waitKey = "agentApprovalWait"
    static let waitChoices: [TimeInterval] = [30, 60, 120]
    static let defaultWait: TimeInterval = 60
    static let heartbeatMaxAge: TimeInterval = 4
    static var directory: URL { AgentEventStore.directory.appendingPathComponent("approvals", isDirectory: true) }

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var wait: TimeInterval {
        let value = UserDefaults.standard.double(forKey: waitKey)
        return waitChoices.contains(value) ? value : defaultWait
    }

    // MARK: What is being approved

    /// The line the user decides on: a command, a path, a URL; for anything else a compact JSON of the input.
    static func summary(tool: String, input: [String: Any]) -> (summary: String, detail: String) {
        func text(_ key: String) -> String? { (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let summary: String
        switch tool {
        case "Bash": summary = text("command") ?? ""
        case "Edit", "Write", "MultiEdit", "Read", "NotebookEdit": summary = text("file_path") ?? text("notebook_path") ?? ""
        case "WebFetch": summary = text("url") ?? ""
        case "WebSearch": summary = text("query") ?? ""
        case "Glob", "Grep": summary = [text("pattern"), text("path")].compactMap { $0 }.joined(separator: " · ")
        default:
            let data = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            summary = String(decoding: data, as: UTF8.self)
        }
        let detail = tool == "Bash" ? text("description") ?? "" : ""
        return (clean(summary, limit: 2000), clean(detail, limit: 200))
    }

    /// Drops control characters (a terminal escape in a command must not reach the UI) and caps the length.
    static func clean(_ value: String, limit: Int) -> String {
        let scalars = value.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(scalars))
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// The hook's stdout for Claude Code's PermissionRequest decision control.
    static func output(_ decision: ApprovalDecision) -> Data {
        var inner: [String: Any] = ["behavior": decision.rawValue]
        if decision == .deny { inner["message"] = String(localized: "Kullanıcı Damla'dan reddetti.") }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": inner]]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    // MARK: Hook side

    /// Everything the waiting hook needs from the outside world, injectable for the self-test.
    struct Environment {
        var now: () -> Date = Date.init
        var pause: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }
        var hostIsFrontmost: (String?) -> Bool = { host in
            guard let host else { return false }
            return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host
        }
        var enabled: () -> Bool = { AgentApprovals.enabled }
        var wait: () -> TimeInterval = { AgentApprovals.wait }
    }

    /// Hook entry point. Returns the decision to print, or nil to step aside.
    static func handle(provider: AgentProvider, input: Data, host: String?, directory: URL = directory,
                       sessions: URL = AgentEventStore.directory, environment env: Environment = Environment()) -> ApprovalDecision? {
        guard env.enabled(), input.count <= 2 * 1024 * 1024,
              let event = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              event["hook_event_name"] as? String == "PermissionRequest",
              let sessionKey = event["session_id"] as? String, !sessionKey.isEmpty, sessionKey.count <= 512,
              let tool = event["tool_name"] as? String,
              !AgentSession.questionTools.contains(tool) else { return nil }   // questions need an answer, not a yes
        let start = env.now()
        guard appAlive(directory: directory, now: start), !env.hostIsFrontmost(host) else { return nil }
        let cwd = event["cwd"] as? String ?? ""
        let (summary, detail) = Self.summary(tool: tool, input: event["tool_input"] as? [String: Any] ?? [:])
        let request = ApprovalRequest(id: UUID().uuidString, session: AgentSession.identifier(provider: provider, session: sessionKey),
                                      provider: provider, project: cwd.isEmpty ? String(localized: "Oturum") : clean(URL(fileURLWithPath: cwd).lastPathComponent, limit: 80),
                                      tool: clean(tool, limit: 120), summary: summary, detail: detail, host: host,
                                      created: start, deadline: start.addingTimeInterval(env.wait()))
        guard write(request, directory: directory) else { return nil }
        let requestFile = directory.appendingPathComponent(request.id + ".json")
        let decisionFile = directory.appendingPathComponent(request.id + ".decision")
        defer { try? FileManager.default.removeItem(at: requestFile); try? FileManager.default.removeItem(at: decisionFile) }
        // Claude Code ends the hook with SIGTERM on its timeout; leave no request behind then either.
        cleanupOnTerm = [requestFile.path, decisionFile.path]
        signal(SIGTERM) { _ in
            for path in AgentApprovals.cleanupOnTerm { unlink(path) }
            _exit(0)
        }
        while env.now() < request.deadline {
            if let raw = try? String(contentsOf: decisionFile, encoding: .utf8),
               let decision = ApprovalDecision(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) { return decision }
            if !FileManager.default.fileExists(atPath: requestFile.path) { return nil }   // withdrawn by the app
            if env.hostIsFrontmost(host) { return nil }   // the user went to the terminal: its prompt takes over
            if answeredElsewhere(request, sessions: sessions) { return nil }
            env.pause(0.2)
        }
        return nil
    }
    nonisolated(unsafe) private static var cleanupOnTerm: [String] = []

    /// The session moved on after the request (a tool ran, the turn stopped): it was answered in the terminal.
    static func answeredElsewhere(_ request: ApprovalRequest, sessions: URL) -> Bool {
        let file = sessions.appendingPathComponent(request.session + ".json")
        guard let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(AgentSession.self, from: data) else { return false }
        return record.updated > request.created.addingTimeInterval(0.5) && record.phase != .waiting
    }

    private static func write(_ request: ApprovalRequest, directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = directory.appendingPathComponent(request.id + ".json")
            try JSONEncoder().encode(request).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch { return false }
    }

    // MARK: App side

    /// The app touches this file every second; a hook only waits when Damla is there to answer.
    static func heartbeat(directory: URL = directory, now: Date = Date()) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("app.alive")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
    }

    static func appAlive(directory: URL = directory, now: Date = Date()) -> Bool {
        let file = directory.appendingPathComponent("app.alive")
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else { return false }
        return abs(now.timeIntervalSince(modified)) < heartbeatMaxAge
    }

    /// Requests still waiting, oldest first. Leftovers past their deadline (a killed hook) are cleared.
    static func pending(directory: URL = directory, now: Date = Date()) -> [ApprovalRequest] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> ApprovalRequest? in
            guard let data = try? Data(contentsOf: url), data.count < 64_000,
                  let request = try? JSONDecoder().decode(ApprovalRequest.self, from: data) else { return nil }
            if now > request.deadline.addingTimeInterval(5) {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(request.id + ".decision"))
                return nil
            }
            return now <= request.deadline ? request : nil
        }.sorted { $0.created < $1.created }
    }

    static func decide(_ id: String, _ decision: ApprovalDecision, directory: URL = directory) {
        guard UUID(uuidString: id) != nil else { return }   // ids are ours; never a path
        let file = directory.appendingPathComponent(id + ".decision")
        try? Data(decision.rawValue.utf8).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
