import Foundation

/// Checks for the in-app hook installer, in a throwaway home folder; never touches real agent settings.
func runHookInstallerSelfTests(_ check: (Bool, String) -> Void) {
    let binary = "/tmp/Project With Spaces/Damla"
    let old: [String: Any] = ["permissions": ["deny": ["Bash(rm *)"]], "disableAllHooks": true,
                              "hooks": ["Stop": [["matcher": "*", "hooks": [["type": "command", "command": "existing"]]]]]]
    guard let merged = try? HookInstaller.merge(old, provider: .claude, binary: binary, approvals: false) else { check(false, "Installer merges"); return }
    check(NSDictionary(dictionary: merged["permissions"] as? [String: Any] ?? [:]).isEqual(to: old["permissions"] as? [String: Any] ?? [:])
          && merged["disableAllHooks"] as? Bool == true, "Installer keeps permissions and switches")
    let stop = (merged["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
    check(stop.count == 2 && ((stop.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "existing", "Installer keeps other hooks first")
    check(((stop.last?["hooks"] as? [[String: Any]])?.first?["command"] as? String)?.hasPrefix("'/tmp/Project With Spaces/Damla' --agent-event claude") == true,
          "Installer quotes paths like shlex")
    let again = try? HookInstaller.merge(merged, provider: .claude, binary: binary, approvals: false)
    check(again.map { NSDictionary(dictionary: $0).isEqual(to: merged) } == true, "Installer is idempotent")
    check((merged["statusLine"] as? [String: Any])?["command"] as? String == "'/tmp/Project With Spaces/Damla' --agent-status claude",
          "Claude Code gets Damla's status line")
    let mine = HookInstaller.statusLine(["type": "command", "command": "~/bin/line.sh --short", "padding": 2], command: "/A/Damla")
    let moved = HookInstaller.statusLine(mine, command: "/B/Damla")
    check(mine["padding"] as? Int == 2 && mine["command"] as? String == "/A/Damla --agent-status claude --then '~/bin/line.sh --short'"
          && moved["command"] as? String == "/B/Damla --agent-status claude --then '~/bin/line.sh --short'"
          && HookInstaller.shellUnquote(HookInstaller.shellQuote("it's")) == "it's", "A status line of the user's own keeps running, wrapped")
    let text = { (object: [String: Any]) in String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self) }
    check(!text(merged).contains("--agent-approval") && !text(merged).contains("behavior"), "Approval hook only on request; no decision in settings")
    let codex = (try? HookInstaller.merge([:], provider: .codex, binary: binary, approvals: true)) ?? [:]
    let codexPlain = (try? HookInstaller.merge([:], provider: .codex, binary: binary, approvals: false)) ?? [:]
    check(text(codex).contains("--agent-approval codex") && !text(codexPlain).contains("--agent-approval") && text(codex).contains("Interrupt")
          && !text(codex).contains("--agent-question"), "Codex gets the approval hook only on request, and no question hook")
    let withApprovals = (try? HookInstaller.merge(merged, provider: .claude, binary: binary, approvals: true)) ?? [:]
    let removed = (try? HookInstaller.merge(withApprovals, provider: .claude, binary: binary, approvals: false)) ?? [:]
    check(text(withApprovals).contains("--agent-approval") && !text(removed).contains("--agent-approval")
          && text(withApprovals).contains("--agent-question claude") && !text(removed).contains("--agent-question")
          && NSDictionary(dictionary: removed).isEqual(to: merged), "Approval hook can be taken out again")
    let trustHome = FileManager.default.temporaryDirectory.appendingPathComponent("Damla-trust-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: trustHome) }
    try? FileManager.default.createDirectory(at: trustHome.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    try? JSONSerialization.data(withJSONObject: codex).write(to: HookInstaller.settingsURL(.codex, home: trustHome))
    let untrusted = HookInstaller.codexApprovalTrusted(home: trustHome)
    let hooksPath = HookInstaller.settingsURL(.codex, home: trustHome).path
    try? Data("[hooks.state.\"\(hooksPath):permission_request:1:0\"]\ntrusted_hash = \"sha256:x\"\n".utf8)
        .write(to: trustHome.appendingPathComponent(".codex/config.toml"))
    check(untrusted == false && HookInstaller.codexApprovalTrusted(home: trustHome) == true, "Codex approval hook reports whether /hooks trusted it")
    check((try? HookInstaller.merge(["hooks": [1, 2]], provider: .claude, binary: binary, approvals: false)) == nil, "Unexpected hooks shape is refused")

    let home = FileManager.default.temporaryDirectory.appendingPathComponent("Damla-hooks-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    let settings = HookInstaller.settingsURL(.claude, home: home)
    try? FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONSerialization.data(withJSONObject: old).write(to: settings)
    let first = (try? HookInstaller.install(.claude, approvals: false, binary: binary, home: home)) ?? false
    let second = (try? HookInstaller.install(.claude, approvals: false, binary: binary, home: home)) ?? true
    let backups = ((try? FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path)) ?? []).filter { $0.contains(".damla-backup-") }
    let mode = ((try? FileManager.default.attributesOfItem(atPath: settings.path))?[.posixPermissions] as? NSNumber)?.intValue ?? 0
    check(first && !second && backups.count == 1 && mode == 0o600 && HookInstaller.isInstalled(.claude, home: home),
          "Install writes once, backs up, keeps the file private")
}
