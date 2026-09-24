import AppKit
import Combine

enum MusicSource: String, CaseIterable, Identifiable {
    case music = "Apple Music", spotify = "Spotify"
    var id: String { rawValue }
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    /// Players Damla can read and drive over Apple Events even when they are not the system's Now Playing app.
    static func scriptable(_ bundleID: String) -> Bool { allCases.contains { $0.bundleID == bundleID } }
}

/// What happens to Music/Spotify when a video (or any other player) starts.
enum HandoffMode: String, CaseIterable, Identifiable {
    case pause, duck, off
    var id: String { rawValue }
    var title: String {
        switch self { case .pause: return String(localized: "Duraklat"); case .duck: return String(localized: "Sesini kıs"); case .off: return String(localized: "Hiçbir şey yapma") }
    }
    static let duckLevel = 0.2   // ducked music plays at a fifth of its volume

    /// Earlier versions stored an on/off switch.
    static var saved: HandoffMode {
        if let raw = UserDefaults.standard.string(forKey: "mediaHandoffMode"), let mode = HandoffMode(rawValue: raw) { return mode }
        return (UserDefaults.standard.object(forKey: "mediaHandoff") as? Bool) == false ? .off : .pause
    }
}

final class MediaService: ObservableObject {
    @Published var source: MusicSource = MusicSource(rawValue: UserDefaults.standard.string(forKey: "musicSource") ?? "") ?? .music
    @Published var connected = UserDefaults.standard.bool(forKey: "musicConnected")
    @Published var title = String(localized: "Müziğine yer aç")
    @Published var artist = String(localized: "Apple Music veya Spotify’ı bağla.")
    @Published private(set) var album = ""
    /// The player named the artist itself: a real song worth looking up lyrics for.
    @Published private(set) var artistKnown = false
    /// Whether the shown Apple Music track is a favorite; nil for other players (Spotify has no such command).
    @Published private(set) var favorited: Bool?
    private var favoriteKey = ""
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
    /// Decides sessions, the shown player and handoffs; this class only carries out its effects.
    private var store = MediaSessionStore(isRunning: { MediaService.isRunning($0) }, appName: { MediaService.appName(for: $0) })
    /// False when the shown session is a background browser tab the bridge no longer reports: no transport.
    @Published private(set) var controllable = true
    /// Pause Music/Spotify when a video (or any other player) starts, resume when it stops.
    @Published var handoffMode = HandoffMode.saved {
        didSet { UserDefaults.standard.set(handoffMode.rawValue, forKey: "mediaHandoffMode"); store.handoffEnabled = handoffMode != .off }
    }
    /// Music/Spotify volume (0–100) per bundle id, read when the mixer opens and after every change.
    @Published private(set) var appVolumes: [String: Double] = [:]
    /// Volumes to put back once a ducked handoff ends (or Damla quits).
    private var duckedVolumes: [String: Int] = [:]
    private var volumeWork: [String: DispatchWorkItem] = [:]
    var onNotice: ((String) -> Void)?
    let bridge = NowPlayingBridge()
    private var pollTimer: Timer?
    private var lastPoll = Date.distantPast
    private var polling: Set<String> = []
    private var deniedNoticeShown = false
    private var timer: Timer?
    private var busy = false
    private let queue = DispatchQueue(label: "app.damla.media", qos: .utility)
    private var lastArtworkKey = ""
    private var generation = 0
    private var lastRefresh = Date.distantPast
    /// Set while the panel is open: refresh every second. Otherwise 2 s while playing, 6 s when idle.
    var wantsFrequentUpdates = false

    func start() {
        store.handoffEnabled = handoffMode != .off   // the saved choice, not the store's default
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
        title = String(localized: "Müzik"); artist = String(localized: "Bir şey çal: Müzik, Spotify, Safari…")
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
        Self.trace(item.map { "bridge \($0.bundleID) playing=\($0.playing)" } ?? "bridge nil")
        perform(store.bridgeReported(item, image: image, now: Date()))
    }

    /// Carries out what the store decided, then shows the result.
    private func perform(_ effects: [MediaEffect]) {
        for effect in effects {
            switch effect {
            case .pauseMusic: pauseMusic()
            case .resume(let ids): resume(ids)
            case .poll(let id): poll(id)
            case let .fetchArtwork(id, key):
                fetchArtwork(bundleID: id) { [weak self] image in
                    guard let self else { return }
                    self.perform(self.store.artworkFetched(id, key: key, image: image))
                }
            case .computeAccent(let id):
                guard let image = store.session(id)?.artwork else { continue }
                queue.async {
                    let accent = Palette.accent(for: image)
                    DispatchQueue.main.async { self.store.accentComputed(id, image: image, accent: accent); self.applyDisplay() }
                }
            case let .confirmGone(token, delay):
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.perform(self.store.goneConfirmed(token: token))
                }
            case let .scheduleResume(token, delay):
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.perform(self.store.resumeDue(token: token))
                }
            }
        }
        applyDisplay()
    }

    func isLive(_ session: MediaSession) -> Bool { store.isLive(session) }

    /// Another session that is playing right now besides the shown one (for the closed notch's badge).
    var otherPlaying: MediaSession? { store.otherPlaying }

    func select(_ bundleID: String) { perform(store.select(bundleID)) }

    /// Copies the shown session into the flat properties the views read.
    private func applyDisplay() {
        sessions = store.sessions
        guard let session = store.displayed else {
            hasTrack = false; playing = false; artwork = nil; accent = nil; sourceBundleID = nil; controllable = true
            title = String(localized: "Müzik"); artist = String(localized: "Bir şey çal: Müzik, Spotify, Safari…")
            return
        }
        let live = store.isLive(session)
        hasTrack = true
        title = session.title; artist = session.artist
        if album != session.album { album = session.album }
        if artistKnown != session.artistKnown { artistKnown = session.artistKnown }
        refreshFavorite(session)
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
        store.inject([
            MediaSession(bundleID: MusicSource.music.bundleID, title: "Sakin Akşam", artist: "Demo Sanatçı", playing: false,
                         duration: 214, position: 81, artwork: art(.systemPink), artworkKey: "demo-1", accent: .systemPink),
            MediaSession(bundleID: "com.google.Chrome", title: "Voleybol · canlı yayın", artist: "Google Chrome", playing: true,
                         duration: 0, position: 0, artwork: art(.systemTeal), artworkKey: "demo-2", accent: .systemTeal)
        ], active: "com.google.Chrome")
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
        for id in store.pollTargets { poll(id) }
        if store.prune(now: Date()) { applyDisplay() }
    }

    private func poll(_ id: String) {
        guard !polling.contains(id), !store.scriptDenied.contains(id), Self.isRunning(id) else { return }
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
                Self.trace("poll \(id) error=\(error.map(String.init) ?? "nil") name=\(name) playing=\(playing)")
                let result: MediaPollResult = error == -1743 ? .denied
                    : error == nil && !name.isEmpty ? .track(title: name, artist: artist, duration: duration, position: position, playing: playing)
                    : .empty
                self.perform(self.store.polled(id, result, now: Date()))
                if error == -1743 { self.noticeDenied(id) }
            }
        }
    }

    private func noticeDenied(_ id: String) {
        guard !deniedNoticeShown else { return }
        deniedNoticeShown = true
        onNotice?(String(localized: "\(Self.appName(for: id)) için otomasyon izni kapalı · Sistem Ayarları → Gizlilik → Otomasyon"))
    }

    // MARK: Handoff

    /// Pauses (or, in duck mode, quiets) whatever Music/Spotify is playing, and reports each one to the store.
    private func pauseMusic() {
        let duck = handoffMode == .duck
        Self.trace("handoff start (\(duck ? "duck" : "pause")) for \(store.activeBundleID ?? "-")")
        for source in MusicSource.allCases where Self.isRunning(source.bundleID) && !store.scriptDenied.contains(source.bundleID) {
            let id = source.bundleID
            let script = duck
                ? "if player state is playing then\nset v to sound volume\nset sound volume to (round (v * \(HandoffMode.duckLevel)))\nreturn v\nend if\nreturn -1"
                : "if player state is playing then\npause\nreturn 1\nend if\nreturn -1"
            queue.async {
                let (value, error) = Self.run(script, bundleID: id)
                let result = Int(value?.int32Value ?? -1)
                Self.trace("handoff \(duck ? "duck" : "pause") \(id) result=\(result) error=\(error.map(String.init) ?? "nil")")
                DispatchQueue.main.async {
                    if error == -1743 { self.store.automationDenied(id); self.noticeDenied(id); self.applyDisplay(); return }
                    guard result >= 0 else { return }
                    if duck { self.duckedVolumes[id] = result }
                    self.perform(self.store.musicPaused(id))
                }
            }
        }
    }

    /// Plays paused music again, or fades ducked music back up to where it was.
    private func resume(_ ids: [String]) {
        Self.trace("handoff resume \(ids.joined(separator: ","))")
        for id in ids {
            if let volume = duckedVolumes.removeValue(forKey: id) {
                fadeVolume(id, to: volume)
                continue
            }
            queue.async {
                _ = Self.run("if player state is paused then play", bundleID: id)
                DispatchQueue.main.async { self.poll(id) }
            }
        }
    }

    /// Four steps over about 0.6 s, so the music swells back instead of jumping.
    private func fadeVolume(_ id: String, to target: Int) {
        queue.async {
            let (value, _) = Self.run("return sound volume", bundleID: id)
            let start = Int(value?.int32Value ?? Int32(target))
            for step in 1...4 {
                let level = start + (target - start) * step / 4
                _ = Self.run("set sound volume to \(level)", bundleID: id)
                if step < 4 { Thread.sleep(forTimeInterval: 0.15) }
            }
            DispatchQueue.main.async { self.appVolumes[id] = Double(target) }
        }
    }

    /// Puts ducked music back at once; called when Damla quits so nothing stays quiet.
    func restoreDucked() {
        for (id, volume) in duckedVolumes { _ = Self.run("set sound volume to \(volume)", bundleID: id) }
        duckedVolumes.removeAll()
    }

    // MARK: Favorite (Apple Music)

    /// Reads the heart once per Music track; other players clear it.
    private func refreshFavorite(_ session: MediaSession) {
        let key = "\(session.bundleID)|\(session.title)|\(session.artist)"
        guard key != favoriteKey else { return }
        favoriteKey = key
        guard session.bundleID == MusicSource.music.bundleID, store.isLive(session) else { favorited = nil; return }
        queue.async {
            let (value, _) = Self.run("return favorited of current track", bundleID: MusicSource.music.bundleID)
            DispatchQueue.main.async { if self.favoriteKey == key { self.favorited = value?.booleanValue } }
        }
    }

    func toggleFavorite() {
        guard let current = favorited else { return }
        favorited = !current   // at once; corrected below if Music says otherwise
        let key = favoriteKey
        queue.async {
            let (value, _) = Self.run("set favorited of current track to \(!current)\nreturn favorited of current track", bundleID: MusicSource.music.bundleID)
            DispatchQueue.main.async { if self.favoriteKey == key, let value { self.favorited = value.booleanValue } }
        }
    }

    // MARK: Per-app volume (Music, Spotify)

    /// Music/Spotify apps that are running and reachable: the rows the mixer can offer today.
    var scriptablePlayers: [String] {
        MusicSource.allCases.map(\.bundleID).filter { Self.isRunning($0) && !store.scriptDenied.contains($0) }
    }

    func refreshAppVolumes() {
        for id in scriptablePlayers {
            queue.async {
                let (value, error) = Self.run("return sound volume", bundleID: id)
                DispatchQueue.main.async {
                    if error == -1743 { self.store.automationDenied(id); self.noticeDenied(id); return }
                    if let value { self.appVolumes[id] = Double(value.int32Value) }
                }
            }
        }
    }

    /// Slider moves arrive many times a second; the player gets the last one after a short pause.
    func setAppVolume(_ id: String, _ volume: Double) {
        let level = Int(min(100, max(0, volume)).rounded())
        appVolumes[id] = Double(level)
        duckedVolumes.removeValue(forKey: id)   // a hand-picked level wins over a pending restore
        volumeWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.queue.async { _ = Self.run("set sound volume to \(level)", bundleID: id) }
        }
        volumeWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func connect(_ selected: MusicSource) {
        guard !bridgeActive else { return }
        source = selected; connected = true; generation += 1
        artwork = nil; accent = nil; hasTrack = false; lastArtworkKey = ""
        UserDefaults.standard.set(source.rawValue, forKey: "musicSource")
        UserDefaults.standard.set(true, forKey: "musicConnected")
        if !isRunning {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else {
                status = String(localized: "\(source.rawValue) bu Mac’te yüklü değil."); return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
            }
        } else { refresh() }
    }
    func disconnect() {
        guard !bridgeActive else { return }
        generation += 1; connected = false; hasTrack = false; playing = false; artwork = nil; accent = nil
        title = String(localized: "Müziğine yer aç"); artist = String(localized: "Apple Music veya Spotify’ı bağla."); status = nil
        UserDefaults.standard.set(false, forKey: "musicConnected")
    }
    var isRunning: Bool { Self.isRunning(source.bundleID) }
    static func isRunning(_ bundleID: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    func refresh() {
        // The bridge owns the state while it runs; the Apple Events path must not overwrite it.
        guard !bridgeActive, connected, !busy else { return }
        guard isRunning else {
            playing = false; hasTrack = false; status = String(localized: "\(source.rawValue) açık değil."); return
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
                    self.status = error == -1743 ? String(localized: "Müzik erişimi kapalı. Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon.") : String(localized: "\(selected.rawValue)’te bir parça aç.")
                    return
                }
                self.title = name.isEmpty ? String(localized: "Bir parça seç") : name; self.artist = artist
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
            if id == store.activeBundleID {
                switch action {
                case "playpause": bridge.send(.togglePlayPause)
                case "next track": bridge.send(.next)
                case "previous track": bridge.send(.previous)
                default: break
                }
            } else if MusicSource.scriptable(id), controllable {
                // A background Music/Spotify: drive it directly. Playing it by hand ends any handoff for it.
                if action == "playpause" { store.playedByHand(id) }
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
        store.seeked(id, to: target, now: Date())
        if id == store.activeBundleID { bridge.seek(to: target) }
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
