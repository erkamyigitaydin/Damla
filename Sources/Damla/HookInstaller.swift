import Foundation

/// Adds Damla's status hooks (and, on request, the notch approval hook) to Claude Code's and Codex's settings,
/// the same way `scripts/install-agent-hooks.py` does, so a Mac without developer tools can set it up from the
/// app. Only entries carrying Damla's marker are touched; everything else is kept as it was, a dated backup is
/// written first, and running it again changes nothing.
enum HookInstaller {
    static let marker = "Damla durumunu güncelle"
    static let approvalMarker = "Damla onayı bekleniyor · çentikten yanıtla"
    static let approvalTimeout = 150
    static let common = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]

    enum Provider: String, CaseIterable { case claude, codex }
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func settingsURL(_ provider: Provider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        provider == .claude ? home.appendingPathComponent(".claude/settings.json") : home.appendingPathComponent(".codex/hooks.json")
    }

    /// The agent is installed (its config folder exists), so offering to hook it makes sense.
    static func isAvailable(_ provider: Provider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        FileManager.default.fileExists(atPath: settingsURL(provider, home: home).deletingLastPathComponent().path)
    }

    static func isInstalled(_ provider: Provider, approvals: Bool = false, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard let data = try? Data(contentsOf: settingsURL(provider, home: home)) else { return false }
        let text = String(decoding: data, as: UTF8.self)
        return text.contains(approvals ? "--agent-approval" : "--agent-event")
    }

    /// Same quoting as Python's shlex.quote, so both installers write identical commands.
    static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Settings with Damla's hooks replaced by fresh ones for `binary`; everything else untouched.
    static func merge(_ original: [String: Any], provider: Provider, binary: String, approvals: Bool) throws -> [String: Any] {
        var data = original
        var hooks: [String: Any]
        if let existing = data["hooks"] {
            guard let dictionary = existing as? [String: Any] else { throw Failure(description: "hooks alanı nesne olmalı; mevcut ayarlar değiştirilmedi") }
            hooks = dictionary
        } else { hooks = [:] }
        func ours(_ handler: [String: Any]) -> Bool {
            let message = handler["statusMessage"] as? String, command = handler["command"] as? String ?? ""
            return (message == marker && command.contains("--agent-event")) || (message == approvalMarker && command.contains("--agent-approval"))
        }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { throw Failure(description: "Beklenmeyen hook biçimi: \(event)") }
            hooks[event] = groups.compactMap { group -> [String: Any]? in
                var copy = group
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                let kept = handlers.filter { !ours($0) }
                copy["hooks"] = kept
                return kept.isEmpty && !handlers.isEmpty ? nil : copy
            }
        }
        let command = shellQuote(binary)
        let events = common + (provider == .claude ? ["Notification", "PostToolUseFailure", "StopFailure", "PermissionDenied"] : ["Interrupt"])
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command + " --agent-event " + provider.rawValue,
                                                   "timeout": 3, "statusMessage": marker]]]
            if event == "Notification" { group["matcher"] = "permission_prompt|elicitation_dialog" }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        // Opt-in: answers Claude Code's permission prompts from the notch. A decision is only ever printed after
        // the user clicked one in Damla; otherwise Claude Code asks as usual.
        if approvals && provider == .claude {
            let group: [String: Any] = ["hooks": [["type": "command", "command": command + " --agent-approval " + provider.rawValue,
                                                   "timeout": approvalTimeout, "statusMessage": approvalMarker]]]
            hooks["PermissionRequest"] = (hooks["PermissionRequest"] as? [[String: Any]] ?? []) + [group]
        }
        data["hooks"] = hooks
        return data
    }

    /// Writes the merged settings. Returns false when they were already up to date.
    @discardableResult
    static func install(_ provider: Provider, approvals: Bool, binary: String = Bundle.main.executablePath ?? "",
                        home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = Date()) throws -> Bool {
        let url = settingsURL(provider, home: home)
        let old = try? Data(contentsOf: url)
        var original: [String: Any] = [:]
        if let old, !old.isEmpty {
            guard let parsed = try JSONSerialization.jsonObject(with: old) as? [String: Any] else { throw Failure(description: "\(url.path) bir JSON nesnesi değil") }
            original = parsed
        }
        let updated = try merge(original, provider: provider, binary: binary, approvals: approvals)
        guard !NSDictionary(dictionary: updated).isEqual(to: original) else { return false }
        let new = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
        // Never overwrite an edit made while we were merging.
        guard (try? Data(contentsOf: url)) == old else { throw Failure(description: "Ayarlar değişti; yeniden dene: \(url.path)") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let old {
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyyMMdd-HHmmss-SSS"; stamp.locale = Locale(identifier: "en_US_POSIX")
            let backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".damla-backup-" + stamp.string(from: now))
            try old.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try new.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }
}
