import Foundation

func runCodexApprovalRoutingSelfTests(_ check: (Bool, String) -> Void) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Damla-codex-routing-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("session.jsonl")
    func line(_ type: String, _ payload: [String: Any]) -> Data {
        var data = try! JSONSerialization.data(withJSONObject: ["type": type, "payload": payload])
        data.append(10); return data
    }
    let header = line("session_meta", ["id": "session"])
    func context(_ reviewer: String, turn: String = "turn") -> Data {
        line("turn_context", ["turn_id": turn, "approvals_reviewer": reviewer])
    }
    func write(_ data: Data) { try! data.write(to: file) }
    let event: [String: Any] = ["session_id": "session", "turn_id": "turn", "transcript_path": file.path]
    let user = context("user"), automatic = context("auto_review")
    write(header + user)
    check(CodexApprovalRouting.reviewer(event) == .user, "Codex manual reviewer is resolved for the exact session and turn")
    write(header + automatic)
    check(CodexApprovalRouting.reviewer(event) == .automatic, "Codex automatic reviewer is resolved without command heuristics")
    write(header + user + automatic)
    check(CodexApprovalRouting.reviewer(event) == .automatic, "Switching the same turn to automatic review supersedes manual approval")
    write(header + automatic + user)
    check(CodexApprovalRouting.reviewer(event) == .user, "Switching back to manual approval is honored")
    write(header + user + context("auto_review", turn: "new-turn"))
    check(CodexApprovalRouting.reviewer(event) == nil, "A newer turn prevents reuse of a stale manual policy")
    write(header + user)
    var other = event; other["session_id"] = "another-session"
    check(CodexApprovalRouting.reviewer(other) == nil, "Approval metadata from another session is rejected")
    other = event; other["turn_id"] = "another-turn"
    check(CodexApprovalRouting.reviewer(other) == nil, "Approval metadata from another turn is rejected")
    other = event; other.removeValue(forKey: "turn_id")
    check(CodexApprovalRouting.reviewer(other) == nil, "An unidentified turn falls back to Codex")
    other = event; other["session_id"] = "parent"; other["agent_id"] = "session"
    check(CodexApprovalRouting.reviewer(other) == .user, "Subagent metadata is matched to the child, not the parent")
    write(header + user + line("turn_context", ["turn_id": "turn"]))
    check(CodexApprovalRouting.reviewer(event) == nil, "Missing reviewer metadata never falls back to an older manual policy")
    write(header + user + context("future-mode"))
    check(CodexApprovalRouting.reviewer(event) == nil, "Unknown reviewer formats leave the decision to Codex")
    write(header + automatic + line("response_item", ["type": "message", "content": "turn_context approvals_reviewer user"]))
    check(CodexApprovalRouting.reviewer(event) == .automatic, "Message text cannot impersonate approval metadata")
    write(header + user + Data("{\"type\":\"turn_context\",\"payload\":".utf8))
    check(CodexApprovalRouting.reviewer(event) == nil, "Partially written context does not reuse an earlier manual policy")
    write(header + Data(repeating: 120, count: CodexApprovalRouting.readLimit + 1) + Data([10]) + user)
    check(CodexApprovalRouting.reviewer(event) == .user, "Large transcripts are read from a bounded tail")
    write(header + user + Data(repeating: 120, count: CodexApprovalRouting.readLimit + 1))
    check(CodexApprovalRouting.reviewer(event) == nil, "An out-of-range context falls back without scanning the whole transcript")

    // The same command has different routing depending on who is meant to review it.
    for reviewer: CodexApprovalRouting.Reviewer? in [.user, .automatic, nil] {
        var session = AgentSession(id: "test", provider: .codex, project: "p", updated: Date())
        let now = Date()
        _ = session.apply(["hook_event_name": "UserPromptSubmit"], at: now)
        _ = session.apply(["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_use_id": "cmd"], at: now, codexReviewer: reviewer)
        check(session.phase == .working && session.pending.isEmpty, "An ordinary command never claims to need approval (\(String(describing: reviewer)))")
        _ = session.apply(["hook_event_name": "PermissionRequest", "tool_name": "Bash"], at: now, codexReviewer: reviewer)
        check(session.phase == (reviewer == .user ? .waiting : .working), "Only a confirmed human permission request sets waiting (\(String(describing: reviewer)))")
        _ = session.apply(["hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_use_id": "cmd"], at: now)
        check(session.phase == .working && session.pending.isEmpty, "Command completion clears a manual approval wait")
    }
    var permission = AgentSession(id: "permission", provider: .codex, project: "p", updated: Date())
    _ = permission.apply(["hook_event_name": "PreToolUse", "tool_name": "request_permissions"], at: Date(), codexReviewer: .automatic)
    check(permission.phase == .working, "Automatically reviewed permission tools do not claim a human wait")
    _ = permission.apply(["hook_event_name": "PreToolUse", "tool_name": "request_user_input"], at: Date(), codexReviewer: .automatic)
    check(permission.phase == .waiting && permission.detail == "Yanıt bekliyor", "User questions remain visible during automatic review")

    // Exercise the production hook event-store path, not just direct reducer calls.
    let store = root.appendingPathComponent("agents")
    var hook = event
    hook["hook_event_name"] = "PermissionRequest"; hook["tool_name"] = "Bash"
    write(header + user)
    try? AgentEventStore.receive(provider: .codex, input: JSONSerialization.data(withJSONObject: hook), directory: store)
    check(AgentEventStore.read(directory: store).first?.phase == .waiting, "The status hook uses matching metadata for real manual approvals")
    AgentEventStore.remove(id: AgentSession.identifier(provider: .codex, session: "session"), directory: store)
    write(header + automatic)
    try? AgentEventStore.receive(provider: .codex, input: JSONSerialization.data(withJSONObject: hook), directory: store)
    check(AgentEventStore.read(directory: store).isEmpty, "An automatic review event creates no phantom waiting session")
}
