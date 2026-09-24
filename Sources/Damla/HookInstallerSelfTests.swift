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
    let text = { (object: [String: Any]) in String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self) }
    check(!text(merged).contains("--agent-approval") && !text(merged).contains("behavior"), "Approval hook only on request; no decision in settings")
    let codex = (try? HookInstaller.merge([:], provider: .codex, binary: binary, approvals: true)) ?? [:]
    check(!text(codex).contains("--agent-approval") && text(codex).contains("Interrupt"), "Codex never gets the approval hook")
    let withApprovals = (try? HookInstaller.merge(merged, provider: .claude, binary: binary, approvals: true)) ?? [:]
    let removed = (try? HookInstaller.merge(withApprovals, provider: .claude, binary: binary, approvals: false)) ?? [:]
    check(text(withApprovals).contains("--agent-approval") && !text(removed).contains("--agent-approval")
          && NSDictionary(dictionary: removed).isEqual(to: merged), "Approval hook can be taken out again")
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
