import Foundation

/// Checks for answering permission prompts from the notch, in throwaway folders with a fake clock-free wait.
func runApprovalSelfTests(_ check: (Bool, String) -> Void) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Damla-approval-test-\(UUID().uuidString)")
    let approvals = root.appendingPathComponent("approvals"), sessions = root.appendingPathComponent("sessions")
    try? FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func event(_ tool: String = "Bash", _ input: [String: Any] = ["command": "rm -rf build", "description": "Derleme klasörünü sil"]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/x/Projem",
                                                     "tool_name": tool, "tool_input": input])
    }
    var env = AgentApprovals.Environment()
    env.pause = { Thread.sleep(forTimeInterval: $0) }
    env.hostIsFrontmost = { _ in false }
    env.enabled = { true }
    env.wait = { 1.5 }
    func requestFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: approvals, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
    }
    /// Answers the first request that appears, from another thread, the way the app would.
    func answer(_ decision: ApprovalDecision, after delay: TimeInterval = 0.3) {
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            if let request = AgentApprovals.pending(directory: approvals).first { AgentApprovals.decide(request.id, decision, directory: approvals) }
        }
    }

    // What the user sees.
    let bash = AgentApprovals.summary(tool: "Bash", input: ["command": "git push\u{1b}[2J --force", "description": "Gönder"])
    check(bash.summary == "git push[2J --force" && bash.detail == "Gönder", "Command shown in full, terminal escapes stripped")
    check(AgentApprovals.summary(tool: "Edit", input: ["file_path": "/a/b.swift", "old_string": "x"]).summary == "/a/b.swift", "File edits show the path")
    check(AgentApprovals.summary(tool: "mcp__figma__use", input: ["a": 1]).summary == "{\"a\":1}", "Other tools show their input")
    check(AgentApprovals.summary(tool: "Bash", input: ["command": String(repeating: "x", count: 5000)]).summary.count == 2001, "Very long input is capped")
    check(ApprovalCard.title(for: "mcp__figma__use_figma") == "figma aracını kullanmak istiyor", "MCP tools are named by server")

    // What Claude Code reads.
    let allow = try? JSONSerialization.jsonObject(with: AgentApprovals.output(.allow)) as? [String: Any]
    let allowDecision = (allow?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    check((allow?["hookSpecificOutput"] as? [String: Any])?["hookEventName"] as? String == "PermissionRequest"
          && allowDecision?["behavior"] as? String == "allow" && allowDecision?["message"] == nil, "Allow uses decision.behavior")
    let deny = try? JSONSerialization.jsonObject(with: AgentApprovals.output(.deny)) as? [String: Any]
    let denyDecision = (deny?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    check(denyDecision?["behavior"] as? String == "deny" && denyDecision?["message"] is String, "Deny tells Claude why")

    // The hook steps aside unless Damla can answer.
    check(AgentApprovals.handle(provider: .claude, input: event(), host: nil, directory: approvals, sessions: sessions, environment: env) == nil
          && requestFiles().isEmpty, "Without Damla running the hook returns at once")
    AgentApprovals.heartbeat(directory: approvals)
    check(AgentApprovals.appAlive(directory: approvals), "Heartbeat marks Damla as present")
    check(!AgentApprovals.appAlive(directory: approvals, now: Date().addingTimeInterval(10)), "A stale heartbeat does not")
    var front = env; front.hostIsFrontmost = { $0 == "com.apple.Terminal" }
    check(AgentApprovals.handle(provider: .claude, input: event(), host: "com.apple.Terminal", directory: approvals, sessions: sessions, environment: front) == nil,
          "Terminal in front: its own prompt answers")
    var off = env; off.enabled = { false }
    check(AgentApprovals.handle(provider: .claude, input: event(), host: nil, directory: approvals, sessions: sessions, environment: off) == nil, "Setting off: never waits")
    check(AgentApprovals.handle(provider: .claude, input: event("AskUserQuestion", [:]), host: nil, directory: approvals, sessions: sessions, environment: env) == nil,
          "Questions are left to the terminal")

    // Decisions from the notch.
    answer(.allow)
    check(AgentApprovals.handle(provider: .claude, input: event(), host: nil, directory: approvals, sessions: sessions, environment: env) == .allow, "Allow from the notch reaches the hook")
    check(requestFiles().isEmpty, "Answered request leaves no file behind")
    AgentApprovals.heartbeat(directory: approvals)
    answer(.deny)
    check(AgentApprovals.handle(provider: .claude, input: event(), host: nil, directory: approvals, sessions: sessions, environment: env) == .deny, "Deny from the notch reaches the hook")
    AgentApprovals.heartbeat(directory: approvals)
    let started = Date()
    check(AgentApprovals.handle(provider: .claude, input: event(), host: nil, directory: approvals, sessions: sessions, environment: env) == nil
          && Date().timeIntervalSince(started) < 3 && requestFiles().isEmpty, "No answer: gives up at the deadline and cleans up")

    // Answered in the terminal: the session moves on and the hook stops waiting.
    AgentApprovals.heartbeat(directory: approvals)
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
        let record = AgentSession(id: AgentSession.identifier(provider: .claude, session: "s1"), provider: .claude, project: "Projem",
                                  phase: .working, updated: Date().addingTimeInterval(1))
        try? JSONEncoder().encode(record).write(to: sessions.appendingPathComponent(record.id + ".json"))
    }
    var slow = env; slow.wait = { 5 }
    let before = Date()
    check(AgentApprovals.handle(provider: .claude, input: event(), host: nil, directory: approvals, sessions: sessions, environment: slow) == nil
          && Date().timeIntervalSince(before) < 2, "Answered in the terminal: the notch withdraws")

    // App side housekeeping.
    let leftover = ApprovalRequest(id: UUID().uuidString, session: "x", provider: .claude, project: "p", tool: "Bash", summary: "ls", detail: "",
                                   host: nil, created: Date().addingTimeInterval(-100), deadline: Date().addingTimeInterval(-40))
    try? JSONEncoder().encode(leftover).write(to: approvals.appendingPathComponent(leftover.id + ".json"))
    check(AgentApprovals.pending(directory: approvals).isEmpty && requestFiles().isEmpty, "A killed hook's request is cleared")
    AgentApprovals.decide("../../etc/passwd", .allow, directory: approvals)
    check(!FileManager.default.fileExists(atPath: approvals.appendingPathComponent("../../etc/passwd.decision").path), "Decisions only for real request ids")
}
