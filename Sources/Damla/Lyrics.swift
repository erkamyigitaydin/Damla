import Foundation
import CryptoKit

/// One timed line of synced lyrics.
struct LyricLine: Equatable, Codable {
    let time: Double     // seconds from the start of the track
    let text: String
}

/// Lyrics as LRCLIB returns them: synced lines when someone timed them, otherwise plain text.
struct Lyrics: Equatable, Codable {
    var lines: [LyricLine] = []
    var plain: String = ""
    var instrumental = false
    var isEmpty: Bool { lines.isEmpty && plain.isEmpty && !instrumental }

    /// The line playing at `position`: the last one that started, nil before the first.
    func index(at position: Double) -> Int? {
        guard let first = lines.first, position >= first.time else { return nil }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= position { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Parses LRC: "[mm:ss.xx]text", several stamps per line allowed, tags such as "[ar:…]" skipped.
    static func parseLRC(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw), stamps: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseStamp(tag) { stamps.append(time) } else if stamps.isEmpty { break }
                rest = rest[rest.index(after: close)...]
            }
            guard !stamps.isEmpty else { continue }
            let words = rest.trimmingCharacters(in: .whitespaces)
            for time in stamps { lines.append(LyricLine(time: time, text: words)) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func parseStamp<S: StringProtocol>(_ tag: S) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")),
              minutes >= 0, seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }
}

/// Talks to lrclib.net, a free and open lyrics database. Only the track's title, artist, album and length
/// are sent, and only when the user turned lyrics on.
enum LRCLib {
    struct Track: Equatable { let title: String, artist: String, album: String, duration: Double }

    static func getURL(_ track: Track) -> URL? {
        var parts = URLComponents(string: "https://lrclib.net/api/get")
        parts?.queryItems = [URLQueryItem(name: "track_name", value: track.title), URLQueryItem(name: "artist_name", value: track.artist),
                             URLQueryItem(name: "album_name", value: track.album), URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))]
        return parts?.url
    }

    static func searchURL(_ track: Track) -> URL? {
        var parts = URLComponents(string: "https://lrclib.net/api/search")
        parts?.queryItems = [URLQueryItem(name: "track_name", value: track.title), URLQueryItem(name: "artist_name", value: track.artist)]
        return parts?.url
    }

    static func lyrics(from object: [String: Any]) -> Lyrics {
        var lyrics = Lyrics()
        lyrics.instrumental = object["instrumental"] as? Bool ?? false
        if let synced = object["syncedLyrics"] as? String { lyrics.lines = Lyrics.parseLRC(synced) }
        lyrics.plain = (object["plainLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return lyrics
    }

    /// From search results, the entry whose length is closest to the track (within 3 s), synced ones first.
    static func bestMatch(_ results: [[String: Any]], duration: Double) -> [String: Any]? {
        let close = results.filter { abs(($0["duration"] as? Double ?? ($0["duration"] as? Int).map(Double.init) ?? -100) - duration) <= 3 }
        return close.first { ($0["syncedLyrics"] as? String)?.isEmpty == false } ?? close.first
    }

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 8)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        request.setValue("Damla/\(version) (https://github.com/erkamyigitaydin/Damla)", forHTTPHeaderField: "User-Agent")   // LRCLIB asks clients to name themselves
        return request
    }
}

/// Lyrics for whatever is shown on Özet, fetched once per track and cached on disk (misses too, briefly).
final class LyricsService: ObservableObject {
    enum State: Equatable { case off, idle, loading, found, missing }
    @Published private(set) var state: State
    @Published private(set) var lyrics = Lyrics()
    @Published var enabled = UserDefaults.standard.bool(forKey: "lyricsEnabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "lyricsEnabled")
            if enabled { state = .idle; if let track = pending { load(track) } } else { state = .off; lyrics = Lyrics(); current = nil }
        }
    }
    private var current: LRCLib.Track?
    private var pending: LRCLib.Track?
    private var task: URLSessionDataTask?
    private static var folder: URL { DiskStore.directory.appendingPathComponent("lyrics", isDirectory: true) }

    init() { state = UserDefaults.standard.bool(forKey: "lyricsEnabled") ? .idle : .off }

    /// Called when the shown track changes. Browsers' videos and live streams have no song to look up.
    func show(title: String, artist: String, album: String, duration: Double) {
        let track = LRCLib.Track(title: title, artist: artist, album: album, duration: duration)
        guard track != current else { return }
        pending = track
        guard enabled else { return }
        load(track)
    }

    /// A new song started but its length is not known yet: drop the old song's lyrics now rather than show them
    /// over the new one while waiting.
    func expecting(title: String, artist: String) {
        guard enabled, current?.title != title || current?.artist != artist else { return }
        task?.cancel(); current = nil; lyrics = Lyrics(); state = .loading
    }

    private func load(_ track: LRCLib.Track) {
        current = track; task?.cancel(); lyrics = Lyrics()
        guard !track.title.isEmpty, !track.artist.isEmpty, track.duration > 30, track.duration.isFinite else { state = .missing; return }
        if let cached = Self.cached(track) { lyrics = cached; state = cached.isEmpty ? .missing : .found; return }
        state = .loading
        fetch(LRCLib.getURL(track), track: track, fallback: true)
    }

    private func fetch(_ url: URL?, track: LRCLib.Track, fallback: Bool) {
        guard let url else { finish(Lyrics(), for: track); return }
        task = URLSession.shared.dataTask(with: LRCLib.request(url)) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            DispatchQueue.main.async {
                guard let self, self.current == track else { return }
                if status == 200, let found = object as? [String: Any] {
                    self.finish(LRCLib.lyrics(from: found), for: track)
                } else if status == 200, let results = object as? [[String: Any]], let best = LRCLib.bestMatch(results, duration: track.duration) {
                    self.finish(LRCLib.lyrics(from: best), for: track)
                } else if fallback && (status == 404 || status == 200) {
                    self.fetch(LRCLib.searchURL(track), track: track, fallback: false)   // exact match missed: search by name
                } else {
                    self.finish(Lyrics(), for: track, cache: status == 404 || status == 200)   // network errors are not remembered
                }
            }
        }
        task?.resume()
    }

    private func finish(_ found: Lyrics, for track: LRCLib.Track, cache: Bool = true) {
        lyrics = found
        state = found.isEmpty ? .missing : .found
        if cache { Self.store(found, for: track) }
    }

    // MARK: Disk cache (one small JSON per track, keyed by a hash of the track)

    private static func key(_ track: LRCLib.Track) -> String {
        let digest = SHA256.hash(data: Data("\(track.title)|\(track.artist)|\(Int(track.duration))".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func cached(_ track: LRCLib.Track) -> Lyrics? {
        let file = folder.appendingPathComponent(key(track) + ".json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path), let data = try? Data(contentsOf: file),
              let lyrics = try? JSONDecoder().decode(Lyrics.self, from: data) else { return nil }
        // A miss is retried after a week: someone may have added the lyrics since.
        if lyrics.isEmpty, let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) > 7 * 24 * 3600 { return nil }
        return lyrics
    }

    private static func store(_ lyrics: Lyrics, for track: LRCLib.Track) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(lyrics) else { return }
        try? data.write(to: folder.appendingPathComponent(key(track) + ".json"), options: .atomic)
    }
}
