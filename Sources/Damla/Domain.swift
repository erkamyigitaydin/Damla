import Foundation

struct FocusSession: Codable {
    enum Phase: String, Codable { case focus, rest }
    var phase: Phase = .focus
    var duration: TimeInterval = 25 * 60
    var deadline: Date?
    var pausedRemaining: TimeInterval = 25 * 60
    var hasStarted = false

    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, deadline.map { $0.timeIntervalSince(now) } ?? pausedRemaining)
    }
    var running: Bool { deadline != nil }
    func progress(at now: Date = Date()) -> Double {
        min(1, max(0, 1 - remaining(at: now) / max(1, duration)))
    }
    mutating func start(at now: Date = Date()) {
        guard deadline == nil else { return }
        if pausedRemaining <= 0 { pausedRemaining = duration }
        deadline = now.addingTimeInterval(pausedRemaining)
        hasStarted = true
    }
    mutating func pause(at now: Date = Date()) {
        pausedRemaining = remaining(at: now)
        deadline = nil
    }
    mutating func reset(minutes: Int, phase: Phase = .focus) {
        self.phase = phase
        duration = TimeInterval(minutes * 60)
        pausedRemaining = duration
        deadline = nil
        hasStarted = false
    }
    mutating func finishIfNeeded(at now: Date = Date()) -> Bool {
        guard let deadline, deadline <= now else { return false }
        self.deadline = nil
        pausedRemaining = 0
        return true
    }
}

/// Today's rounds in cycles of four, the classic pomodoro: a long break after every fourth focus round.
enum FocusCycle {
    static let length = 4
    static let longBreakMinutes = 15
    /// Focus/break pairs offered next to the dial; any other focus length comes from turning the dial.
    static let presets = [(25, 5), (45, 10), (50, 10)]

    /// Dots lit in the current cycle. During the break after the fourth round all four stay lit.
    static func filled(completed: Int, phase: FocusSession.Phase) -> Int {
        let inCycle = completed % length
        return phase == .rest && completed > 0 && inCycle == 0 ? length : inCycle
    }
    /// The round being worked on, or the one up next during a break: 1 to 4.
    static func round(completed: Int) -> Int { completed % length + 1 }
    /// The break that follows a finished focus round: the long one after every fourth.
    static func breakMinutes(completed: Int, short: Int) -> Int {
        completed > 0 && completed % length == 0 ? max(longBreakMinutes, short) : short
    }
}

/// Today's completed focus sessions, dated separately from the running timer. An old, undated lifetime
/// total cannot tell us how many sessions happened today, so it is deliberately not imported.
struct FocusDailyCount: Codable, Equatable {
    static let defaultsKey = "focusDailyCount"
    private(set) var day: Date
    private(set) var count = 0

    init(at now: Date, calendar: Calendar = .autoupdatingCurrent) {
        day = calendar.startOfDay(for: now)
    }

    static func restored(from data: Data?, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> FocusDailyCount {
        guard let data, var saved = try? JSONDecoder().decode(Self.self, from: data), saved.count >= 0 else {
            return Self(at: now, calendar: calendar)
        }
        saved.refresh(at: now, calendar: calendar)
        return saved
    }

    mutating func refresh(at now: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard !calendar.isDate(day, inSameDayAs: now) else { return }
        day = calendar.startOfDay(for: now)
        count = 0
    }

    /// Reconciles a timer after a tick, relaunch or wake. Attribute an overdue session to its actual
    /// deadline: waking today must not count yesterday's completed timer as today's work.
    @discardableResult
    mutating func update(session: inout FocusSession, at now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        refresh(at: now, calendar: calendar)
        let deadline = session.deadline
        guard session.finishIfNeeded(at: now) else { return false }
        if session.phase == .focus, let deadline, calendar.isDate(deadline, inSameDayAs: now) {
            count += 1
        }
        return true
    }
}

struct ShelfItem: Identifiable, Codable {
    var id: UUID = UUID()
    var path: String
    var bookmark: Data?
    var added = Date()
    var url: URL {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) { return resolved }
        }
        return URL(fileURLWithPath: path)
    }
    init(url: URL) {
        path = url.standardizedFileURL.path
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

struct ClipEntry: Identifiable, Codable {
    enum Kind: String, Codable { case text, image, file }
    var id = UUID()
    var kind: Kind
    /// The text; for `.file` the copied files' paths, one per line.
    var text: String?
    var imageData: Data?
    var date = Date()   // when it was (last) copied
    var pinned = false
    /// The app that was in front when it was copied. Optional, so clips saved before it existed still load.
    var sourceBundleID: String?
    var byteSize: Int { (text?.utf8.count ?? 0) + (imageData?.count ?? 0) }
    var fileURLs: [URL] {
        kind == .file ? (text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) } : []
    }
    var title: String {
        switch kind {
        case .image: return String(localized: "Kopyalanan görsel")
        case .file: return fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        case .text: return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    /// A single web address, nothing around it.
    var isLink: Bool {
        guard kind == .text, let t = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(where: \.isWhitespace)
    }
    /// A hex colour code (#153AA4, #fff): the card shows the colour itself.
    var isColor: Bool {
        guard kind == .text, let t = text?.trimmingCharacters(in: .whitespaces), t.hasPrefix("#"), t.count == 7 || t.count == 4 else { return false }
        return t.dropFirst().allSatisfy(\.isHexDigit)
    }
    /// The chip it falls under. A colour code is copied and pasted as text, so it counts as text.
    var category: ClipFilter { kind == .image ? .image : kind == .file ? .file : isLink ? .link : .text }
}

/// The Pano page's filter chips.
enum ClipFilter: CaseIterable {
    case all, text, link, image, file
    var title: String {
        switch self {
        case .all: return String(localized: "Tümü")
        case .text: return String(localized: "Metin")
        case .link: return String(localized: "Bağlantı")
        case .image: return String(localized: "Görsel")
        case .file: return String(localized: "Dosya")
        }
    }
    func matches(_ entry: ClipEntry) -> Bool { self == .all || entry.category == self }
}

enum ClipRules {
    /// How long ago, in the few characters a card has: şimdi, 5 dk, 2 sa, dün, 3 g. Past a day it counts calendar
    /// days, so "dün" means yesterday rather than 24–48 hours.
    static func age(since date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return String(localized: "şimdi") }
        if seconds < 3600 { return String(localized: "\(Int(seconds / 60)) dk") }
        if seconds < 86_400 { return String(localized: "\(Int(seconds / 3600)) sa") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        return days <= 1 ? String(localized: "dün") : String(localized: "\(days) g")
    }
    static let excludedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword",
        "com.typeit4me.clipping", "de.petermaurer.TransientPasteboardType"
    ]
    static func shouldCapture(types: Set<String>) -> Bool { types.isDisjoint(with: excludedTypes) }
    static func trimmed(_ entries: [ClipEntry]) -> [ClipEntry] {
        var bytes = 0
        return entries.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.date > $1.date
        }.prefix(60).filter { item in
            bytes += item.byteSize
            return bytes <= 24 * 1024 * 1024
        }
    }
}

enum DiskStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Damla", isDirectory: true)
        // `--debug` runs can keep their data elsewhere (README screenshots with demo agents, shelf and clips).
        if ProcessInfo.processInfo.arguments.contains("--debug"), let custom = ProcessInfo.processInfo.environment["DAMLA_SUPPORT_DIR"] {
            url = URL(fileURLWithPath: custom, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }
    static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { NSLog("Damla: local save failed: %@", error.localizedDescription) }
    }
}
