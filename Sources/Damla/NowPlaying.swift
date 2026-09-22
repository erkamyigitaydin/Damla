import AppKit

/// Reads the system-wide "Now Playing" state (Music, Spotify, Safari/Chrome tabs, Podcasts…) through the
/// bundled MediaRemote adapter: a tiny framework loaded into `/usr/bin/perl`, which is entitled to use
/// the private MediaRemote framework where a third-party app is not (macOS 15.4+). The adapter prints
/// JSON lines; this class keeps the merged state and hands out a snapshot on every change.
final class NowPlayingBridge {
    struct Item: Equatable {
        var title: String
        var artist: String
        var album: String
        var bundleID: String
        var playing: Bool
        var duration: Double
        var elapsed: Double
        var timestamp: Date
        var playbackRate: Double
        var artworkKey: String   // cheap identity for the artwork payload, so it is decoded once
    }

    private static let folder = Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
    static var scriptURL: URL? { folder?.appendingPathComponent("mediaremote-adapter.pl") }
    static var frameworkURL: URL? { folder?.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true) }
    static var testClientURL: URL? { folder?.appendingPathComponent("MediaRemoteAdapterTestClient") }
    static var isBundled: Bool {
        guard let script = scriptURL, let framework = frameworkURL else { return false }
        return FileManager.default.fileExists(atPath: script.path) && FileManager.default.fileExists(atPath: framework.path)
    }

    var onUpdate: ((Item?, NSImage?) -> Void)?   // called on the main thread; image only when the artwork changed
    private var process: Process?
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private var lastArtworkKey = ""
    private var restarts = 0
    private var stopped = false
    private let queue = DispatchQueue(label: "app.damla.nowplaying", qos: .utility)
    private static let iso = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    /// Runs the adapter's self-test (exit 0 means the entitlement trick still works on this macOS).
    func test(completion: @escaping (Bool) -> Void) {
        guard let script = Self.scriptURL, let framework = Self.frameworkURL, let client = Self.testClientURL else { completion(false); return }
        queue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            task.arguments = [script.path, framework.path, client.path, "test"]
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            do { try task.run() } catch { DispatchQueue.main.async { completion(false) }; return }
            task.waitUntilExit()
            let ok = task.terminationStatus == 0
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func start() {
        stopped = false
        launchStream()
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    private func launchStream() {
        guard let script = Self.scriptURL, let framework = Self.frameworkURL else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [script.path, framework.path, "stream", "--debounce=80"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async { self.consume(data) }
        }
        task.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            guard let self, !self.stopped, self.restarts < 5 else { return }
            self.restarts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.launchStream() }
        }
        do { try task.run(); process = task } catch { NSLog("Damla: now playing adapter failed to start: %@", error.localizedDescription) }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return }
        let isDiff = object["diff"] as? Bool ?? false
        if isDiff {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload.filter { !($0.value is NSNull) }
        }
        publish()
    }

    private func publish() {
        guard let title = state["title"] as? String, let bundleID = state["bundleIdentifier"] as? String else {
            lastArtworkKey = ""
            DispatchQueue.main.async { [weak self] in self?.onUpdate?(nil, nil) }
            return
        }
        let artworkData = state["artworkData"] as? String ?? ""
        let artworkKey = artworkData.isEmpty ? "" : "\(artworkData.count):\(artworkData.prefix(48))"
        var image: NSImage?
        var artworkChanged = false
        if artworkKey != lastArtworkKey {
            lastArtworkKey = artworkKey
            artworkChanged = true
            if let decoded = Data(base64Encoded: artworkData) { image = NSImage(data: decoded) }
        }
        let timestamp = (state["timestamp"] as? String).flatMap { Self.isoFractional.date(from: $0) ?? Self.iso.date(from: $0) } ?? Date()
        let playing = state["playing"] as? Bool ?? false
        let item = Item(title: title,
                        artist: state["artist"] as? String ?? "",
                        album: state["album"] as? String ?? "",
                        bundleID: bundleID,
                        playing: playing,
                        duration: (state["duration"] as? NSNumber)?.doubleValue ?? 0,
                        elapsed: (state["elapsedTime"] as? NSNumber)?.doubleValue ?? 0,
                        timestamp: timestamp,
                        playbackRate: (state["playbackRate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0),
                        artworkKey: artworkKey)
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(item, artworkChanged ? image : nil) }
    }

    // MARK: Commands (MediaRemote command IDs from the adapter's table)

    enum Command: Int { case play = 0, pause = 1, togglePlayPause = 2, stop = 3, next = 4, previous = 5 }

    func send(_ command: Command) { run(["send", String(command.rawValue)]) }
    func seek(to seconds: Double) { run(["seek", String(Int(max(0, seconds) * 1_000_000))]) }

    private func run(_ arguments: [String]) {
        guard let script = Self.scriptURL, let framework = Self.frameworkURL else { return }
        queue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            task.arguments = [script.path, framework.path] + arguments
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }
}
