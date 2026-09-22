import AppKit
import Combine

enum MusicSource: String, CaseIterable, Identifiable {
    case music = "Apple Music", spotify = "Spotify"
    var id: String { rawValue }
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
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
    let bridge = NowPlayingBridge()
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
        bridge.onUpdate = { [weak self] item, image in
            guard let self else { return }
            guard let item else {
                self.hasTrack = false; self.playing = false; self.artwork = nil; self.accent = nil; self.sourceBundleID = nil
                self.title = "Müzik"; self.artist = "Bir şey çal: Müzik, Spotify, Safari…"
                return
            }
            self.hasTrack = true
            self.title = item.title
            self.artist = item.artist.isEmpty ? item.album : item.artist
            self.playing = item.playing
            self.duration = max(0, item.duration)
            self.position = max(0, item.elapsed); self.positionDate = item.timestamp
            self.sourceBundleID = item.bundleID
            if let image {
                self.artwork = image
                self.queue.async {
                    let accent = Palette.accent(for: image)
                    DispatchQueue.main.async { if self.artwork === image { self.accent = accent } }
                }
            } else if item.artworkKey.isEmpty {
                self.artwork = nil; self.accent = nil
            }
        }
        bridge.start()
    }
    func connect(_ selected: MusicSource) {
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
        generation += 1; connected = false; hasTrack = false; playing = false; artwork = nil; accent = nil
        title = "Müziğine yer aç"; artist = "Apple Music veya Spotify’ı bağla."; status = nil
        UserDefaults.standard.set(false, forKey: "musicConnected")
    }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty }

    func refresh() {
        guard connected, !busy else { return }
        guard isRunning else {
            playing = false; hasTrack = false; status = "\(source.rawValue) açık değil."; return
        }
        busy = true; lastRefresh = Date()
        let selected = source, currentGeneration = generation
        let read = "return {name of current track, artist of current track, duration of current track, player position, player state as string}"
        queue.async {
            let (value, error) = Self.run(read, source: selected)
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
        queue.async {
            let command = source == .music ? "return raw data of artwork 1 of current track" : "return artwork url of current track"
            let (value, _) = Self.run(command, source: source)
            if source == .music {
                let image = value.flatMap { NSImage(data: $0.data) }
                let accent = image.flatMap(Palette.accent(for:))
                DispatchQueue.main.async {
                    if self.generation == generation, self.lastArtworkKey == key { self.artwork = image; self.accent = accent }
                }
            } else if let string = value?.stringValue, let url = URL(string: string), url.scheme == "https" {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data, data.count < 8_000_000, let image = NSImage(data: data) else { return }
                    let accent = Palette.accent(for: image)
                    DispatchQueue.main.async {
                        if self.generation == generation, self.lastArtworkKey == key { self.artwork = image; self.accent = accent }
                    }
                }.resume()
            }
        }
    }
    func command(_ action: String) {
        if bridgeActive {
            switch action {
            case "playpause": bridge.send(.togglePlayPause)
            case "next track": bridge.send(.next)
            case "previous track": bridge.send(.previous)
            default: break
            }
            return
        }
        guard connected, isRunning else { return }
        let selected = source
        queue.async {
            _ = Self.run(action, source: selected)
            DispatchQueue.main.async { self.refresh() }
        }
    }
    func seek(_ seconds: Double) {
        let target = min(duration, max(0, seconds))
        position = target; positionDate = Date()
        if bridgeActive { bridge.seek(to: target) } else { command("set player position to \(target)") }
    }
    /// Icon of the app that is playing (Music, Spotify, Safari, Chrome…), for the source button.
    var sourceIcon: NSImage? {
        guard let id = sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
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
    private static func run(_ body: String, source: MusicSource) -> (NSAppleEventDescriptor?, Int?) {
        let text = "with timeout of 4 seconds\ntell application id \"\(source.bundleID)\"\n\(body)\nend tell\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: text)?.executeAndReturnError(&error)
        return (result, error?[NSAppleScript.errorNumber] as? Int)
    }
    deinit { timer?.invalidate(); bridge.stop() }
}
