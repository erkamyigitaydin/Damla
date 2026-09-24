import AppKit
import Combine

enum MusicSource: String, CaseIterable, Identifiable {
    case music = "Apple Music", spotify = "Spotify"
    var id: String { rawValue }
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    /// Players Damla can read and drive over Apple Events even when they are not the system's Now Playing app.
    static func scriptable(_ bundleID: String) -> Bool { allCases.contains { $0.bundleID == bundleID } }
}

/// One app's media, as last seen. The system Now Playing bridge only reports the frontmost player, so the
/// others are kept here: Music and Spotify stay live over Apple Events, browsers keep their last known state.
struct MediaSession: Identifiable {
    let bundleID: String
    var id: String { bundleID }
    var title = ""
    var artist = ""
    var playing = false
    var duration = 0.0
    var position = 0.0
    var positionDate = Date()
    var artwork: NSImage?
    var artworkKey = ""
    var accent: NSColor?
    var lastSeen = Date()
    var scriptable: Bool { MusicSource.scriptable(bundleID) }
}

final class MediaService: ObservableObject {
    @Published var source: MusicSource = MusicSource(rawValue: UserDefaults.standard.string(forKey: "musicSource") ?? "") ?? .music
    @Published var connected = UserDefaults.standard.bool(forKey: "musicConnected")
    @Published var title = "Müziğine yer aç"
    @Published var artist = "Apple Music veya Spotify’ı bağla."
    @Published var playing = false
    @Published var duration: Double = 0
    @Published var position: Double = 0
    @Published var positionDate = Date()
    @Published var artwork: NSImage?
    @Published var accent: NSColor?
    @Published var status: String?
    @Published var hasTrack = false
    /// True when the system Now Playing bridge is running: every player (browsers included) is covered
    /// and the manual source picker is unnecessary.
    @Published var bridgeActive = false
    @Published var sourceBundleID: String?
    /// Every player seen since launch, in first-seen order; the shown one is `sourceBundleID`.
    @Published private(set) var sessions: [MediaSession] = []
    /// False when the shown session is a background browser tab the bridge no longer reports: no transport.
    @Published private(set) var controllable = true
    /// Pause Music/Spotify when a video (or any other player) starts, resume when it stops.
    @Published var handoffEnabled = UserDefaults.standard.object(forKey: "mediaHandoff") as? Bool ?? true {
        didSet { UserDefaults.standard.set(handoffEnabled, forKey: "mediaHandoff"); if !handoffEnabled { handoffPaused.removeAll(); interrupter = nil } }
    }
    var onNotice: ((String) -> Void)?
    let bridge = NowPlayingBridge()
    private var activeBundleID: String?      // the app the bridge currently reports
    private var pinnedBundleID: String?      // chosen by hand; cleared when another player takes over
    private var followedBundleID: String?    // the last player that started playing; stays shown while paused
    private var goneWork: DispatchWorkItem?  // confirms an empty bridge report before acting on it
    private var bridgeArtworkKey = ""
    private var pollTimer: Timer?
    private var lastPoll = Date.distantPast
    private var polling: Set<String> = []
    private var scriptDenied: Set<String> = []
    private var deniedNoticeShown = false
    // Handoff: the player that interrupted the music, whether it is playing, and what Damla paused for it.
    private var interrupter: String?
    private var interrupterPlaying = false
    private var handoffPaused: Set<String> = []
    private var resumeWork: DispatchWorkItem?
    private var timer: Timer?
    private var busy = false
    private let queue = DispatchQueue(label: "app.damla.media", qos: .utility)
    private var lastArtworkKey = ""
    private var generation = 0
    private var lastRefresh = Date.distantPast
    /// Set while the panel is open: refresh every second. Otherwise 2 s while playing, 6 s when idle.
    var wantsFrequentUpdates = false

    func start() {
        if NowPlayingBridge.isBundled {
            bridge.test { [weak self] ok in
                guard let self else { return }
                if ok { self.startBridge() } else { self.startLegacy() }
            }
        } else {
            startLegacy()
        }
    }
    private func startLegacy() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let age = Date().timeIntervalSince(self.lastRefresh)
            if self.wantsFrequentUpdates || (self.playing && age >= 2) || age >= 6 { self.refresh() }
        }
    }
    private func startBridge() {
        bridgeActive = true; connected = true; status = nil
        title = "Müzik"; artist = "Bir şey çal: Müzik, Spotify, Safari…"
        bridge.onUpdate = { [weak self] item, image in self?.bridgeUpdate(item, image) }
        bridge.start()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let age = Date().timeIntervalSince(self.lastPoll)
            if age >= (self.wantsFrequentUpdates ? 2 : 5) { self.pollBackground() }
        }
    }

    // MARK: Sessions

    private func bridgeUpdate(_ item: NowPlayingBridge.Item?, _ image: NSImage?) {
        let previous = activeBundleID
        guard let item else {
            Self.trace("bridge nil prev=\(previous ?? "-")")
            activeBundleID = nil; bridgeArtworkKey = ""
            // macOS sends an empty report between two players too; only a lasting one means the player is gone.
            // Then a browser tab goes (Music/Spotify stay, the poll keeps them honest) and a handoff may resume.
            goneWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.activeBundleID == nil else { return }
                if let previous, !MusicSource.scriptable(previous) { self.sessions.removeAll { $0.bundleID == previous } }
                self.handoff(active: nil)
                self.applyDisplay()
            }
            goneWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
            return
        }
        goneWork?.cancel(); goneWork = nil
        let id = item.bundleID
        Self.trace("bridge \(id) playing=\(item.playing) prev=\(previous ?? "-")")
        activeBundleID = id
        // Pausing never moves the view away; a player takes it only by starting: going from stopped to playing,
        // or cutting in while the shown one plays. About a minute after the shown player pauses, macOS hands Now
        // Playing back to a player that never stopped (a video left running); that is not a start, and neither
        // are that player's routine updates afterwards, so the paused one stays on screen.
        let followed = followedBundleID.flatMap { f in sessions.first { $0.bundleID == f } }
        let wasPlaying = sessions.first { $0.bundleID == id }?.playing == true
        let followedPlaying = followed.map { $0.playing && isLive($0) } ?? false
        if item.playing && id != followedBundleID {
            if followed == nil || !wasPlaying || followedPlaying {
                followedBundleID = id; pinnedBundleID = nil
            } else if id != previous {
                Self.trace("fallback to \(id); keep showing \(followedBundleID ?? "-")")
            }
        }
        var session = sessions.first { $0.bundleID == id } ?? MediaSession(bundleID: id)
        session.title = item.title
        // Browsers often send no artist; fall back to the album, then to the player's name (Safari, Chrome…).
        session.artist = !item.artist.isEmpty ? item.artist : !item.album.isEmpty ? item.album : Self.appName(for: id)
        session.playing = item.playing
        session.duration = item.duration.isFinite ? max(0, item.duration) : 0
        session.position = max(0, item.elapsed); session.positionDate = item.timestamp
        session.lastSeen = Date()
        if let image {
            session.artwork = image; session.artworkKey = item.artworkKey; session.accent = nil
            computeAccent(for: id, image: image)
        } else if item.artworkKey.isEmpty {
            session.artwork = nil; session.artworkKey = ""; session.accent = nil
        } else if item.artworkKey != session.artworkKey, bridgeArtworkKey == item.artworkKey {
            // Same artwork payload as before, now credited to this app (the bridge only sends images on change).
            session.artworkKey = item.artworkKey
        }
        bridgeArtworkKey = item.artworkKey
        upsert(session)
        handoff(active: item)
        applyDisplay()
    }

    private func upsert(_ session: MediaSession) {
        if let index = sessions.firstIndex(where: { $0.bundleID == session.bundleID }) { sessions[index] = session }
        else { sessions.append(session) }
    }

    private func computeAccent(for id: String, image: NSImage) {
        queue.async {
            let accent = Palette.accent(for: image)
            DispatchQueue.main.async {
                guard let index = self.sessions.firstIndex(where: { $0.bundleID == id }), self.sessions[index].artwork === image else { return }
                self.sessions[index].accent = accent
                self.applyDisplay()
            }
        }
    }

    /// Live means Damla can still see and drive it: the bridge reports it, or Apple Events reach it.
    func isLive(_ session: MediaSession) -> Bool {
        session.bundleID == activeBundleID || (session.scriptable && !scriptDenied.contains(session.bundleID) && Self.isRunning(session.bundleID))
    }

    /// The pinned session, else the last one that started playing, else something playing (the bridge's app
    /// first), else the bridge's app, else the latest.
    private var displayedSession: MediaSession? {
        if let pinned = pinnedBundleID, let session = sessions.first(where: { $0.bundleID == pinned }) { return session }
        if let followed = followedBundleID, let session = sessions.first(where: { $0.bundleID == followed }) { return session }
        let playing = sessions.filter { $0.playing && isLive($0) }
        return playing.first { $0.bundleID == activeBundleID } ?? playing.first
            ?? sessions.first { $0.bundleID == activeBundleID } ?? sessions.max { $0.lastSeen < $1.lastSeen }
    }

    /// Another session that is playing right now besides the shown one (for the closed notch's badge).
    var otherPlaying: MediaSession? {
        sessions.first { $0.bundleID != sourceBundleID && $0.playing && isLive($0) }
    }

    func select(_ bundleID: String) {
        pinnedBundleID = bundleID
        applyDisplay()
        if let session = sessions.first(where: { $0.bundleID == bundleID }), session.scriptable, session.bundleID != activeBundleID { poll(bundleID) }
    }

    /// Copies the shown session into the flat properties the views read.
    private func applyDisplay() {
        guard let session = displayedSession else {
            hasTrack = false; playing = false; artwork = nil; accent = nil; sourceBundleID = nil; controllable = true
            title = "Müzik"; artist = "Bir şey çal: Müzik, Spotify, Safari…"
            return
        }
        let live = isLive(session)
        hasTrack = true
        title = session.title; artist = session.artist
        playing = session.playing && live
        duration = session.duration
        position = session.position; positionDate = session.positionDate
        if artwork !== session.artwork { artwork = session.artwork }
        if accent != session.accent { accent = session.accent }
        if sourceBundleID != session.bundleID { sourceBundleID = session.bundleID }
        if controllable != live { controllable = live }
    }

    /// Debug builds only: two fake players (a paused Music track behind a playing Chrome tab) for screenshots.
    func injectDemoSessions() {
        func art(_ color: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in color.setFill(); rect.fill(); return true }
        }
        sessions = [
            MediaSession(bundleID: MusicSource.music.bundleID, title: "Sakin Akşam", artist: "Demo Sanatçı", playing: false,
                         duration: 214, position: 81, artwork: art(.systemPink), artworkKey: "demo-1", accent: .systemPink),
            MediaSession(bundleID: "com.google.Chrome", title: "Voleybol · canlı yayın", artist: "Google Chrome", playing: true,
                         duration: 0, position: 0, artwork: art(.systemTeal), artworkKey: "demo-2", accent: .systemTeal)
        ]
        activeBundleID = "com.google.Chrome"; pinnedBundleID = nil
        applyDisplay()
    }

    /// `--debug` runs append media decisions to /tmp/damla-media.log.
    static let tracing = ProcessInfo.processInfo.arguments.contains("--debug")
    static func trace(_ line: String) {
        guard tracing else { return }
        let text = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(line)\n"
        if let handle = FileHandle(forWritingAtPath: "/tmp/damla-media.log") { handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close() }
        else { try? Data(text.utf8).write(to: URL(fileURLWithPath: "/tmp/damla-media.log")) }
    }
    /// Debug builds only: runs an Apple Events snippet against Music (as Damla, with Damla's permissions).
    func debugMusic(_ body: String) {
        queue.async { let (value, error) = Self.run(body, bundleID: MusicSource.music.bundleID); Self.trace("debug-music \(body) -> \(value?.stringValue ?? "nil") error=\(error.map(String.init) ?? "nil")") }
    }

    // MARK: Background players (Apple Events)

    private func pollBackground() {
        lastPoll = Date()
        let targets = Set(sessions.filter { $0.scriptable && $0.bundleID != activeBundleID }.map(\.bundleID)).union(handoffPaused)
        for id in targets where id != activeBundleID { poll(id) }
        // Background browser tabs cannot be read; forget them when their app quits or after a quiet while.
        let before = sessions.count
        sessions.removeAll { session in
            guard !session.scriptable, session.bundleID != activeBundleID else { return false }
            return !Self.isRunning(session.bundleID) || Date().timeIntervalSince(session.lastSeen) > 15 * 60
        }
        if sessions.count != before { applyDisplay() }
    }

    private func poll(_ id: String) {
        guard !polling.contains(id), !scriptDenied.contains(id) else { return }
        guard Self.isRunning(id) else {
            handoffPaused.remove(id)
            if id != activeBundleID, sessions.contains(where: { $0.bundleID == id }) { sessions.removeAll { $0.bundleID == id }; applyDisplay() }
            return
        }
        polling.insert(id)
        let read = "return {name of current track, artist of current track, duration of current track, player position, player state as string}"
        queue.async {
            let (value, error) = Self.run(read, bundleID: id)
            let name = value?.atIndex(1)?.stringValue ?? ""
            let artist = value?.atIndex(2)?.stringValue ?? ""
            let duration = (value?.atIndex(3)?.doubleValue ?? 0) / (id == MusicSource.spotify.bundleID ? 1000 : 1)
            let position = value?.atIndex(4)?.doubleValue ?? 0
            let playing = value?.atIndex(5)?.stringValue == "playing"
            DispatchQueue.main.async {
                self.polling.remove(id)
                guard id != self.activeBundleID else { return }   // the bridge took it over meanwhile
                Self.trace("poll \(id) error=\(error.map(String.init) ?? "nil") name=\(name) playing=\(playing)")
                if error == -1743 { self.automationDenied(id); return }
                guard error == nil, !name.isEmpty else {
                    // Running with nothing queued: nothing to show.
                    if !self.handoffPaused.contains(id) { self.sessions.removeAll { $0.bundleID == id }; self.applyDisplay() }
                    return
                }
                var session = self.sessions.first { $0.bundleID == id } ?? MediaSession(bundleID: id)
                let key = "\(name)|\(artist)"
                let trackChanged = session.title != name || session.artist != artist || session.artwork == nil
                session.title = name; session.artist = artist.isEmpty ? Self.appName(for: id) : artist
                session.duration = max(0, duration); session.position = max(0, position); session.positionDate = Date()
                session.playing = playing; session.lastSeen = Date()
                if trackChanged && session.artworkKey != "script:" + key {
                    session.artworkKey = "script:" + key
                    self.fetchArtwork(bundleID: id) { image in
                        guard let image, let index = self.sessions.firstIndex(where: { $0.bundleID == id }),
                              self.sessions[index].artworkKey == "script:" + key else { return }
                        self.sessions[index].artwork = image
                        self.computeAccent(for: id, image: image)
                        self.applyDisplay()
                    }
                }
                self.upsert(session)
                self.applyDisplay()
            }
        }
    }

    private func automationDenied(_ id: String) {
        scriptDenied.insert(id); handoffPaused.remove(id)
        applyDisplay()
        guard !deniedNoticeShown else { return }
        deniedNoticeShown = true
        onNotice?("\(Self.appName(for: id)) için otomasyon izni kapalı · Sistem Ayarları → Gizlilik → Otomasyon")
    }

    // MARK: Handoff

    /// A non-music player starting pauses Music/Spotify; when it stops for a moment, the music comes back.
    private func handoff(active item: NowPlayingBridge.Item?) {
        guard handoffEnabled else { return }
        guard let item else {
            if interrupter != nil { interrupterPlaying = false; scheduleResume() }
            return
        }
        if MusicSource.scriptable(item.bundleID) {
            // Started by hand while the video runs: the user wants both, so this one is no longer ours to resume.
            if item.playing { handoffPaused.remove(item.bundleID) }
            return
        }
        if item.playing {
            resumeWork?.cancel(); resumeWork = nil
            if interrupter != item.bundleID || !interrupterPlaying { pauseMusic() }
            interrupter = item.bundleID; interrupterPlaying = true
        } else if interrupter == item.bundleID {
            interrupterPlaying = false
            scheduleResume()
        }
    }

    private func pauseMusic() {
        Self.trace("handoff start: pausing music for \(activeBundleID ?? "-")")
        for source in MusicSource.allCases where Self.isRunning(source.bundleID) && !scriptDenied.contains(source.bundleID) {
            let id = source.bundleID
            queue.async {
                let (value, error) = Self.run("if player state is playing then\npause\nreturn true\nend if\nreturn false", bundleID: id)
                Self.trace("handoff pause \(id) paused=\(value?.booleanValue == true) error=\(error.map(String.init) ?? "nil")")
                DispatchQueue.main.async {
                    if error == -1743 { self.automationDenied(id); return }
                    guard value?.booleanValue == true else { return }
                    self.handoffPaused.insert(id)
                    self.poll(id)
                }
            }
        }
    }

    /// Waits out short gaps (buffering, the next video, a seek) before bringing the music back.
    private func scheduleResume() {
        resumeWork?.cancel()
        guard !handoffPaused.isEmpty else { interrupter = nil; return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.interrupterPlaying else { return }
            let targets = self.handoffPaused
            self.handoffPaused.removeAll(); self.interrupter = nil
            Self.trace("handoff resume \(targets.sorted().joined(separator: ","))")
            for id in targets where Self.isRunning(id) {
                self.queue.async {
                    _ = Self.run("if player state is paused then play", bundleID: id)
                    DispatchQueue.main.async { self.poll(id) }
                }
            }
        }
        resumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func connect(_ selected: MusicSource) {
        guard !bridgeActive else { return }
        source = selected; connected = true; generation += 1
        artwork = nil; accent = nil; hasTrack = false; lastArtworkKey = ""
        UserDefaults.standard.set(source.rawValue, forKey: "musicSource")
        UserDefaults.standard.set(true, forKey: "musicConnected")
        if !isRunning {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else {
                status = "\(source.rawValue) bu Mac’te yüklü değil."; return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
            }
        } else { refresh() }
    }
    func disconnect() {
        guard !bridgeActive else { return }
        generation += 1; connected = false; hasTrack = false; playing = false; artwork = nil; accent = nil
        title = "Müziğine yer aç"; artist = "Apple Music veya Spotify’ı bağla."; status = nil
        UserDefaults.standard.set(false, forKey: "musicConnected")
    }
    var isRunning: Bool { Self.isRunning(source.bundleID) }
    static func isRunning(_ bundleID: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    func refresh() {
        // The bridge owns the state while it runs; the Apple Events path must not overwrite it.
        guard !bridgeActive, connected, !busy else { return }
        guard isRunning else {
            playing = false; hasTrack = false; status = "\(source.rawValue) açık değil."; return
        }
        busy = true; lastRefresh = Date()
        let selected = source, currentGeneration = generation
        let read = "return {name of current track, artist of current track, duration of current track, player position, player state as string}"
        queue.async {
            let (value, error) = Self.run(read, bundleID: selected.bundleID)
            let name = value?.atIndex(1)?.stringValue ?? ""
            let artist = value?.atIndex(2)?.stringValue ?? ""
            let duration = (value?.atIndex(3)?.doubleValue ?? 0) / (selected == .spotify ? 1000 : 1)
            let position = value?.atIndex(4)?.doubleValue ?? 0
            let playing = value?.atIndex(5)?.stringValue == "playing"
            DispatchQueue.main.async {
                self.busy = false
                guard self.generation == currentGeneration, self.connected else { return }
                if let error {
                    self.playing = false; self.hasTrack = false
                    self.status = error == -1743 ? "Müzik erişimi kapalı. Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon." : "\(selected.rawValue)’te bir parça aç."
                    return
                }
                self.title = name.isEmpty ? "Bir parça seç" : name; self.artist = artist
                self.duration = max(0, duration); self.position = max(0, position); self.positionDate = Date()
                self.playing = playing; self.hasTrack = !name.isEmpty; self.status = nil
                let key = "\(selected.rawValue)|\(name)|\(artist)"
                if self.lastArtworkKey != key {
                    self.lastArtworkKey = key; self.artwork = nil; self.accent = nil
                    self.loadArtwork(source: selected, key: key, generation: currentGeneration)
                }
            }
        }
    }
    private func loadArtwork(source: MusicSource, key: String, generation: Int) {
        fetchArtwork(bundleID: source.bundleID) { image in
            guard let image, self.generation == generation, self.lastArtworkKey == key else { return }
            self.artwork = image
            self.queue.async {
                let accent = Palette.accent(for: image)
                DispatchQueue.main.async { if self.artwork === image { self.accent = accent } }
            }
        }
    }
    /// Current track's artwork from Music (raw data) or Spotify (an https URL); completion on the main thread.
    private func fetchArtwork(bundleID: String, completion: @escaping (NSImage?) -> Void) {
        let isMusic = bundleID == MusicSource.music.bundleID
        queue.async {
            let command = isMusic ? "return raw data of artwork 1 of current track" : "return artwork url of current track"
            let (value, _) = Self.run(command, bundleID: bundleID)
            if isMusic {
                let image = value.flatMap { NSImage(data: $0.data) }
                DispatchQueue.main.async { completion(image) }
            } else if let string = value?.stringValue, let url = URL(string: string), url.scheme == "https" {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    let image = data.flatMap { $0.count < 8_000_000 ? NSImage(data: $0) : nil }
                    DispatchQueue.main.async { completion(image) }
                }.resume()
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    func command(_ action: String) {
        if bridgeActive {
            guard let id = sourceBundleID else { return }
            if id == activeBundleID {
                switch action {
                case "playpause": bridge.send(.togglePlayPause)
                case "next track": bridge.send(.next)
                case "previous track": bridge.send(.previous)
                default: break
                }
            } else if MusicSource.scriptable(id), controllable {
                // A background Music/Spotify: drive it directly. Playing it by hand ends any handoff for it.
                if action == "playpause" { handoffPaused.remove(id) }
                queue.async {
                    _ = Self.run(action, bundleID: id)
                    DispatchQueue.main.async { self.poll(id) }
                }
            }
            return
        }
        guard connected, isRunning else { return }
        let selected = source
        queue.async {
            _ = Self.run(action, bundleID: selected.bundleID)
            DispatchQueue.main.async { self.refresh() }
        }
    }
    func seek(_ seconds: Double) {
        let target = min(duration, max(0, seconds))
        position = target; positionDate = Date()
        guard bridgeActive, let id = sourceBundleID else { command("set player position to \(target)"); return }
        if let index = sessions.firstIndex(where: { $0.bundleID == id }) { sessions[index].position = target; sessions[index].positionDate = Date() }
        if id == activeBundleID { bridge.seek(to: target) }
        else if MusicSource.scriptable(id), controllable { queue.async { _ = Self.run("set player position to \(target)", bundleID: id) } }
    }
    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    /// Icon of the app that is playing (Music, Spotify, Safari, Chrome…), for the source button.
    var sourceIcon: NSImage? { sourceBundleID.flatMap(Self.icon(for:)) }
    private static var icons: [String: NSImage] = [:]
    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
    func activateSource() {
        guard let id = sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    /// Interpolates between 2-second refreshes so the scrub bar moves smoothly.
    func livePosition(at now: Date) -> Double {
        guard playing else { return position }
        return min(duration, position + max(0, now.timeIntervalSince(positionDate)))
    }
    private static func run(_ body: String, bundleID: String) -> (NSAppleEventDescriptor?, Int?) {
        let text = "with timeout of 4 seconds\ntell application id \"\(bundleID)\"\n\(body)\nend tell\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: text)?.executeAndReturnError(&error)
        return (result, error?[NSAppleScript.errorNumber] as? Int)
    }
    deinit { timer?.invalidate(); pollTimer?.invalidate(); bridge.stop() }
}
