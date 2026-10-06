import Foundation

/// Adds Damla's status hooks (and, on request, the notch approval hook) to Claude Code's and Codex's settings,
/// the same way `scripts/install-agent-hooks.py` does, so a Mac without developer tools can set it up from the
/// app. Only entries carrying Damla's marker are touched; everything else is kept as it was, a dated backup is
/// written first, and running it again changes nothing.
enum HookInstaller {
    static let marker = "Damla durumunu güncelle"
    static let approvalMarker = "Damla onayı bekleniyor · çentikten yanıtla"
    static let questionMarker = "Damla sorusu · çentikten yanıtla"
    static let approvalTimeout = 150
    static let common = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"]

    enum Provider: String, CaseIterable { case claude, codex }
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func settingsURL(_ provider: Provider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        provider == .claude ? home.appendingPathComponent(".claude/settings.json") : home.appendingPathComponent(".codex/hooks.json")
    }

    /// Claude Code reads its settings from CLAUDE_CONFIG_DIR when that is set, which people use to keep one
    /// account per editor (the VS Code extension started with ~/.claude-default, say). Each config folder in use
    /// gets the hooks: ~/.claude, the environment's folder, and every ~/.claude-* folder Claude Code has kept
    /// sessions in (other tools' ~/.claude-mem and the like have none). The environment only counts for the real
    /// home, so a test home never reaches the user's settings.
    static func claudeDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                  environment: [String: String]? = nil) -> [URL] {
        let fm = FileManager.default
        let realHome = home.standardizedFileURL.path == fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        let env = environment ?? (realHome ? ProcessInfo.processInfo.environment : [:])
        func isDirectory(_ url: URL) -> Bool {
            var directory: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
        var found: [URL] = []
        let standard = home.appendingPathComponent(".claude", isDirectory: true)
        if isDirectory(standard) { found.append(standard) }
        if let configured = env["CLAUDE_CONFIG_DIR"], configured.hasPrefix("/") {
            let url = URL(fileURLWithPath: configured, isDirectory: true)
            if isDirectory(url) { found.append(url) }
        }
        let names = ((try? fm.contentsOfDirectory(atPath: home.path)) ?? []).filter { $0.hasPrefix(".claude-") }.sorted()
        for name in names {
            let url = home.appendingPathComponent(name, isDirectory: true)
            if isDirectory(url.appendingPathComponent("projects")) || fm.fileExists(atPath: url.appendingPathComponent("history.jsonl").path) {
                found.append(url)
            }
        }
        var seen = Set<String>()
        found = found.filter { seen.insert($0.resolvingSymlinksInPath().standardizedFileURL.path).inserted }
        return found.isEmpty ? [standard] : found
    }

    /// Every settings file the provider reads: one per Claude Code config folder, Codex's single hooks file.
    static func settingsURLs(_ provider: Provider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        provider == .claude ? claudeDirectories(home: home).map { $0.appendingPathComponent("settings.json") } : [settingsURL(.codex, home: home)]
    }

    /// The agent is installed (a config folder exists), so offering to hook it makes sense.
    static func isAvailable(_ provider: Provider, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        settingsURLs(provider, home: home).contains { FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
    }

    /// True only when every config folder has the hooks, so a newly added one (a second account) shows as missing.
    static func isInstalled(_ provider: Provider, approvals: Bool = false, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        settingsURLs(provider, home: home).allSatisfy { url in
            guard let data = try? Data(contentsOf: url) else { return false }
            let text = String(decoding: data, as: UTF8.self)
            // Claude Code's approvals come with the question hook; an older install without it counts as missing.
            guard approvals else { return text.contains("--agent-event") }
            return text.contains("--agent-approval") && (provider != .claude || text.contains("--agent-question"))
        }
    }

    /// Codex runs a hook only after the user trusted it with /hooks, which it records in config.toml under the
    /// handler's position ("…/hooks.json:permission_request:1:0"). False when Damla's approval handler is
    /// installed but has no trust entry yet; nil when it is not installed at all.
    static func codexApprovalTrusted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool? {
        let hooksFile = settingsURL(.codex, home: home)
        guard let data = try? Data(contentsOf: hooksFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = (root["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] else { return nil }
        for (g, group) in groups.enumerated() {
            for (h, handler) in (group["hooks"] as? [[String: Any]] ?? []).enumerated()
            where (handler["command"] as? String)?.contains("--agent-approval") == true {
                let config = home.appendingPathComponent(".codex/config.toml")
                let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
                return text.contains("\"\(hooksFile.path):permission_request:\(g):\(h)\"")
            }
        }
        return nil
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
            guard let dictionary = existing as? [String: Any] else { throw Failure(description: String(localized: "hooks alanı nesne olmalı; mevcut ayarlar değiştirilmedi")) }
            hooks = dictionary
        } else { hooks = [:] }
        func ours(_ handler: [String: Any]) -> Bool {
            let message = handler["statusMessage"] as? String, command = handler["command"] as? String ?? ""
            return (message == marker && command.contains("--agent-event")) || (message == approvalMarker && command.contains("--agent-approval"))
                || (message == questionMarker && command.contains("--agent-question"))
        }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { throw Failure(description: String(localized: "Beklenmeyen hook biçimi: \(event)")) }
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
        // Opt-in: answers the agent's permission prompts from the notch. A decision is only ever printed after
        // the user clicked one in Damla; otherwise the agent asks as usual.
        if approvals {
            let group: [String: Any] = ["hooks": [["type": "command", "command": command + " --agent-approval " + provider.rawValue,
                                                   "timeout": approvalTimeout, "statusMessage": approvalMarker]]]
            hooks["PermissionRequest"] = (hooks["PermissionRequest"] as? [[String: Any]] ?? []) + [group]
            // Claude Code's multiple-choice questions are answered from the notch through PreToolUse.
            if provider == .claude {
                let question: [String: Any] = ["matcher": "AskUserQuestion",
                                               "hooks": [["type": "command", "command": command + " --agent-question claude",
                                                          "timeout": approvalTimeout, "statusMessage": questionMarker]]]
                hooks["PreToolUse"] = (hooks["PreToolUse"] as? [[String: Any]] ?? []) + [question]
            }
        }
        data["hooks"] = hooks
        if provider == .claude { data["statusLine"] = statusLine(data["statusLine"], command: command) }
        return data
    }

    /// Claude Code's status line carries context and rate-limit use, which no hook sees. Damla's command records
    /// them and prints a short line; a status line the user already had keeps running after `--then`, with its
    /// own settings (padding, refreshInterval) left as they were.
    static func statusLine(_ existing: Any?, command: String) -> [String: Any] {
        var line = existing as? [String: Any] ?? [:]
        let current = line["command"] as? String ?? ""
        var original: String?
        if let range = current.range(of: " --agent-status claude") {
            // Ours already: keep whatever it wraps, point it at this binary.
            if let then = current.range(of: " --then ", range: range.upperBound..<current.endIndex) {
                original = shellUnquote(String(current[then.upperBound...]))
            }
        } else if !current.isEmpty, line["type"] as? String ?? "command" == "command" {
            original = current
        }
        line["type"] = "command"
        line["command"] = command + " --agent-status claude" + (original.map { " --then " + shellQuote($0) } ?? "")
        return line
    }

    /// Reverses `shellQuote` for the one argument Damla wrote itself.
    static func shellUnquote(_ value: String) -> String {
        guard value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "'\"'\"'", with: "'")
    }

    /// Writes the merged settings into every file the provider reads. Returns false when all were already up to date.
    @discardableResult
    static func install(_ provider: Provider, approvals: Bool, binary: String = Bundle.main.executablePath ?? "",
                        home: URL = FileManager.default.homeDirectoryForCurrentUser, now: Date = Date()) throws -> Bool {
        var changed = false
        for url in settingsURLs(provider, home: home) {
            if try install(provider, at: url, approvals: approvals, binary: binary, now: now) { changed = true }
        }
        return changed
    }

    private static func install(_ provider: Provider, at url: URL, approvals: Bool, binary: String, now: Date) throws -> Bool {
        let old = try? Data(contentsOf: url)
        var original: [String: Any] = [:]
        if let old, !old.isEmpty {
            guard let parsed = try JSONSerialization.jsonObject(with: old) as? [String: Any] else { throw Failure(description: String(localized: "\(url.path) bir JSON nesnesi değil")) }
            original = parsed
        }
        let updated = try merge(original, provider: provider, binary: binary, approvals: approvals)
        guard !NSDictionary(dictionary: updated).isEqual(to: original) else { return false }
        let new = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
        // Never overwrite an edit made while we were merging.
        guard (try? Data(contentsOf: url)) == old else { throw Failure(description: String(localized: "Ayarlar değişti; yeniden dene: \(url.path)")) }
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
