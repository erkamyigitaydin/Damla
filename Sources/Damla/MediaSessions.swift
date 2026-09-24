import AppKit

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

/// What the store asks the outside world to do. `MediaService` turns these into Apple Events and timers and
/// reports the outcome back; the store itself never touches an app, a clock or a queue, so it can be tested.
enum MediaEffect: Equatable {
    case pauseMusic                          // pause Music/Spotify if playing; answer with `musicPaused(_:)`
    case resume([String])                    // play these again if they are still paused
    case poll(String)                        // read a background Music/Spotify; answer with `polled(_:_:now:)`
    case fetchArtwork(String, key: String)   // answer with `artworkFetched(_:key:image:)`
    case computeAccent(String)               // artwork changed; answer with `accentComputed(_:image:accent:)`
    case confirmGone(token: Int, after: TimeInterval)     // call `goneConfirmed(token:)` then
    case scheduleResume(token: Int, after: TimeInterval)  // call `resumeDue(token:)` then
}

/// What a background poll of Music/Spotify found.
enum MediaPollResult {
    case denied                                         // Automation permission refused (-1743)
    case empty                                          // running with nothing queued, or the read failed
    case track(title: String, artist: String, duration: Double, position: Double, playing: Bool)
}

/// Decides which players exist, which one is shown and when the music hands over to a video.
struct MediaSessionStore {
    static let goneDelay: TimeInterval = 2
    static let resumeDelay: TimeInterval = 2.5
    static let staleBrowser: TimeInterval = 15 * 60

    /// Every player seen since launch, in first-seen order.
    private(set) var sessions: [MediaSession] = []
    private(set) var activeBundleID: String?      // the app the bridge currently reports
    private(set) var pinnedBundleID: String?      // chosen by hand; cleared when another player starts
    private(set) var followedBundleID: String?    // the last player that started playing; stays shown while paused
    private(set) var scriptDenied: Set<String> = []
    private(set) var handoffPaused: Set<String> = []   // what Damla paused for the current interrupter
    private(set) var interrupter: String?
    private(set) var interrupterPlaying = false
    var handoffEnabled = true {
        didSet { if !handoffEnabled { handoffPaused.removeAll(); interrupter = nil; interrupterPlaying = false } }
    }
    private var bridgeArtworkKey = ""
    private var goneToken = 0
    private var goneCandidate: String?   // the player an empty report may have ended
    private var resumeToken = 0
    private let isRunning: (String) -> Bool
    private let appName: (String) -> String

    init(isRunning: @escaping (String) -> Bool, appName: @escaping (String) -> String) {
        self.isRunning = isRunning
        self.appName = appName
    }

    // MARK: Reading

    /// Live means Damla can still see and drive it: the bridge reports it, or Apple Events reach it.
    func isLive(_ session: MediaSession) -> Bool {
        session.bundleID == activeBundleID || (session.scriptable && !scriptDenied.contains(session.bundleID) && isRunning(session.bundleID))
    }

    /// The pinned session, else the last one that started playing, else something playing (the bridge's app
    /// first), else the bridge's app, else the latest.
    var displayed: MediaSession? {
        if let pinned = pinnedBundleID, let session = session(pinned) { return session }
        if let followed = followedBundleID, let session = session(followed) { return session }
        let playing = sessions.filter { $0.playing && isLive($0) }
        return playing.first { $0.bundleID == activeBundleID } ?? playing.first
            ?? sessions.first { $0.bundleID == activeBundleID } ?? sessions.max { $0.lastSeen < $1.lastSeen }
    }

    /// Another session that is playing right now besides the shown one (for the closed notch's badge).
    var otherPlaying: MediaSession? {
        let shown = displayed?.bundleID
        return sessions.first { $0.bundleID != shown && $0.playing && isLive($0) }
    }

    /// Music/Spotify sessions the bridge does not report, plus anything paused for a handoff: read these.
    var pollTargets: Set<String> {
        Set(sessions.filter { $0.scriptable }.map(\.bundleID)).union(handoffPaused).subtracting([activeBundleID].compactMap { $0 })
    }

    func session(_ id: String) -> MediaSession? { sessions.first { $0.bundleID == id } }

    // MARK: Bridge

    mutating func bridgeReported(_ item: NowPlayingBridge.Item?, image: NSImage?, now: Date) -> [MediaEffect] {
        guard let item else {
            let previous = activeBundleID
            // macOS sends an empty report between two players too; only a lasting one means the player is gone.
            if let previous { goneCandidate = previous }
            activeBundleID = nil; bridgeArtworkKey = ""
            goneToken += 1
            return [.confirmGone(token: goneToken, after: Self.goneDelay)]
        }
        goneToken += 1; goneCandidate = nil   // a report arrived: any pending "gone" check is void
        let id = item.bundleID
        activeBundleID = id
        // Pausing never moves the view away; a player takes it only by starting: going from stopped to playing,
        // or cutting in while the shown one plays. About a minute after the shown player pauses, macOS hands Now
        // Playing back to a player that never stopped (a video left running); that is not a start, and neither
        // are that player's routine updates afterwards, so the paused one stays on screen.
        let followed = followedBundleID.flatMap { session($0) }
        let wasPlaying = session(id)?.playing == true
        let followedPlaying = followed.map { $0.playing && isLive($0) } ?? false
        if item.playing && id != followedBundleID && (followed == nil || !wasPlaying || followedPlaying) {
            followedBundleID = id; pinnedBundleID = nil
        }
        var effects: [MediaEffect] = []
        var session = session(id) ?? MediaSession(bundleID: id)
        session.title = item.title
        // Browsers often send no artist; fall back to the album, then to the player's name (Safari, Chrome…).
        session.artist = !item.artist.isEmpty ? item.artist : !item.album.isEmpty ? item.album : appName(id)
        session.playing = item.playing
        session.duration = item.duration.isFinite ? max(0, item.duration) : 0   // live streams report infinity
        session.position = item.elapsed.isFinite ? max(0, item.elapsed) : 0
        session.positionDate = item.timestamp
        session.lastSeen = now
        if let image {
            session.artwork = image; session.artworkKey = item.artworkKey; session.accent = nil
            effects.append(.computeAccent(id))
        } else if item.artworkKey.isEmpty {
            session.artwork = nil; session.artworkKey = ""; session.accent = nil
        } else if item.artworkKey != session.artworkKey, bridgeArtworkKey == item.artworkKey {
            // Same artwork payload as before, now credited to this app (the bridge only sends images on change).
            session.artworkKey = item.artworkKey
        }
        bridgeArtworkKey = item.artworkKey
        upsert(session)
        effects += handoff(active: item)
        return effects
    }

    /// The empty report lasted: a browser tab is gone (Music/Spotify stay, the poll keeps them honest) and a
    /// handoff may resume. A stale token means another report came in meanwhile.
    mutating func goneConfirmed(token: Int) -> [MediaEffect] {
        guard token == goneToken, activeBundleID == nil else { return [] }
        if let gone = goneCandidate, !MusicSource.scriptable(gone) { sessions.removeAll { $0.bundleID == gone } }
        goneCandidate = nil
        guard handoffEnabled, interrupter != nil else { return [] }
        interrupterPlaying = false
        return scheduleResume()
    }

    // MARK: Background players

    mutating func polled(_ id: String, _ result: MediaPollResult, now: Date) -> [MediaEffect] {
        guard id != activeBundleID else { return [] }   // the bridge took it over meanwhile
        switch result {
        case .denied:
            automationDenied(id)
            return []
        case .empty:
            if !handoffPaused.contains(id) { sessions.removeAll { $0.bundleID == id } }
            return []
        case let .track(title, artist, duration, position, playing):
            var session = session(id) ?? MediaSession(bundleID: id)
            let key = "script:\(title)|\(artist)"
            let trackChanged = session.title != title || session.artist != artist || session.artwork == nil
            session.title = title; session.artist = artist.isEmpty ? appName(id) : artist
            session.duration = duration.isFinite ? max(0, duration) : 0
            session.position = max(0, position); session.positionDate = now
            session.playing = playing; session.lastSeen = now
            var effects: [MediaEffect] = []
            if trackChanged && session.artworkKey != key {
                session.artworkKey = key
                effects.append(.fetchArtwork(id, key: key))
            }
            upsert(session)
            return effects
        }
    }

    mutating func artworkFetched(_ id: String, key: String, image: NSImage?) -> [MediaEffect] {
        guard let image, let index = index(id), sessions[index].artworkKey == key else { return [] }
        sessions[index].artwork = image
        return [.computeAccent(id)]
    }

    mutating func accentComputed(_ id: String, image: NSImage, accent: NSColor?) {
        guard let index = index(id), sessions[index].artwork === image else { return }
        sessions[index].accent = accent
    }

    mutating func automationDenied(_ id: String) {
        scriptDenied.insert(id); handoffPaused.remove(id)
    }

    /// Background browser tabs cannot be read; forget them when their app quits or after a quiet while. Music or
    /// Spotify that quit go too. Returns true when something was removed.
    @discardableResult
    mutating func prune(now: Date) -> Bool {
        let before = sessions.count
        sessions.removeAll { session in
            guard session.bundleID != activeBundleID else { return false }
            if !isRunning(session.bundleID) { return true }
            return !session.scriptable && now.timeIntervalSince(session.lastSeen) > Self.staleBrowser
        }
        handoffPaused = handoffPaused.filter(isRunning)
        return sessions.count != before
    }

    mutating func select(_ id: String) -> [MediaEffect] {
        pinnedBundleID = id
        guard let session = session(id), session.scriptable, id != activeBundleID else { return [] }
        return [.poll(id)]
    }

    /// Moves the scrub position at once, before the player confirms it.
    mutating func seeked(_ id: String, to seconds: Double, now: Date) {
        guard let index = index(id) else { return }
        sessions[index].position = seconds; sessions[index].positionDate = now
    }

    /// The user pressed play/pause on a background Music/Spotify: a handoff no longer owns it.
    mutating func playedByHand(_ id: String) { handoffPaused.remove(id) }

    // MARK: Handoff

    /// A non-music player starting pauses Music/Spotify; when it stops for a moment, the music comes back.
    private mutating func handoff(active item: NowPlayingBridge.Item) -> [MediaEffect] {
        guard handoffEnabled else { return [] }
        if MusicSource.scriptable(item.bundleID) {
            // Started by hand while the video runs: the user wants both, so this one is no longer ours to resume.
            if item.playing { handoffPaused.remove(item.bundleID) }
            return []
        }
        if item.playing {
            resumeToken += 1   // cancels a pending resume: the video is back (buffering, next video, seek)
            let starting = interrupter != item.bundleID || !interrupterPlaying
            interrupter = item.bundleID; interrupterPlaying = true
            return starting ? [.pauseMusic] : []
        }
        guard interrupter == item.bundleID else { return [] }
        interrupterPlaying = false
        return scheduleResume()
    }

    mutating func musicPaused(_ id: String) -> [MediaEffect] {
        handoffPaused.insert(id)
        // The video may already have stopped while the pause was on its way; the music is due back then.
        return [.poll(id)] + (interrupterPlaying ? [] : scheduleResume())
    }

    /// Waits out short gaps before bringing the music back; `resumeDue` decides when the time comes.
    private mutating func scheduleResume() -> [MediaEffect] {
        resumeToken += 1
        guard !handoffPaused.isEmpty else { if !interrupterPlaying { interrupter = nil }; return [] }
        return [.scheduleResume(token: resumeToken, after: Self.resumeDelay)]
    }

    mutating func resumeDue(token: Int) -> [MediaEffect] {
        guard token == resumeToken, !interrupterPlaying, !handoffPaused.isEmpty else { return [] }
        let targets = handoffPaused.filter(isRunning).sorted()
        handoffPaused.removeAll(); interrupter = nil
        return targets.isEmpty ? [] : [.resume(targets)]
    }

    // MARK: Helpers

    private func index(_ id: String) -> Int? { sessions.firstIndex { $0.bundleID == id } }

    private mutating func upsert(_ session: MediaSession) {
        if let index = index(session.bundleID) { sessions[index] = session } else { sessions.append(session) }
    }

    /// Debug builds only: replaces everything with fixed sessions for screenshots.
    mutating func inject(_ demo: [MediaSession], active: String?) {
        sessions = demo; activeBundleID = active; pinnedBundleID = nil; followedBundleID = active
    }
}
