import Foundation

/// Scenario checks for `MediaSessionStore`, replayed from the bridge reports seen on a real Mac (macOS 27):
/// empty reports between players, macOS falling back to a video left running, handoffs racing a pause.
func runMediaSelfTests(_ check: (Bool, String) -> Void) {
    let music = MusicSource.music.bundleID, chrome = "com.google.Chrome", safari = "com.apple.Safari"
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    var running: Set<String> = [music, chrome, safari]
    func item(_ id: String, playing: Bool, duration: Double = 200, title: String = "Parça") -> NowPlayingBridge.Item {
        NowPlayingBridge.Item(title: title, artist: "Sanatçı", album: "", bundleID: id, playing: playing, duration: duration,
                              elapsed: 10, timestamp: t0, playbackRate: playing ? 1 : 0, artworkKey: "")
    }
    func store() -> MediaSessionStore { MediaSessionStore(isRunning: { running.contains($0) }, appName: { $0 }) }
    func token(_ effects: [MediaEffect]) -> Int? {
        for effect in effects { if case let .confirmGone(token, _) = effect { return token }; if case let .scheduleResume(token, _) = effect { return token } }
        return nil
    }

    // An empty report between two players is not an ending.
    var s = store()
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    let gap = s.bridgeReported(nil, image: nil, now: t0)
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.goneConfirmed(token: token(gap) ?? -1)
    check(s.session(chrome) != nil && s.session(music) != nil, "Empty report between players keeps the previous one")
    check(s.displayed?.bundleID == music, "The player that started is shown")

    // A lasting empty report ends a browser tab but not Music.
    s = store()
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    _ = s.goneConfirmed(token: token(s.bridgeReported(nil, image: nil, now: t0)) ?? -1)
    check(s.session(chrome) == nil, "Lasting empty report removes a browser tab")
    s = store()
    _ = s.bridgeReported(item(music, playing: false), image: nil, now: t0)
    _ = s.goneConfirmed(token: token(s.bridgeReported(nil, image: nil, now: t0)) ?? -1)
    check(s.session(music) != nil, "Lasting empty report keeps Music (polled instead)")

    // Pausing never moves the view; macOS falling back to a running video does not either.
    s = store()
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(music, playing: false), image: nil, now: t0)
    check(s.displayed?.bundleID == music, "Paused player stays shown")
    _ = s.bridgeReported(nil, image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    check(s.displayed?.bundleID == music, "Fallback to a video left running keeps the paused music shown")
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0.addingTimeInterval(15))
    check(s.displayed?.bundleID == music, "The video's routine updates do not take the view either")
    check(s.isLive(s.session(music)!), "Music behind the video stays live and controllable")
    _ = s.bridgeReported(item(chrome, playing: false), image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    check(s.displayed?.bundleID == chrome, "The video starting again (stopped → playing) takes the view")

    // Cutting in while the shown one plays, or a fresh player after a pause, takes the view.
    s = store()
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    check(s.displayed?.bundleID == chrome, "A player cutting in while music plays is shown")
    s = store()
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(music, playing: false), image: nil, now: t0)
    _ = s.bridgeReported(item(safari, playing: true), image: nil, now: t0)
    check(s.displayed?.bundleID == safari, "A new player after a pause is shown")

    // A hand-picked session sticks until another player starts.
    _ = s.select(music)
    check(s.displayed?.bundleID == music, "Picking a session shows it")
    _ = s.bridgeReported(item(safari, playing: true), image: nil, now: t0.addingTimeInterval(5))
    check(s.displayed?.bundleID == music, "Routine updates keep the picked session")
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    check(s.displayed?.bundleID == chrome && s.pinnedBundleID == nil, "Another player starting clears the pick")

    // Live streams report an infinite duration.
    s = store()
    _ = s.bridgeReported(item(chrome, playing: true, duration: .infinity), image: nil, now: t0)
    check(s.displayed?.duration == 0, "Infinite duration reads as live (0)")

    // Handoff: video starts → music pauses; video stops → music resumes after the grace period.
    s = store()
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    let start = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    check(start.contains(.pauseMusic), "Video starting pauses the music")
    check(!s.bridgeReported(item(chrome, playing: true), image: nil, now: t0).contains(.pauseMusic), "Routine video updates do not pause again")
    _ = s.musicPaused(music)
    let stop = s.bridgeReported(item(chrome, playing: false), image: nil, now: t0)
    let resumeToken = token(stop)
    check(resumeToken != nil, "Video stopping schedules the resume")
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    check(s.resumeDue(token: resumeToken ?? -1).isEmpty, "Video back within the grace period cancels the resume")
    let stopAgain = s.bridgeReported(item(chrome, playing: false), image: nil, now: t0)
    check(s.resumeDue(token: token(stopAgain) ?? -1) == [.resume([music])], "Music resumes after the grace period")
    check(s.handoffPaused.isEmpty && s.interrupter == nil, "Handoff ends after resuming")

    // The video stopping before the pause lands (seen live): the music still comes back.
    s = store()
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: false), image: nil, now: t0)
    let late = s.musicPaused(music)
    check(s.resumeDue(token: token(late) ?? -1) == [.resume([music])], "Pause landing after the video stopped still resumes")

    // Playing the music by hand during the video: it is no longer Damla's to resume.
    s = store()
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    _ = s.musicPaused(music)
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    check(s.handoffPaused.isEmpty, "Music started by hand leaves the handoff")
    s.handoffEnabled = false
    check(!s.bridgeReported(item(safari, playing: true), image: nil, now: t0).contains(.pauseMusic), "Handoff off: nothing is paused")

    // Polling background Music/Spotify.
    s = store()
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    check(s.pollTargets == [music], "Background Music is polled, the bridge's app is not")
    _ = s.polled(music, .denied, now: t0)
    check(!s.isLive(s.session(music)!), "Automation denied: Music is shown as not controllable")
    s = store()
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    _ = s.polled(music, .empty, now: t0)
    check(s.session(music) == nil, "Music with nothing queued leaves the list")
    let fetched = s.polled(music, .track(title: "Yeni", artist: "", duration: 100, position: 5, playing: false), now: t0)
    check(s.session(music)?.title == "Yeni" && fetched.contains(.fetchArtwork(music, key: "script:Yeni|")), "Polled track appears and asks for its artwork")

    // Pruning.
    s = store()
    _ = s.bridgeReported(item(chrome, playing: true), image: nil, now: t0)
    _ = s.bridgeReported(item(music, playing: true), image: nil, now: t0)
    s.prune(now: t0.addingTimeInterval(16 * 60))
    check(s.session(chrome) == nil, "Background browser tab expires after 15 minutes")
    running.remove(music)
    _ = s.bridgeReported(item(safari, playing: true), image: nil, now: t0)
    s.prune(now: t0)
    check(s.session(music) == nil, "Quit player leaves the list")
}
