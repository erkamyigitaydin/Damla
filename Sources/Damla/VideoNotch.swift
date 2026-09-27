import AppKit
import ApplicationServices
import CoreMedia
import ScreenCaptureKit
import SwiftUI

/// The playing app's video, live under the closed notch. ScreenCaptureKit captures only the video's rectangle of
/// that app's window (straight onto a layer, no copies through SwiftUI); where the video sits is found by motion
/// (the part of the window that keeps changing) and pinned to the page element under it, so it follows scrolling.
/// DRM video (Netflix, Apple TV+) comes through black: the system blanks it for every capture.
final class VideoNotch: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var active = false
    /// Width / height of what is shown.
    @Published private(set) var aspect: CGFloat = 16.0 / 9.0
    @Published var large = UserDefaults.standard.bool(forKey: "videoNotchLarge") {
        didSet { UserDefaults.standard.set(large, forKey: "videoNotchLarge"); if large != oldValue { configureOutput() } }
    }
    @Published private(set) var hovering = false
    /// Why it stopped or could not start; the app shows it as a notice.
    var onProblem: ((String) -> Void)?

    /// Apps that never have a picture to show.
    static let audioOnly: Set<String> = ["com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.iTunes"]
    static func canShow(_ bundleID: String?) -> Bool { bundleID.map { !audioOnly.contains($0) } ?? false }

    private let layers = NSHashTable<CALayer>.weakObjects()
    private var lastSurface: IOSurface?
    private var stream: SCStream?
    private var window: SCWindow?
    private var bundleID: String?
    private var mediaTitle = ""
    /// Where the video is, in the window's own points (top-left origin).
    private var source: CGRect?
    /// The page element the video sits in, and the video's place inside it (0…1), so scrolling moves the crop.
    private var element: AXUIElement?
    private var inner = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var trackTimer: Timer?
    /// The app we asked to build its page tree; told to stop again when the video goes.
    private var treePID: pid_t?
    private let axQueue = DispatchQueue(label: "damla.video.ax", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "damla.video.frames", qos: .userInteractive)
    // Motion probe (frameQueue only).
    private var probing = false
    private var probeGrids: [[Float]] = []
    private var probeColumns = 0
    private var generation = 0

    // MARK: Public

    func attach(_ layer: CALayer) {
        layers.add(layer)
        if let lastSurface { layer.contents = lastSurface }
    }

    func setHovering(_ value: Bool) { if hovering != value { hovering = value } }

    /// Starts on the given app's window, asking for Screen Recording access the first time.
    func start(bundleID: String, title: String) {
        guard Self.canShow(bundleID) else { return }
        MediaService.trace("video start \(bundleID) preflight=\(CGPreflightScreenCaptureAccess())")
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            onProblem?(String(localized: "Videoyu çentikte göstermek için Ekran Kaydı izni gerekiyor: Sistem Ayarları → Gizlilik ve Güvenlik → Ekran ve Sistem Sesi Kaydı"))
            return
        }
        self.bundleID = bundleID
        mediaTitle = title
        Task { await self.open() }
    }

    func stop() {
        generation += 1
        trackTimer?.invalidate(); trackTimer = nil
        let old = stream
        stream = nil; window = nil; element = nil; source = nil; bundleID = nil
        if let pid = treePID {
            treePID = nil
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanFalse)
        }
        frameQueue.async { self.probing = false; self.probeGrids = [] }
        Task { try? await old?.stopCapture() }
        lastSurface = nil
        for layer in layers.allObjects { layer.contents = nil }
        if active { active = false }
        if hovering { hovering = false }
    }

    /// The player moved on: another app (follow it, or stop when it has no picture) or another video (find it again).
    func mediaChanged(bundleID: String?, title: String) {
        guard active || stream != nil else { return }
        if bundleID != self.bundleID {
            guard let bundleID, Self.canShow(bundleID) else { stop(); return }
            stop(); start(bundleID: bundleID, title: title)
        } else if title != mediaTitle {
            mediaTitle = title
            probe()
        }
    }

    /// Playback resumed: a video that was paused while we looked for it can be found now.
    func playbackResumed() { if active && element == nil { probe() } }

    // MARK: Window and stream

    @MainActor private func open() async {
        let token = generation
        guard let bundleID, let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
            onProblem?(String(localized: "Ekran Kaydı izni verilmemiş; izin verdikten sonra Damla’yı yeniden başlat."))
            return
        }
        guard token == generation else { return }
        let candidates = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.height > 120
        }
        // The tab playing the video names the window (Chrome, Safari); otherwise the largest window.
        let key = Self.normalized(mediaTitle).prefix(24)
        let chosen = candidates.first { !key.isEmpty && Self.normalized($0.title ?? "").contains(key) }
            ?? candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let chosen else {
            onProblem?(String(localized: "Videonun penceresi görünmüyor (küçültülmüş ya da başka bir masaüstünde)."))
            return
        }
        window = chosen
        MediaService.trace("video window \(chosen.title ?? "-") \(chosen.frame) of \(candidates.count)")
        let config = SCStreamConfiguration()
        Self.baseConfig(config)
        Self.probeSize(config, window: chosen.frame.size)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: chosen), configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            try await stream.startCapture()
        } catch {
            MediaService.trace("video capture error \(error)")
            onProblem?(String(localized: "Video yakalanamadı: \(error.localizedDescription)"))
            return
        }
        guard token == generation else { try? await stream.stopCapture(); return }
        self.stream = stream
        // Chrome and Electron build their page tree for assistive apps only when asked.
        if let pid = chosen.owningApplication?.processID {
            let app = AXUIElementCreateApplication(pid)
            if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success { treePID = pid }
        }
        probe()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.track() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        trackTimer = timer
    }

    /// Watches the whole window at low resolution for a moment; what changes is the video.
    private func probe() {
        guard let stream, let window else { return }
        element = nil
        let config = SCStreamConfiguration()
        Self.baseConfig(config)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        Self.probeSize(config, window: window.frame.size)
        let token = generation
        frameQueue.async { self.probeGrids = []; self.probing = true }
        stream.updateConfiguration(config) { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, token == self.generation else { return }
            self.frameQueue.async {
                let grids = self.probeGrids, columns = self.probeColumns
                self.probing = false; self.probeGrids = []
                let motion = Self.motionRect(grids, columns: columns)
                DispatchQueue.main.async { self.located(motion: motion, token: token) }
            }
        }
    }

    /// Motion found (normalized to the window) or not: pin it to a page element, then crop to it.
    private func located(motion: CGRect?, token: Int) {
        guard token == generation, let window else { return }
        MediaService.trace("video motion \(motion.map { "\($0)" } ?? "none")")
        let size = window.frame.size
        guard let motion else {
            // Nothing moved (paused, or a still frame): the whole window until playback resumes.
            setSource(CGRect(origin: .zero, size: size))
            return
        }
        let rect = CGRect(x: motion.minX * size.width, y: motion.minY * size.height, width: motion.width * size.width, height: motion.height * size.height)
        setSource(rect)
        let screenRect = rect.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        guard let pid = window.owningApplication?.processID else { return }
        axQueue.async { [weak self] in
            guard let found = Self.element(around: screenRect, pid: pid) else { return }
            let frame = found.frame
            // Snap to the element's edges where the motion nearly reaches them; keep letterbox bars out otherwise.
            var inside = CGRect(x: (screenRect.minX - frame.minX) / frame.width, y: (screenRect.minY - frame.minY) / frame.height,
                                width: screenRect.width / frame.width, height: screenRect.height / frame.height)
            if inside.width > 0.84 { inside.origin.x = 0; inside.size.width = 1 }
            if inside.height > 0.84 { inside.origin.y = 0; inside.size.height = 1 }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                MediaService.trace("video element \(found.frame) inner \(inside)")
                self.element = found.element
                self.inner = inside
                self.track()
            }
        }
    }

    /// Follows the element as the page scrolls or the window resizes.
    private func track() {
        guard let element, let windowID = window?.windowID else { return }
        let inner = self.inner, token = generation
        axQueue.async { [weak self] in
            let frame = Self.frame(of: element)
            let bounds = Self.windowBounds(windowID)
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                guard let frame, frame.width > 20, let bounds else { self.element = nil; self.probe(); return }
                let video = CGRect(x: frame.minX + inner.minX * frame.width, y: frame.minY + inner.minY * frame.height,
                                   width: inner.width * frame.width, height: inner.height * frame.height)
                let local = video.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
                    .intersection(CGRect(origin: .zero, size: bounds.size))
                guard !local.isNull, local.width > 40, local.height > 30 else { return }   // scrolled away: keep the last frame
                if self.source.map({ abs($0.minX - local.minX) + abs($0.minY - local.minY) + abs($0.width - local.width) + abs($0.height - local.height) > 1 }) ?? true {
                    self.setSource(local)
                }
            }
        }
    }

    private func setSource(_ rect: CGRect) {
        source = rect.integral
        let ratio = max(0.5, min(2.6, rect.width / max(rect.height, 1)))
        if abs(ratio - aspect) > 0.01 { aspect = ratio }
        configureOutput()
        if !active { active = true }
    }

    private func configureOutput() {
        guard let stream, let source else { return }
        let config = SCStreamConfiguration()
        Self.baseConfig(config)
        config.sourceRect = source
        // Retina pixels for the drawn size; the larger size gets more.
        let width = large ? 800.0 : 580.0
        config.width = Int(width)
        config.height = Int((width / max(0.5, source.width / max(source.height, 1))).rounded())
        stream.updateConfiguration(config) { _ in }
    }

    private static func baseConfig(_ config: SCStreamConfiguration) {
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.queueDepth = 4
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    }

    private static func probeSize(_ config: SCStreamConfiguration, window: CGSize) {
        // About 4 points per pixel on a big window: cells fine enough to find the video's edges.
        let width = min(720, max(320, Int(window.width / 4)))
        config.width = width
        config.height = max(40, Int(CGFloat(width) * window.height / max(window.width, 1)))
        config.sourceRect = CGRect(origin: .zero, size: window)
    }

    // MARK: Frames

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer else { return }
        if probing {
            if let grid = Self.grid(pixels) { probeColumns = grid.columns; probeGrids.append(grid.cells) }
            return
        }
        guard let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.lastSurface = surface
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for layer in self.layers.allObjects { layer.contents = surface }
            CATransaction.commit()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stop()
            self.onProblem?(String(localized: "Video yakalama durdu (pencere kapandı ya da izin geri alındı)."))
        }
    }

    // MARK: Motion

    static let cell = 8   // probe pixels per grid cell

    /// Mean brightness per 8×8 cell.
    static func grid(_ buffer: CVPixelBuffer) -> (cells: [Float], columns: Int)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        let columns = width / cell, rows = height / cell
        guard columns > 2, rows > 2 else { return nil }
        var cells = [Float](repeating: 0, count: columns * rows)
        for r in 0..<rows {
            for c in 0..<columns {
                var sum = 0
                for y in stride(from: r * cell, to: r * cell + cell, by: 2) {
                    let line = base + y * row
                    for x in stride(from: c * cell, to: c * cell + cell, by: 2) {
                        let p = line + x * 4   // BGRA
                        sum += Int(p[0]) + Int(p[1]) * 2 + Int(p[2])
                    }
                }
                cells[r * columns + c] = Float(sum) / Float(16 * 4)
            }
        }
        return (cells, columns)
    }

    /// The largest block of cells that kept changing, normalized to the frame; nil when nothing did.
    static func motionRect(_ grids: [[Float]], columns: Int) -> CGRect? {
        guard grids.count >= 4, columns > 0, let count = grids.first?.count, grids.allSatisfy({ $0.count == count }) else { return nil }
        let rows = count / columns
        var changes = [Int](repeating: 0, count: count)
        for (a, b) in zip(grids, grids.dropFirst()) {
            for i in 0..<count where abs(a[i] - b[i]) > 3 { changes[i] += 1 }
        }
        let needed = max(2, (grids.count - 1) / 4)
        let hot = changes.map { $0 >= needed }
        var seen = [Bool](repeating: false, count: count)
        var best: (size: Int, minC: Int, minR: Int, maxC: Int, maxR: Int)?
        for start in 0..<count where hot[start] && !seen[start] {
            var stack = [start]; seen[start] = true
            var size = 0, minC = columns, minR = rows, maxC = 0, maxR = 0
            while let i = stack.popLast() {
                size += 1
                let r = i / columns, c = i % columns
                minC = min(minC, c); maxC = max(maxC, c); minR = min(minR, r); maxR = max(maxR, r)
                // Neighbours two cells away too, so a dark, still patch inside the video does not split it.
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-2, 0), (2, 0), (0, -2), (0, 2)] {
                    let nr = r + dr, nc = c + dc
                    guard nr >= 0, nr < rows, nc >= 0, nc < columns else { continue }
                    let n = nr * columns + nc
                    if hot[n] && !seen[n] { seen[n] = true; stack.append(n) }
                }
            }
            let area = (maxC - minC + 1) * (maxR - minR + 1)
            if area >= 12, best.map({ area > ($0.maxC - $0.minC + 1) * ($0.maxR - $0.minR + 1) }) ?? true {
                best = (size, minC, minR, maxC, maxR)
            }
        }
        guard let best else { return nil }
        return CGRect(x: CGFloat(best.minC) / CGFloat(columns), y: CGFloat(best.minR) / CGFloat(rows),
                      width: CGFloat(best.maxC - best.minC + 1) / CGFloat(columns), height: CGFloat(best.maxR - best.minR + 1) / CGFloat(rows))
    }

    // MARK: Accessibility

    /// The page element that best matches the moving area (a <video> or its player box).
    static func element(around rect: CGRect, pid: pid_t) -> (element: AXUIElement, frame: CGRect)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var windows: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return nil }
        var best: (element: AXUIElement, frame: CGRect, score: CGFloat)?
        var visited = 0
        func walk(_ e: AXUIElement, depth: Int) {
            visited += 1
            guard visited < 6000, depth < 50 else { return }
            if let frame = frame(of: e), frame.width > 60, frame.height > 40 {
                let overlap = frame.intersection(rect)
                if overlap.isNull || overlap.width < 1 { return }   // children sit inside their parent's box
                let union = frame.width * frame.height + rect.width * rect.height - overlap.width * overlap.height
                let score = overlap.width * overlap.height / union
                // Ties go to the deeper element: the video itself rather than the page around it.
                if score > 0.55, score >= (best?.score ?? 0) - 0.02 { best = (e, frame, score) }
            }
            var children: AnyObject?
            guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &children) == .success,
                  let kids = children as? [AXUIElement] else { return }
            for kid in kids { walk(kid, depth: depth + 1) }
        }
        for window in list where frame(of: window)?.intersects(rect) ?? false { walk(window, depth: 0) }
        return best.map { ($0.element, $0.frame) }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var position: AnyObject?, size: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    static func windowBounds(_ id: CGWindowID) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - View

/// The video under the closed notch, with its controls on hover: close, play/pause, bigger/smaller, go to the app.
struct VideoNotchView: View {
    @ObservedObject var model: AppState
    @ObservedObject var video: VideoNotch
    @ObservedObject var media: MediaService
    let size: CGSize
    var body: some View {
        ZStack {
            VideoLayer(video: video)
            if video.hovering {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                HStack(spacing: 10) {
                    control("xmark", "Kapat") { withAnimation(Theme.quick) { model.stopVideo() } }
                    Spacer(minLength: 0)
                    control(media.playing ? "pause.fill" : "play.fill", media.playing ? "Duraklat" : "Oynat") { media.command("playpause") }
                    control(video.large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                            video.large ? "Küçült" : "Büyüt") { video.large.toggle() }
                    control("arrow.up.forward.app", "Uygulamaya git") { media.activateSource() }
                }
                .padding(8)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: video.large ? 14 : 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { media.command("playpause") }
        .animation(Theme.quick, value: video.hovering)
    }
    private func control(_ icon: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }.buttonStyle(GlassCircleStyle()).help(label)
    }
}

/// A plain layer the capture draws into; it never passes through SwiftUI.
struct VideoLayer: NSViewRepresentable {
    let video: VideoNotch
    func makeNSView(context: Context) -> NSView {
        let view = VideoLayerView()
        video.attach(view.videoLayer)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class VideoLayerView: NSView {
    let videoLayer = CALayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.contentsGravity = .resizeAspect
        videoLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
