import AppKit
import CoreAudio
import EventKit

/// The next meeting from the Mac's calendars: a countdown in the closed notch from ten minutes before, a line on
/// the home page for the next three hours, and one tap to join when the event carries a Zoom, Meet, Teams, Webex
/// or FaceTime link. Off until the user turns it on, since it asks for calendar access.
final class CalendarService: ObservableObject {
    struct Meeting: Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var joinURL: URL?
    }
    static let enabledKey = "calendarEnabled"
    static let soonBefore: TimeInterval = 10 * 60
    static let soonAfter: TimeInterval = 5 * 60
    static let homeWindow: TimeInterval = 3 * 3600
    /// The 24-hour search window must advance even when its last result was empty.
    static let refreshInterval: TimeInterval = 5 * 60

    @Published private(set) var next: Meeting?
    @Published private(set) var access: EKAuthorizationStatus
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            if enabled { requestAccess() } else { clear() }
        }
    }
    /// A minute before a meeting starts: title, join link.
    var onStarting: ((Meeting) -> Void)?

    private lazy var store = EKEventStore()
    private let defaults: UserDefaults
    private let now: () -> Date
    private let authorizationStatus: () -> EKAuthorizationStatus
    private let query: ((Date, Date) -> [Meeting])?
    private var lastRefresh: Date?
    private var timer: Timer?
    private var announced: String?
    private var observer: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// Injected sources let regressions use a local clock and meetings without touching EventKit data.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         authorizationStatus: @escaping () -> EKAuthorizationStatus = { EKEventStore.authorizationStatus(for: .event) },
         query: ((Date, Date) -> [Meeting])? = nil) {
        self.defaults = defaults
        self.now = now
        self.authorizationStatus = authorizationStatus
        self.query = query
        access = authorizationStatus()
        enabled = defaults.bool(forKey: Self.enabledKey)
    }

    func start() {
        guard timer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.refresh() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.didWake() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 5
        refresh()
    }

    deinit {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func requestAccess() {
        if authorizationStatus() == .fullAccess { refresh(); return }
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    func refresh() {
        access = authorizationStatus()
        guard enabled, access == .fullAccess else { clear(); return }
        let now = now()
        let meeting = Self.pick(meetings(from: now.addingTimeInterval(-Self.soonAfter), to: now.addingTimeInterval(24 * 3600)), now: now)
        lastRefresh = now
        if meeting != next { next = meeting }
        updateCountdown(at: now)
    }

    private func meetings(from start: Date, to end: Date) -> [Meeting] {
        if let query { return query(start, end) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).filter { !$0.isAllDay }.map { event in
            Meeting(id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)", title: event.title ?? String(localized: "Etkinlik"),
                    start: event.startDate, end: event.endDate,
                    joinURL: Self.joinURL(in: [event.url?.absoluteString, event.location, event.notes]))
        }
    }

    private func clear() {
        if next != nil { next = nil }
        lastRefresh = nil
    }

    /// Wake notifications bypass the periodic deadline; a short sleep can still cross an event boundary.
    func didWake() { refresh() }

    func tick() {
        let status = authorizationStatus()
        if access != status { access = status }
        guard enabled, access == .fullAccess else { clear(); return }
        let now = now()
        let refreshDue = lastRefresh.map { now < $0 || now.timeIntervalSince($0) >= Self.refreshInterval } ?? true
        if refreshDue
            || next.map({ now >= $0.start.addingTimeInterval(Self.soonAfter) || now >= $0.end }) == true {
            refresh()
            return
        }
        updateCountdown(at: now)
    }

    private func updateCountdown(at now: Date) {
        guard let meeting = next else { return }
        let left = meeting.start.timeIntervalSince(now)
        if left <= 60, left > -30, announced != meeting.id {
            announced = meeting.id
            onStarting?(meeting)
        }
        objectWillChange.send()   // the countdown text moves on
    }

    /// The first timed event that has not been running for more than five minutes. All-day events never count.
    static func pick(_ meetings: [Meeting], allDay: Set<String> = [], now: Date) -> Meeting? {
        meetings.filter { !allDay.contains($0.id) && $0.start > now.addingTimeInterval(-soonAfter) && $0.end > now }
            .min { $0.start < $1.start }
    }

    /// Debug: a fake meeting `minutes` from now, for screenshots.
    func injectDemo(title: String, minutes: Double, link: Bool) {
        next = Meeting(id: "demo", title: title, start: Date().addingTimeInterval(minutes * 60), end: Date().addingTimeInterval(minutes * 60 + 1800),
                       joinURL: link ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
    }

    func isSoon(_ meeting: Meeting, at now: Date = Date()) -> Bool {
        meeting.start.timeIntervalSince(now) <= Self.soonBefore && now < meeting.start.addingTimeInterval(Self.soonAfter)
    }
    var soon: Meeting? { next.flatMap { isSoon($0) ? $0 : nil } }
    var upcoming: Meeting? { next.flatMap { $0.start.timeIntervalSinceNow <= Self.homeWindow ? $0 : nil } }

    /// "5 dk", "şimdi", "14:30".
    static func countdown(_ meeting: Meeting, at now: Date = Date()) -> String {
        let minutes = Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return String(localized: "şimdi") }
        if minutes < 60 { return String(localized: "\(minutes) dk") }
        return meeting.start.formatted(date: .omitted, time: .shortened)
    }

    /// The first video-call link in the event's URL, location or notes.
    static func joinURL(in fields: [String?]) -> URL? {
        let pattern = #"https://(?:[\w-]+\.)?(?:zoom\.us/(?:j|my|w)/[^\s<>"]+|meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\s<>"]*|teams\.microsoft\.com/l/meetup-join/[^\s<>"]+|teams\.live\.com/meet/[^\s<>"]+|[\w-]+\.webex\.com/[^\s<>"]+|facetime\.apple\.com/join[^\s<>"]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for field in fields.compactMap({ $0 }) {
            let range = NSRange(field.startIndex..., in: field)
            if let match = regex.firstMatch(in: field, range: range), let r = Range(match.range, in: field) {
                return URL(string: String(field[r]))
            }
        }
        return nil
    }

    /// Joins the call when there is a link, otherwise shows the event in Calendar.
    func open(_ meeting: Meeting) {
        if let url = meeting.joinURL { NSWorkspace.shared.open(url); return }
        if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
    }
}

/// The default microphone: whether any app is using it (a call, a recording) and a mute switch that works for
/// every app at once. CoreAudio only; reading these needs no permission.
final class MicrophoneMonitor: ObservableObject {
    @Published private(set) var inUse = false
    @Published private(set) var muted = false
    private var device: AudioDeviceID = 0
    private var listener: AudioObjectPropertyListenerBlock?
    private var defaultListener: AudioObjectPropertyListenerBlock?

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func start() {
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }
        defaultListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, block)
        attach()
    }

    private func attach() {
        if device != 0, let listener {
            for selector in [kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioDevicePropertyMute] {
                var a = Self.address(selector, selector == kAudioDevicePropertyMute ? kAudioDevicePropertyScopeInput : kAudioObjectPropertyScopeGlobal)
                AudioObjectRemovePropertyListenerBlock(device, &a, .main, listener)
            }
        }
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else {
            device = 0; inUse = false; return
        }
        device = id
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read() }
        listener = block
        for selector in [kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioDevicePropertyMute] {
            var a = Self.address(selector, selector == kAudioDevicePropertyMute ? kAudioDevicePropertyScopeInput : kAudioObjectPropertyScopeGlobal)
            if AudioObjectHasProperty(id, &a) { AudioObjectAddPropertyListenerBlock(id, &a, .main, block) }
        }
        read()
    }

    private func read() {
        var running = UInt32(0), mute = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectGetPropertyData(device, &a, 0, nil, &size, &running)
        var m = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        size = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = AudioObjectHasProperty(device, &m) && AudioObjectGetPropertyData(device, &m, 0, nil, &size, &mute) == noErr
        if inUse != (running != 0) { inUse = running != 0 }
        let now = (hasMute && mute != 0) || savedLevels[device] != nil
        if muted != now { muted = now }
    }

    /// Input level before a volume-based mute, per device, so unmuting brings it back.
    private var savedLevels: [AudioDeviceID: [UInt32: Float32]] = [:]

    /// Mutes or unmutes the microphone for every app. Devices without a mute switch (often the built-in mic)
    /// are silenced by turning their input level to zero and restoring it afterwards.
    @discardableResult
    func toggleMute() -> Bool {
        guard device != 0 else { return false }
        var m = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(device, &m), AudioObjectIsPropertySettable(device, &m, &settable) == noErr, settable.boolValue {
            var value = UInt32(muted ? 0 : 1)
            let ok = AudioObjectSetPropertyData(device, &m, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
            read()
            return ok
        }
        let elements = volumeElements()
        guard !elements.isEmpty else { return false }
        let muting = savedLevels[device] == nil
        var saved: [UInt32: Float32] = [:]
        for element in elements {
            var v = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: element)
            var level = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(device, &v, 0, nil, &size, &level)
            saved[element] = level
            var target = muting ? Float32(0) : (savedLevels[device]?[element] ?? 0.75)
            AudioObjectSetPropertyData(device, &v, 0, nil, UInt32(MemoryLayout<Float32>.size), &target)
        }
        savedLevels[device] = muting ? saved : nil
        muted = muting
        return true
    }

    /// The input volume controls a device offers: the master one, or one per channel.
    private func volumeElements() -> [UInt32] {
        [kAudioObjectPropertyElementMain, 1, 2].filter { element in
            var v = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: element)
            var settable: DarwinBoolean = false
            return AudioObjectHasProperty(device, &v) && AudioObjectIsPropertySettable(device, &v, &settable) == noErr && settable.boolValue
        }
    }
}
