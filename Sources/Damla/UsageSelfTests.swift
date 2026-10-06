import Foundation

/// Checks for the plan-limit cards: reading Codex's rollouts (in a throwaway tree) and the pace arithmetic.
func runUsageSelfTests(_ check: (Bool, String) -> Void) {
    let now = Date()
    func line(_ limits: [String: Any]) -> String {
        let event: [String: Any] = ["timestamp": "2026-10-06T10:54:55.916Z", "type": "event_msg",
                                    "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": 1]], "rate_limits": limits]]
        return String(data: try! JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
    }
    let reset = now.timeIntervalSince1970 + 3 * 24 * 3600
    let weekly: [String: Any] = ["limit_id": "codex", "limit_name": NSNull(), "plan_type": "prolite", "secondary": NSNull(),
                                 "primary": ["used_percent": 89.0, "window_minutes": 10080, "resets_at": reset]]
    let spark: [String: Any] = ["limit_id": "codex_bengalfox", "limit_name": "GPT-5.3-Codex-Spark", "plan_type": "prolite",
                                "primary": ["used_percent": 3.0, "window_minutes": 300, "resets_at": reset],
                                "secondary": ["used_percent": 1.0, "window_minutes": 10080, "resets_at": reset]]
    let empty: [String: Any] = ["limit_id": "codex", "primary": NSNull(), "secondary": NSNull()]
    let tail = "ut_tokens\":4}}}\n" + [line(weekly), line(spark), line(empty), #"{"type":"response_item"}"#].joined(separator: "\n") + "\n"
    let updated = Date(timeIntervalSince1970: 1_791_000_000)
    let parsed = CodexUsage.parse(tail: Data(tail.utf8), updated: updated)
    check(parsed?.sevenDay?.percent == 89 && parsed?.fiveHour == nil && parsed?.updated == updated,
          "Codex: the last plan-wide limits win; a cut first line, one model's limits and empty slots are skipped")
    check(parsed?.plan == "prolite" && parsed?.planTitle == "Pro Lite", "Codex: plan type becomes the badge")
    let both: [String: Any] = ["primary": ["used_percent": 34.0, "window_minutes": 300, "resets_at": reset],
                               "secondary": ["used_percent": 43.0, "window_minutes": 10080, "resets_at": reset]]
    let older = CodexUsage.parse(tail: Data(line(both).utf8), updated: updated)
    check(older?.fiveHour?.percent == 34 && older?.sevenDay?.percent == 43 && older?.planTitle == nil,
          "Codex: window length decides five hours or week; an older line without limit_id still counts")
    check(CodexUsage.parse(tail: Data(#"{"type":"event_msg","payload":{"type":"token_count","rate_limits":null}}"#.utf8), updated: updated) == nil,
          "Codex: no limits, no card")

    // A rollout tree: the newest written file wins, even from yesterday's folder; one without limits falls back.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Damla-usage-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    func write(_ path: String, _ text: String, modified: Date) {
        let url = root.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
    check(CodexUsage.read(root: root) == nil, "Codex: no sessions folder, no card")
    var limits = weekly
    limits["primary"] = ["used_percent": 12.0, "window_minutes": 10080, "resets_at": reset]
    write("2025/12/31/rollout-old.jsonl", line(both), modified: now.addingTimeInterval(-90 * 24 * 3600))
    write("2026/9/30/rollout-a.jsonl", line(limits), modified: now.addingTimeInterval(-60))
    write("2026/10/01/rollout-b.jsonl", line(both), modified: now.addingTimeInterval(-600))
    write("2026/10/01/notes.jsonl", line(spark), modified: now)
    let latest = CodexUsage.read(root: root)
    check(latest?.sevenDay?.percent == 12 && abs((latest?.updated ?? .distantPast).timeIntervalSince(now.addingTimeInterval(-60))) < 1,
          "Codex: the most recently written rollout of the last days is read, dated by the file")
    write("2026/10/02/rollout-c.jsonl", #"{"type":"session_meta"}"# + "\n", modified: now)
    check(CodexUsage.read(root: root)?.sevenDay?.percent == 12, "Codex: a fresh rollout without limits yet falls back to the previous one")
    check(CodexUsage.recentRollouts(in: root).map(\.url.lastPathComponent) == ["rollout-c.jsonl", "rollout-a.jsonl", "rollout-b.jsonl"],
          "Codex: only the newest day folders are listed")
    write("2026/10/03/rollout-big.jsonl", String(repeating: #"{"type":"response_item","payload":"xxxxxxxxxxxxxxxxxxxx"}"# + "\n", count: 12_000) + line(both) + "\n", modified: now)
    let big = root.appendingPathComponent("2026/10/03/rollout-big.jsonl")
    check((CodexUsage.tail(of: big)?.count ?? 0) == 256 * 1024 && CodexUsage.read(root: root)?.fiveHour?.percent == 34,
          "Codex: only the file's last 256 KB is read")

    // Pace: where even use would stand, and where the current one leads.
    let length = AgentUsage.fiveHourLength
    func window(_ percent: Double, elapsed: Double) -> AgentUsage.Window {
        AgentUsage.Window(percent: percent, resetsAt: now.addingTimeInterval((1 - elapsed) * length))
    }
    check(abs(window(30, elapsed: 0.4).elapsed(length: length, at: now) - 0.4) < 0.001
          && window(30, elapsed: 0).elapsed(length: length, at: now.addingTimeInterval(-60)) == 0, "Pace tick sits at the elapsed part of the window")
    check(window(5, elapsed: 0.05).outlook(length: length, at: now) == .resets && window(100, elapsed: 0.5).outlook(length: length, at: now) == .resets,
          "Early in a window, or once it is full, the line tells the reset time")
    check(window(20, elapsed: 0.5).outlook(length: length, at: now) == .leaves(60), "Slow use: what will be left at the reset")
    if case .fills(let date) = window(50, elapsed: 0.25).outlook(length: length, at: now) {
        check(abs(date.timeIntervalSince(now) - 0.25 * length) < 1, "Fast use: when the window runs out")
    } else { check(false, "Fast use: when the window runs out") }
    check(AgentText.outlook(window(20, elapsed: 0.5), length: length, at: now) == "sıfırlanınca ~%60 kalır"
          && AgentText.outlook(window(50, elapsed: 0.25), length: length, at: now).hasPrefix("bu hızla ")
          && AgentText.outlook(window(5, elapsed: 0.05), length: length, at: now).hasSuffix(" sıfırlanır"), "Usage line texts")
    check(["14:30", "14:00", "13:40", "10:20", "09:45", "00:00", "Cum 16:00", "12:00", "19:59"].map(AgentText.locative)
          == ["da", "te", "ta", "de", "te", "da", "da", "de", "da"], "Clock times take the suffix they are read with")
    let afternoon = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: now)!
    let other = afternoon.addingTimeInterval(2 * 24 * 3600)
    let today = AgentText.at(afternoon, now: now), later = AgentText.at(other, now: now)
    check(today.hasSuffix("’da") && !today.contains(afternoon.formatted(.dateTime.weekday(.abbreviated)))
          && later.hasSuffix("’da") && later.contains(other.formatted(.dateTime.weekday(.abbreviated))),
          "A time today is just the clock; another day adds the weekday")
    check(AgentText.ago(12 * 60) == "12 dk önce" && AgentText.ago(3 * 3600 + 60) == "3 sa önce" && AgentText.ago(3 * 24 * 3600) == "3 gün önce",
          "Old usage tells its age")
}
