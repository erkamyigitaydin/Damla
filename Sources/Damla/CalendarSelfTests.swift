import EventKit
import Foundation

/// Exercises the service's timer/wake paths with fake meetings, authorization and time; no EventKit data is read.
func runCalendarSelfTests(_ check: (Bool, String) -> Void) {
    let suite = "Damla-calendar-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: CalendarService.enabledKey)

    let origin = Date(timeIntervalSince1970: 1_800_000_000)
    var now = origin
    var authorization: EKAuthorizationStatus = .fullAccess
    var queries: [(Date, Date)] = []
    // Already in the calendar, but outside the first 24-hour query. No change notification will arrive.
    var events = [CalendarService.Meeting(id: "tomorrow", title: "Tomorrow", start: origin.addingTimeInterval(24 * 3600 + 150),
                                         end: origin.addingTimeInterval(24 * 3600 + 1950), joinURL: nil)]
    let service = CalendarService(defaults: defaults, now: { now }, authorizationStatus: { authorization }, query: { start, end in
        queries.append((start, end))
        return events.filter { $0.start < end && $0.end > start }
    })

    service.refresh()
    check(service.next == nil && queries.count == 1, "Calendar: a meeting beyond the initial 24-hour window leaves an empty result")
    check(queries.first?.0 == origin.addingTimeInterval(-CalendarService.soonAfter)
          && queries.first?.1 == origin.addingTimeInterval(24 * 3600), "Calendar: query keeps the existing five-minute lookback and 24-hour horizon")
    for seconds in stride(from: 30, through: 270, by: 30) {
        now = origin.addingTimeInterval(Double(seconds))
        service.tick()
    }
    check(queries.count == 1, "Calendar: empty results do not query on every 30-second countdown tick")
    now = origin.addingTimeInterval(300)
    service.tick()
    check(queries.count == 2 && service.next?.id == "tomorrow", "Calendar: an empty result recovers when an existing event enters the moving window")
    now = origin.addingTimeInterval(330)
    service.tick()
    check(queries.count == 2, "Calendar: a populated result shares the low-frequency refresh deadline")

    authorization = .denied
    service.tick()
    now = origin.addingTimeInterval(1000)
    service.tick()
    service.didWake()
    service.refresh()
    check(queries.count == 2 && service.next == nil && service.access == .denied,
          "Calendar: revoked access clears stale events and blocks timer, wake and change-triggered queries")
    authorization = .writeOnly
    service.tick()
    service.didWake()
    check(queries.count == 2 && service.next == nil, "Calendar: write-only permission never allows event reads")
    authorization = .fullAccess
    service.tick()
    check(queries.count == 3 && service.next?.id == "tomorrow", "Calendar: restored read access refreshes on the next tick")

    service.enabled = false
    service.tick()
    service.refresh()
    service.didWake()
    check(queries.count == 3 && service.next == nil && !defaults.bool(forKey: CalendarService.enabledKey),
          "Calendar: disabling persists and blocks timer, wake and change-triggered queries")
    service.enabled = true // The injected authorization is already full; this must never request real permission.
    check(queries.count == 4 && service.next?.id == "tomorrow", "Calendar: re-enabling with existing permission immediately refreshes")

    now = origin.addingTimeInterval(1010)
    events = [CalendarService.Meeting(id: "after-wake", title: "After wake", start: now.addingTimeInterval(60),
                                    end: now.addingTimeInterval(120), joinURL: nil)]
    var announcements: [String] = []
    service.onStarting = { announcements.append($0.id) }
    service.didWake()
    check(queries.count == 5 && service.next?.id == "after-wake", "Calendar: wake refreshes immediately even before the five-minute deadline")
    now = now.addingTimeInterval(30)
    service.tick()
    check(queries.count == 5 && announcements == ["after-wake"], "Calendar: countdown ticks announce once without repeatedly querying")
    now = origin.addingTimeInterval(1130)
    service.tick()
    check(queries.count == 6 && service.next == nil, "Calendar: an ended short meeting is removed before the periodic deadline")

    now = origin.addingTimeInterval(1100)
    service.tick()
    check(queries.count == 7, "Calendar: a backwards wall-clock adjustment does not postpone refresh indefinitely")
    events = []
    now = origin.addingTimeInterval(1130)
    service.didWake()
    check(queries.count == 8 && service.next == nil && announcements == ["after-wake"],
          "Calendar: waking after a meeting clears it without repeating its announcement")

    authorization = .notDetermined
    service.tick()
    service.didWake()
    check(queries.count == 8 && service.access == .notDetermined, "Calendar: background refresh neither reads nor asks for undetermined permission")
}
