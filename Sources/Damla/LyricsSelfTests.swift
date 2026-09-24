import Foundation

/// Checks for lyrics parsing and LRCLIB matching; no network.
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
}
