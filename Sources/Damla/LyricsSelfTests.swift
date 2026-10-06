import Foundation

/// Checks for lyrics parsing, LRCLIB matching and recovery; no network or user preferences/cache.
func runLyricsSelfTests(_ check: (Bool, String) -> Void) {
    let lrc = """
    [ar:Sezen Aksu]
    [ti:Gidiyorum]
    [00:12.50]Gidiyorum, gidiyorum
    [00:18.00][01:40.25]Nakarat satırı
    [00:24,75]  Virgüllü damga
    [00:30.00]
    bozuk satır
    """
    let lines = Lyrics.parseLRC(lrc)
    check(lines.count == 5 && lines.first?.text == "Gidiyorum, gidiyorum" && lines.last?.time == 100.25, "LRC: tags skipped, repeated stamps expanded, sorted")
    check(lines.contains { $0.time == 24.75 && $0.text == "Virgüllü damga" }, "LRC: comma decimals and padding handled")
    let lyrics = Lyrics(lines: lines)
    check(lyrics.index(at: 5) == nil && lyrics.index(at: 12.5) == 0 && lyrics.index(at: 20) == 1 && lyrics.index(at: 500) == 4,
          "Current line follows the position")

    let track = LRCLib.Track(title: "Şımarık", artist: "Tarkan", album: "Ölürüm Sana", duration: 237.4)
    let url = LRCLib.getURL(track)?.absoluteString ?? ""
    check(url.hasPrefix("https://lrclib.net/api/get?") && url.contains("track_name=%C5%9E%C4%B1mar%C4%B1k")
          && url.contains("album_name=%C3%96l%C3%BCr%C3%BCm%20Sana") && url.contains("duration=237"), "LRCLIB request encodes Turkish text and rounds the length")
    let results: [[String: Any]] = [
        ["duration": 180.0, "syncedLyrics": "[00:01.00]yanlış şarkı"],
        ["duration": 238.0, "plainLyrics": "düz metin"],
        ["duration": 236, "syncedLyrics": "[00:02.00]doğru"]
    ]
    let best = LRCLib.bestMatch(results, duration: 237.4)
    check((best?["syncedLyrics"] as? String) == "[00:02.00]doğru", "Search picks the synced entry within 3 s of the track")
    check(LRCLib.bestMatch([["duration": 100.0, "syncedLyrics": "[00:01.00]x"]], duration: 237) == nil, "No match when lengths differ")
    let instrumental = LRCLib.lyrics(from: ["instrumental": true, "syncedLyrics": NSNull()])
    check(instrumental.instrumental && instrumental.lines.isEmpty && !instrumental.isEmpty, "Instrumental tracks are a result, not a miss")
    runLyricsServiceSelfTests(check)
}

private final class LyricsTestRequest: LyricsRequest {
    let request: URLRequest
    let completion: (Data?, URLResponse?, Error?) -> Void
    private(set) var resumed = false
    private(set) var cancelled = false

    init(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        self.request = request; self.completion = completion
    }
    func resume() { resumed = true }
    func cancel() { cancelled = true }

    /// Deliver even after cancellation to reproduce completions already queued when a track/retry changed.
    func complete(status: Int = 200, body: String? = nil, error: Error? = nil) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)
        completion(body.map { Data($0.utf8) }, response, error)
    }
}

private final class LyricsTestTransport {
    private(set) var requests: [LyricsTestRequest] = []
    func task(_ request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> LyricsRequest {
        let task = LyricsTestRequest(request, completion: completion)
        requests.append(task)
        return task
    }
    func complete(_ index: Int, status: Int = 200, body: String? = nil, error: Error? = nil) {
        guard requests.indices.contains(index) else { return }
        requests[index].complete(status: status, body: body, error: error)
    }
}

private func runLyricsServiceSelfTests(_ check: (Bool, String) -> Void) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Damla-lyrics-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let success = #"{"instrumental":false,"plainLyrics":"Recovered lyrics","syncedLyrics":null,"duration":237}"#
    let oldSuccess = #"{"instrumental":false,"plainLyrics":"Old lyrics","syncedLyrics":null,"duration":237}"#
    let empty = #"{"instrumental":false,"plainLyrics":null,"syncedLyrics":null,"duration":237}"#

    func service(_ fake: LyricsTestTransport, folder: String) -> LyricsService {
        let service = LyricsService(defaults: nil, cacheDirectory: root.appendingPathComponent(folder), transport: fake.task)
        service.enabled = true
        return service
    }
    func show(_ service: LyricsService, title: String = "Şımarık") {
        service.show(title: title, artist: "Tarkan", album: "Ölürüm Sana", duration: 237)
    }
    func cacheCount(_ folder: String) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path).count) ?? 0
    }

    let recoveryTransport = LyricsTestTransport()
    let recovery = service(recoveryTransport, folder: "recovery")
    show(recovery)
    check(recovery.state == .loading && recoveryTransport.requests.count == 1 && recoveryTransport.requests.first?.resumed == true,
          "Lyrics: showing a song starts one request")
    recoveryTransport.complete(0, error: URLError(.notConnectedToInternet))
    show(recovery)
    check(recovery.state == .failed && recovery.lyrics.isEmpty && recoveryTransport.requests.count == 1 && cacheCount("recovery") == 0,
          "Lyrics: offline failure stays retryable, is not cached and does not retry on media updates")
    recovery.retry()
    recovery.retry()
    check(recovery.state == .loading && recoveryTransport.requests.count == 2,
          "Lyrics: a manual retry requests the same song once, without overlapping retries")
    recoveryTransport.complete(0, status: 404)
    check(recovery.state == .loading && recoveryTransport.requests.count == 2 && cacheCount("recovery") == 0,
          "Lyrics: an old same-song completion cannot start a fallback during retry")
    recoveryTransport.complete(1, body: success)
    recoveryTransport.complete(0, body: oldSuccess)
    check(recovery.state == .found && recovery.lyrics.plain == "Recovered lyrics" && cacheCount("recovery") == 1,
          "Lyrics: manual retry recovers and a late old result cannot replace or cache over it")
    let recoveredCacheTransport = LyricsTestTransport()
    let recoveredCache = service(recoveredCacheTransport, folder: "recovery")
    show(recoveredCache)
    check(recoveredCache.state == .found && recoveredCache.lyrics.plain == "Recovered lyrics" && recoveredCacheTransport.requests.isEmpty,
          "Lyrics: the recovered result, not the late response, is persisted")

    show(recovery, title: "Old track")
    show(recovery, title: "New track")
    recoveryTransport.complete(2, status: 404)
    check(recoveryTransport.requests.count == 4 && recoveryTransport.requests[2].cancelled && recovery.state == .loading,
          "Lyrics: changing tracks cancels and ignores the prior request")
    recoveryTransport.complete(3, body: success)
    show(recovery, title: "Disabled track")
    recovery.enabled = false
    recoveryTransport.complete(4, body: success)
    check(recovery.state == .off && recovery.lyrics.isEmpty && recoveryTransport.requests.count == 5 && recoveryTransport.requests[4].cancelled && cacheCount("recovery") == 2,
          "Lyrics: disabling lookup cancels it and ignores its later completion")

    let missingTransport = LyricsTestTransport()
    let missing = service(missingTransport, folder: "missing")
    show(missing)
    missingTransport.complete(0, status: 404)
    check(missing.state == .loading && missingTransport.requests.count == 2 && missingTransport.requests.last?.request.url?.path == "/api/search",
          "Lyrics: a genuine exact miss uses the existing name-search fallback")
    missingTransport.complete(1, body: "[]")
    missing.retry()
    check(missing.state == .missing && missingTransport.requests.count == 2 && cacheCount("missing") == 1,
          "Lyrics: an empty successful search is a cached miss, not a retryable error")
    let cachedTransport = LyricsTestTransport()
    let cached = service(cachedTransport, folder: "missing")
    show(cached)
    check(cached.state == .missing && cachedTransport.requests.isEmpty,
          "Lyrics: a confirmed miss survives reload without another request")
    let emptyTransport = LyricsTestTransport()
    let noWords = service(emptyTransport, folder: "empty")
    show(noWords)
    emptyTransport.complete(0, body: empty)
    check(noWords.state == .missing && cacheCount("empty") == 1,
          "Lyrics: a valid record without lyrics is a confirmed miss")

    for (index, response) in [(503, "Service unavailable"), (200, "not JSON"), (200, "{}"), (200, "[]")].enumerated() {
        let fake = LyricsTestTransport()
        let folder = "error-\(index)"
        let failed = service(fake, folder: folder)
        show(failed)
        fake.complete(0, status: response.0, body: response.1)
        check(failed.state == .failed && fake.requests.count == 1 && cacheCount(folder) == 0,
              "Lyrics: HTTP/malformed response \(index + 1) stays retryable without caching or automatic fallback")
    }
    let badSearchTransport = LyricsTestTransport()
    let badSearch = service(badSearchTransport, folder: "bad-search")
    show(badSearch)
    badSearchTransport.complete(0, status: 404)
    badSearchTransport.complete(1, body: #"[{"instrumental":false,"plainLyrics":"No duration","syncedLyrics":null}]"#)
    check(badSearch.state == .failed && cacheCount("bad-search") == 0,
          "Lyrics: malformed search records cannot be mistaken for a cached miss")
}
