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
    /// Rules Claude Code offers to remember ("Bash(npm test:*) · bu proje"), in `alwaysEntries` order.
    var always: [String]? = nil
    /// Set when Claude asks a multiple-choice question (AskUserQuestion) instead of a permission.
    var questions: [QuestionPrompt]? = nil
}

/// One AskUserQuestion question, as far as the notch needs it.
struct QuestionPrompt: Codable, Equatable {
    struct Option: Codable, Equatable { var label: String; var description: String? }
    var question: String
    var header: String
    var options: [Option]
    var multiSelect: Bool
}

enum ApprovalDecision: Equatable {
    case allow, deny
    case allowAlways(Int)             // index into the request's `always` rules
    case answer([String: String])     // question text → chosen label(s), joined with ", " when several

    /// How the app hands the decision to the waiting hook (the `.decision` file).
    var fileText: String {
        switch self {
        case .allow: return "allow"
        case .deny: return "deny"
        case .allowAlways(let index): return "always:\(index)"
        case .answer(let answers):
            let data = (try? JSONSerialization.data(withJSONObject: answers, options: [.sortedKeys])) ?? Data()
            return "answer:" + String(decoding: data, as: UTF8.self)
        }
    }
    var isAnswer: Bool { if case .answer = self { return true } else { return false } }
    init?(fileText raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch text {
        case "allow": self = .allow
        case "deny": self = .deny
        default:
            if text.hasPrefix("always:"), let index = Int(text.dropFirst(7)), index >= 0 { self = .allowAlways(index); return }
            guard text.hasPrefix("answer:"),
                  let answers = try? JSONSerialization.jsonObject(with: Data(text.dropFirst(7).utf8)) as? [String: String] else { return nil }
            self = .answer(answers)
        }
    }
}

/// Lets the notch answer Claude Code's and Codex's permission prompts. The hook process (`Damla --agent-approval
/// claude|codex`, installed only on request) writes a request file and waits for a decision
/// file from the app. It steps aside, printing nothing so the normal terminal prompt appears, when:
/// the setting is off, Damla is not running, the app hosting the session is in front (the user is looking at
/// the prompt already), the prompt was answered in the terminal, or no decision came before the deadline.
enum AgentApprovals {
    static let enabledKey = "agentApprovals"
    static let waitKey = "agentApprovalWait"
    static let waitChoices: [TimeInterval] = [30, 60, 120]
    static let defaultWait: TimeInterval = 60
    /// Codex runs the hook before it shows its own prompt, and a question hook runs before Claude Code shows the
    /// question, so the terminal stays silent while the notch waits. Leaving for the host app ends the wait at
    /// once; when the host is unknown that cannot happen, so the silence is kept short.
    static let silentUnknownHostWait: TimeInterval = 30
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
        case "AskUserQuestion": summary = questions(input)?.first?.question ?? ""
        case "apply_patch": summary = patchFiles(text("command") ?? text("patch") ?? text("input") ?? "")
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

    /// Codex's patch as one line per file: "~ a.swift" changed, "+ b.swift" added, "− c.swift" deleted.
    static func patchFiles(_ patch: String) -> String {
        let marks = [("*** Update File: ", "~ "), ("*** Add File: ", "+ "), ("*** Delete File: ", "− "), ("*** Move to: ", "→ ")]
        let lines = patch.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> String? in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard let (prefix, mark) = marks.first(where: { line.hasPrefix($0.0) }) else { return nil }
            return mark + line.dropFirst(prefix.count)
        }
        return lines.isEmpty ? patch : lines.joined(separator: "\n")
    }

    /// How long the notch waits for this request (see `silentUnknownHostWait`).
    static func effectiveWait(_ wait: TimeInterval, provider: AgentProvider, host: String?, question: Bool = false) -> TimeInterval {
        (provider == .codex || question) && host == nil ? min(wait, silentUnknownHostWait) : wait
    }

    /// The "don't ask again" updates Claude Code suggested that the notch can offer: allow rules and extra
    /// folders. Codex rejects permission updates, so it never gets any.
    static func alwaysEntries(_ event: [String: Any], provider: AgentProvider) -> [[String: Any]] {
        guard provider == .claude else { return [] }
        return (event["permission_suggestions"] as? [[String: Any]] ?? []).filter { entry in
            switch entry["type"] as? String {
            case "addRules": return entry["behavior"] as? String == "allow" && !(entry["rules"] as? [[String: Any]] ?? []).isEmpty
            case "addDirectories": return !(entry["directories"] as? [String] ?? []).isEmpty
            default: return false
            }
        }.prefix(3).map { $0 }
    }

    /// "Bash(npm test:*) · bu proje", "~/Code · tüm projeler".
    static func alwaysLabel(_ entry: [String: Any]) -> String {
        let what: String
        if let rules = entry["rules"] as? [[String: Any]] {
            what = rules.compactMap { rule -> String? in
                guard let tool = rule["toolName"] as? String else { return nil }
                return (rule["ruleContent"] as? String).map { "\(tool)(\($0))" } ?? tool
            }.joined(separator: ", ")
        } else {
            what = (entry["directories"] as? [String] ?? []).joined(separator: ", ")
        }
        let place: String
        switch entry["destination"] as? String {
        case "session": place = String(localized: "bu oturum")
        case "localSettings": place = String(localized: "bu proje, yalnızca sende")
        case "projectSettings": place = String(localized: "bu proje")
        case "userSettings": place = String(localized: "tüm projeler")
        default: place = ""
        }
        return clean(place.isEmpty ? what : what + " · " + place, limit: 300)
    }

    /// AskUserQuestion's questions, when they are the plain kind the notch can show (one to four, with options).
    static func questions(_ input: [String: Any]) -> [QuestionPrompt]? {
        guard let raw = input["questions"] as? [[String: Any]], (1...4).contains(raw.count) else { return nil }
        let parsed = raw.compactMap { item -> QuestionPrompt? in
            guard let question = item["question"] as? String, !question.isEmpty,
                  let options = item["options"] as? [[String: Any]], (1...8).contains(options.count) else { return nil }
            let choices = options.compactMap { option -> QuestionPrompt.Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return QuestionPrompt.Option(label: clean(label, limit: 120), description: (option["description"] as? String).map { clean($0, limit: 200) })
            }
            guard choices.count == options.count else { return nil }
            return QuestionPrompt(question: clean(question, limit: 400), header: clean(item["header"] as? String ?? "", limit: 40),
                                  options: choices, multiSelect: item["multiSelect"] as? Bool ?? false)
        }
        return parsed.count == raw.count ? parsed : nil
    }

    /// Drops control characters (a terminal escape in a command must not reach the UI) and caps the length.
    static func clean(_ value: String, limit: Int) -> String {
        let scalars = value.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(scalars))
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// The hook's stdout for the decision. PermissionRequest answers the same way for Claude Code and Codex;
    /// "always" echoes the suggestion Claude Code made; a question answer goes back through PreToolUse with the
    /// original questions plus `answers`. Returns empty data when the decision does not fit the event.
    static func output(_ decision: ApprovalDecision, input: Data = Data(#"{"hook_event_name":"PermissionRequest"}"#.utf8),
                       provider: AgentProvider = .claude) -> Data {
        guard let event = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { return Data() }
        let object: [String: Any]
        if event["hook_event_name"] as? String == "PreToolUse" {
            guard case .answer(let answers) = decision, var toolInput = event["tool_input"] as? [String: Any] else { return Data() }
            toolInput["answers"] = answers
            object = ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": toolInput]]
        } else {
            var inner: [String: Any]
            switch decision {
            case .allow: inner = ["behavior": "allow"]
            case .deny: inner = ["behavior": "deny", "message": String(localized: "Kullanıcı Damla'dan reddetti.")]
            case .allowAlways(let index):
                let entries = alwaysEntries(event, provider: provider)
                inner = ["behavior": "allow"]
                if entries.indices.contains(index) { inner["updatedPermissions"] = [entries[index]] }
            case .answer: return Data()
            }
            object = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": inner]]
        }
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
              let sessionKey = event["session_id"] as? String, !sessionKey.isEmpty, sessionKey.count <= 512,
              let tool = event["tool_name"] as? String else { return nil }
        let toolInput = event["tool_input"] as? [String: Any] ?? [:]
        // Permission prompts come through PermissionRequest; Claude Code's multiple-choice questions through
        // PreToolUse. Other agents' questions need a typed answer, not a yes.
        var questions: [QuestionPrompt]?
        switch event["hook_event_name"] as? String {
        case "PermissionRequest":
            guard !AgentSession.questionTools.contains(tool) else { return nil }
        case "PreToolUse":
            guard provider == .claude, tool == "AskUserQuestion", let parsed = Self.questions(toolInput) else { return nil }
            questions = parsed
        default:
            return nil
        }
        let start = env.now()
        guard appAlive(directory: directory, now: start), !env.hostIsFrontmost(host) else { return nil }
        let cwd = event["cwd"] as? String ?? ""
        let (summary, detail) = Self.summary(tool: tool, input: toolInput)
        let always = alwaysEntries(event, provider: provider).map(alwaysLabel)
        let wait = effectiveWait(env.wait(), provider: provider, host: host, question: questions != nil)
        let request = ApprovalRequest(id: UUID().uuidString, session: AgentSession.identifier(provider: provider, session: sessionKey),
                                      provider: provider, project: cwd.isEmpty ? String(localized: "Oturum") : clean(URL(fileURLWithPath: cwd).lastPathComponent, limit: 80),
                                      tool: clean(tool, limit: 120), summary: summary, detail: detail, host: host,
                                      created: start, deadline: start.addingTimeInterval(wait),
                                      always: always.isEmpty ? nil : always, questions: questions)
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
            if let raw = try? String(contentsOf: decisionFile, encoding: .utf8), let decision = ApprovalDecision(fileText: raw) {
                // A question only takes answers; a permission prompt never does.
                return (questions != nil) == (decision.isAnswer) ? decision : nil
            }
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
        try? Data(decision.fileText.utf8).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
