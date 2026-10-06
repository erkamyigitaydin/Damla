import Foundation

/// The same reconciliation used by AppState, with an explicit clock; no user preferences or files touched.
func runFocusSelfTests(_ check: (Bool, String) -> Void) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func timer(ending deadline: Date, phase: FocusSession.Phase = .focus) -> FocusSession {
        var value = FocusSession()
        value.reset(minutes: 25, phase: phase)
        value.start(at: deadline.addingTimeInterval(-25 * 60))
        return value
    }
    let morning = date(6, 10)
    var daily = FocusDailyCount.restored(from: nil, at: morning, calendar: calendar)
    check(daily.count == 0, "Focus daily: no dated record never imports the legacy lifetime total")
    var session = timer(ending: morning)
    check(daily.update(session: &session, at: morning, calendar: calendar) && daily.count == 1,
          "Focus daily: completion counts once on its local day")
    check(!daily.update(session: &session, at: morning.addingTimeInterval(1), calendar: calendar) && daily.count == 1,
          "Focus daily: duplicate tick or wake cannot count the same completion twice")
    session = timer(ending: date(6, 11))
    _ = daily.update(session: &session, at: date(6, 11), calendar: calendar)
    check(daily.count == 2, "Focus daily: separate completions on the same day accumulate")
    let saved = try? JSONEncoder().encode(daily)
    let savedSession = try? JSONEncoder().encode(session)
    daily = FocusDailyCount.restored(from: saved, at: date(6, 12), calendar: calendar)
    session = savedSession.flatMap { try? JSONDecoder().decode(FocusSession.self, from: $0) } ?? FocusSession()
    check(daily.count == 2 && !daily.update(session: &session, at: date(6, 12), calendar: calendar),
          "Focus daily: saved counter and finished timer survive relaunch without recounting")
    session = timer(ending: date(6, 13), phase: .rest)
    check(daily.update(session: &session, at: date(6, 13), calendar: calendar) && daily.count == 2,
          "Focus daily: breaks finish but do not increase focus count")
    _ = daily.update(session: &session, at: date(7), calendar: calendar)
    check(daily.count == 0, "Focus daily: midnight resets an idle counter without an active timer")
    let rolled = try? JSONEncoder().encode(daily)
    check(FocusDailyCount.restored(from: rolled, at: date(7, 9), calendar: calendar).count == 0,
          "Focus daily: reset persists across a same-day relaunch")
    check(FocusDailyCount.restored(from: saved, at: date(7, 9), calendar: calendar).count == 0,
          "Focus daily: relaunch on another day drops the old daily count")
    session = timer(ending: date(6, 23, 55))
    check(daily.update(session: &session, at: date(7, 8), calendar: calendar) && daily.count == 0 && !session.running,
          "Focus daily: wake finishes yesterday's timer without crediting today")
    session = timer(ending: date(7, 0, 10))
    check(daily.update(session: &session, at: date(7, 8), calendar: calendar) && daily.count == 1,
          "Focus daily: timer crossing midnight counts on its deadline day after wake")
    session = timer(ending: date(7, 10))
    session.pause(at: date(7, 9, 50))
    check(!daily.update(session: &session, at: date(7, 11), calendar: calendar) && daily.count == 1,
          "Focus daily: paused sessions never become completions during sleep")
    check(FocusDailyCount.restored(from: Data("broken".utf8), at: morning, calendar: calendar).count == 0,
          "Focus daily: malformed saved data safely starts a dated zero count")

    var dst = Calendar(identifier: .gregorian)
    dst.timeZone = TimeZone(identifier: "America/New_York")!
    let shortDay = dst.date(from: DateComponents(year: 2026, month: 3, day: 8))!
    let afterDST = dst.date(from: DateComponents(year: 2026, month: 3, day: 9))!
    var dstCount = FocusDailyCount(at: shortDay, calendar: dst)
    var dstSession = timer(ending: shortDay.addingTimeInterval(3600))
    _ = dstCount.update(session: &dstSession, at: shortDay.addingTimeInterval(3600), calendar: dst)
    dstCount.refresh(at: afterDST, calendar: dst)
    check(afterDST.timeIntervalSince(shortDay) == 23 * 3600 && dstCount.count == 0,
          "Focus daily: a 23-hour DST day resets at local midnight, not after 24 hours")

    check(FocusCycle.filled(completed: 0, phase: .focus) == 0 && FocusCycle.round(completed: 0) == 1
          && FocusCycle.filled(completed: 2, phase: .focus) == 2 && FocusCycle.round(completed: 2) == 3,
          "Focus cycle: dots and round follow today's completed rounds")
    check(FocusCycle.filled(completed: 4, phase: .rest) == 4 && FocusCycle.filled(completed: 4, phase: .focus) == 0
          && FocusCycle.round(completed: 4) == 1, "Focus cycle: all four stay lit through the long break, then a new cycle")
    check(FocusCycle.breakMinutes(completed: 3, short: 5) == 5 && FocusCycle.breakMinutes(completed: 4, short: 5) == 15
          && FocusCycle.breakMinutes(completed: 8, short: 20) == 20 && FocusCycle.breakMinutes(completed: 0, short: 5) == 5,
          "Focus cycle: every fourth round earns the long break, never shorter than the chosen one")
}
