import AppKit
import ApplicationServices
import CoreMedia
import ScreenCaptureKit
import SwiftUI

/// The browser's video, live under the closed notch. A page only keeps drawing while its window can be seen, so a
/// capture of the tab freezes as soon as the browser goes behind other windows. Picture-in-picture is the one
/// surface browsers keep drawing in the background, so Damla puts the video into the browser's own PiP window,
/// parks that window right under the notch (hidden behind the notch's video box, which is drawn on top of it), and
/// shows a capture of just that window. Controls go to the video element through JavaScript.
///
/// Needs, once: Screen Recording (the capture), Automation for the browser plus its "Allow JavaScript from Apple
/// Events" setting (finding and driving the video), Accessibility (already granted for the media keys).
final class VideoNotch: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var active = false
    /// Size of the browser's PiP window: the small video matches it, since the window hides behind it.
    @Published private(set) var pipSize = CGSize(width: 336, height: 189)
    @Published var large = UserDefaults.standard.bool(forKey: "videoNotchLarge") {
        didSet { UserDefaults.standard.set(large, forKey: "videoNotchLarge") }
    }
    @Published private(set) var hovering = false
    @Published private(set) var starting = false
    /// Why it stopped or could not start; the app shows it as a notice.
    var onProblem: ((String) -> Void)?
    /// Where the video box is drawn right now (screen points, top-left origin); nil while it is not shown
    /// (panel open, full screen), when the PiP window waits off screen.
    var dockTarget: (() -> CGRect?)?

    /// Chromium browsers that take `execute javascript` over Apple Events.
    static let browsers: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser",
                                        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "org.chromium.Chromium"]
    static func canShow(_ bundleID: String?) -> Bool { bundleID.map(browsers.contains) ?? false }

    private let layers = NSHashTable<CALayer>.weakObjects()
    private var stream: SCStream?
    private var bundleID: String?
    private var pid: pid_t = 0
    /// "tab id X of window id Y" of the tab whose video is in PiP.
    private var tabRef: String?
    private var pipWindowID: CGWindowID = 0
    private var pipElement: AXUIElement?
    private var dockTimer: Timer?
    /// A clear window over the parked PiP window that takes the pointer. The notch lets the pointer through until it
    /// is over its shape, so the first move would reach the PiP window and Chrome would draw its own controls into
    /// the picture. Barely-there alpha takes the events; a non-opaque window does not make Chrome stop drawing.
    private lazy var shield: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.02)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)   // above PiP, below the notch
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }()
    private var treeRequested = false
    private var generation = 0
    private let scriptQueue = DispatchQueue(label: "damla.video.script", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "damla.video.frames", qos: .userInteractive)

    // MARK: Public

    func attach(_ layer: CALayer) { layers.add(layer) }
    func setHovering(_ value: Bool) { if hovering != value { hovering = value } }

    func start(bundleID: String) {
        guard Self.canShow(bundleID), !starting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            onProblem?(String(localized: "Videoyu çentikte göstermek için Ekran Kaydı izni gerekiyor: Sistem Ayarları → Gizlilik ve Güvenlik → Ekran ve Sistem Sesi Kaydı"))
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        stop()
        let token = generation
        self.bundleID = bundleID
        pid = app.processIdentifier
        starting = true
        // Chrome builds its page tree for assistive apps only when asked; ask now, it takes a moment.
        let axApp = AXUIElementCreateApplication(pid)
        if AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success { treeRequested = true }
        let pid = self.pid
        scriptQueue.async { [weak self] in
            let result = Self.enterPictureInPicture(bundleID: bundleID, pid: pid, axApp: axApp)
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.starting = false
                switch result {
                case .failure(let problem): MediaService.trace("video failed: \(problem.message)"); self.stop(); self.onProblem?(problem.message)
                case .success(let pip): Task { await self.capture(pip, token: token) }
                }
            }
        }
    }

    /// `waiting`: on quit, the video has to leave PiP before the app is gone.
    func stop(waiting: Bool = false) {
        generation += 1
        dockTimer?.invalidate(); dockTimer = nil
        shield.orderOut(nil)
        let old = stream
        stream = nil
        Task { try? await old?.stopCapture() }
        if let tabRef, let bundleID {
            runJavaScript("document.pictureInPictureElement && document.exitPictureInPicture(); 1", tab: tabRef, bundleID: bundleID)
            if waiting { scriptQueue.sync {} }
        }
        if treeRequested {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanFalse)
            treeRequested = false
        }
        tabRef = nil; bundleID = nil; pipElement = nil; pipWindowID = 0
        for layer in layers.allObjects { layer.contents = nil }
        if active { active = false }
        if hovering { hovering = false }
        if starting { starting = false }
    }

    func togglePlayback() {
        guard let tabRef, let bundleID else { return }
        runJavaScript("(()=>{const v=document.pictureInPictureElement; if(!v) return 0; if(v.paused) v.play(); else v.pause(); return 1})()", tab: tabRef, bundleID: bundleID)
    }

    /// Back to the tab: the video leaves PiP and the browser comes forward on it.
    func showTab() {
        guard let tabRef, let bundleID else { return }
        let window = tabRef.components(separatedBy: " of ").last ?? ""
        stop()
        scriptQueue.async {
            _ = Self.appleScript("""
            tell application id "\(bundleID)"
                set index of \(window) to 1
                activate
            end tell
            """)
        }
    }

    // MARK: Entering PiP

    struct Problem: Error { let message: String }
    struct PipWindow { let id: CGWindowID; let element: AXUIElement; let frame: CGRect; let tab: String }

    /// Marks the playing video, presses it through Accessibility (which counts as a click, the gesture PiP needs)
    /// and waits for the PiP window. Runs off the main thread: Apple Events and the page tree can take a moment.
    private static func enterPictureInPicture(bundleID: String, pid: pid_t, axApp: AXUIElement) -> Result<PipWindow, Problem> {
        let mark = """
        (()=>{const all=[...document.querySelectorAll('video')].filter(v=>v.readyState>=2&&v.videoWidth>0);
        const big=(a,b)=>b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight;
        const playing=all.filter(v=>!v.paused).sort(big), started=all.filter(v=>v.currentTime>1).sort(big);
        const v=document.pictureInPictureElement||playing[0]||started[0];
        if(!v) return 'none';
        document.querySelectorAll('.damla-pip').forEach(e=>e.classList.remove('damla-pip'));
        v.classList.add('damla-pip');
        const arm=e=>{if(e.target!==v) return; e.stopImmediatePropagation(); e.preventDefault();
        window.removeEventListener('click',arm,true); v.requestPictureInPicture().catch(()=>{});};
        window.addEventListener('click',arm,true); return 'ok';})()
        """
        let js = escaped(mark)
        // Active tabs first; a video in a background tab is brought to the front of its window, since only the
        // front tab of a window is in the page tree.
        let find = """
        tell application id "\(bundleID)"
            set lastError to ""
            repeat with w in windows
                try
                    set t to active tab of w
                    if (execute t javascript "\(js)") is "ok" then return "tab id " & (id of t) & " of window id " & (id of w)
                on error message
                    set lastError to message
                end try
            end repeat
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    try
                        if (execute t javascript "\(js)") is "ok" then
                            set active tab index of w to i
                            return "tab id " & (id of t) & " of window id " & (id of w)
                        end if
                    on error message
                        set lastError to message
                    end try
                end repeat
            end repeat
            return "none:" & lastError
        end tell
        """
        let found = appleScript(find)
        MediaService.trace("video find -> \(found.value ?? "nil") error=\(found.error ?? "-") code=\(found.code.map(String.init) ?? "-")")
        guard let tab = found.value, tab.hasPrefix("tab id") else {
            let text = (found.value ?? "") + " " + (found.error ?? "")
            if text.localizedCaseInsensitiveContains("JavaScript") {
                return .failure(Problem(message: String(localized: "Tarayıcıda Görünüm → Geliştirici → “Apple Events’ten JavaScript’e izin ver”i aç, sonra yeniden dene.")))
            }
            if found.code == -1743 {
                return .failure(Problem(message: String(localized: "Damla’nın tarayıcıyı denetlemesine izin ver: Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon")))
            }
            return .failure(Problem(message: String(localized: "Oynayan bir video bulunamadı (videonun sekmesi açık ve oynuyor olmalı).")))
        }
        let existing = Set(floatingWindows(pid: pid).map(\.id))
        // The page tree fills in over a second or so after it is first asked for.
        var element: AXUIElement?
        for _ in 0..<8 {
            element = findElement(in: axApp, domClass: "damla-pip")
            if element != nil { break }
            Thread.sleep(forTimeInterval: 0.35)
        }
        MediaService.trace("video element \(element == nil ? "missing" : "found")")
        guard let element, AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            return .failure(Problem(message: String(localized: "Videoya ulaşılamadı; tarayıcının penceresi açık olmalı.")))
        }
        for _ in 0..<15 {
            Thread.sleep(forTimeInterval: 0.2)
            let windows = floatingWindows(pid: pid)
            guard let window = windows.first(where: { !existing.contains($0.id) }) ?? windows.first,
                  let axWindow = axWindow(in: axApp, matching: window.frame) else { continue }
            return .success(PipWindow(id: window.id, element: axWindow, frame: window.frame, tab: tab))
        }
        return .failure(Problem(message: String(localized: "Tarayıcı videoyu resim içinde resim moduna almadı.")))
    }

    // MARK: Capture and docking

    @MainActor private func capture(_ pip: PipWindow, token: Int) async {
        MediaService.trace("video pip window \(pip.id) \(pip.frame) tab \(pip.tab)")
        tabRef = pip.tab
        pipElement = pip.element
        pipWindowID = pip.id
        pipSize = pip.frame.size
        active = true   // the notch grows its video box now, so the window has somewhere to hide
        dock()
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == pip.id }) else {
            stop(); onProblem?(String(localized: "Video penceresi yakalanamadı.")); return
        }
        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.queueDepth = 4
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        // The window's own pixels: the layer scales them to the drawn size (a capture larger than the window is not
        // scaled up, it comes back padded).
        let filter = SCContentFilter(desktopIndependentWindow: window)
        config.width = Int((pip.frame.width * CGFloat(filter.pointPixelScale)).rounded())
        config.height = Int((pip.frame.height * CGFloat(filter.pointPixelScale)).rounded())
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            try await stream.startCapture()
        } catch {
            stop(); onProblem?(String(localized: "Video yakalanamadı: \(error.localizedDescription)")); return
        }
        guard token == generation else { try? await stream.stopCapture(); return }
        self.stream = stream
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.dock() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        dockTimer = timer
    }

    /// Keeps the PiP window behind the notch's video box, or off screen while the box is not drawn. A window
    /// fully off screen stops being drawn, which is fine then: nothing shows it.
    private func dock() {
        guard let element = pipElement else { return }
        guard Self.windowExists(pipWindowID) else { stop(); return }   // PiP closed from the page, or the tab went away
        guard let frame = Self.frame(of: element) else { return }
        if frame.width > 50, abs(frame.width - pipSize.width) > 1 || abs(frame.height - pipSize.height) > 1 { pipSize = frame.size }
        let target: CGPoint
        if let box = dockTarget?() {
            target = CGPoint(x: (box.midX - frame.width / 2).rounded(), y: (box.midY - frame.height / 2).rounded())
            // Over the whole box (the PiP window sits inside it, a few points lower when the menu bar pushes it).
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            let cover = NSRect(x: box.minX, y: primaryTop - box.maxY - 12, width: box.width, height: box.height + 12)
            if shield.frame != cover { shield.setFrame(cover, display: false) }
            if !shield.isVisible { shield.orderFrontRegardless() }
        } else {
            let left = NSScreen.screens.map(\.frame.minX).min() ?? 0
            target = CGPoint(x: left - frame.width - 4000, y: 200)
            if shield.isVisible { shield.orderOut(nil) }
        }
        // The system keeps windows below the menu bar, so a few points off at the top are expected; the notch's
        // rim covers them.
        guard abs(frame.minX - target.x) > 2 || abs(frame.minY - target.y) > 8 else { return }
        var point = target
        if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for layer in self.layers.allObjects { layer.contents = surface }
            CATransaction.commit()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stop()
        }
    }

    // MARK: Helpers

    private func runJavaScript(_ source: String, tab: String, bundleID: String) {
        let script = "tell application id \"\(bundleID)\" to execute \(tab) javascript \"\(Self.escaped(source))\""
        scriptQueue.async { _ = Self.appleScript(script) }
    }

    static func escaped(_ source: String) -> String {
        source.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
    }

    static func appleScript(_ source: String) -> (value: String?, error: String?, code: Int?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (result?.stringValue, error?[NSAppleScript.errorMessage] as? String, error?[NSAppleScript.errorNumber] as? Int)
    }

    /// The app's windows above the normal level (a PiP window floats), newest first.
    static func floatingWindows(pid: pid_t) -> [(id: CGWindowID, frame: CGRect)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info -> (id: CGWindowID, frame: CGRect)? in
            guard let owner = info[kCGWindowOwnerPID as String] as? Int, pid_t(owner) == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer > 0, layer < 20,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  bounds.width > 120, bounds.height > 60 else { return nil }
            return (CGWindowID(number), bounds)
        }.sorted { $0.id > $1.id }
    }

    /// Still there (on screen or parked off it): gone once the PiP closes.
    static func windowExists(_ id: CGWindowID) -> Bool {
        guard id != 0, let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first else { return false }
        return (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
    }

    static func axWindow(in app: AXUIElement, matching frame: CGRect) -> AXUIElement? {
        var windows: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return nil }
        return list.first { window in
            guard let f = Self.frame(of: window) else { return false }
            return abs(f.minX - frame.minX) < 2 && abs(f.minY - frame.minY) < 2 && abs(f.width - frame.width) < 2
        }
    }

    static func findElement(in app: AXUIElement, domClass: String) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(app, 1)
        var windows: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return nil }
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            visited += 1
            guard visited < 12000, depth < 80 else { return nil }
            var classes: AnyObject?
            if AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &classes) == .success,
               (classes as? [String])?.contains(domClass) == true { return element }
            var children: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                  let kids = children as? [AXUIElement] else { return nil }
            for kid in kids { if let hit = walk(kid, depth: depth + 1) { return hit } }
            return nil
        }
        for window in list { if let hit = walk(window, depth: 0) { return hit } }
        return nil
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
}

// MARK: - View

/// The video under the closed notch, with its controls on hover: close, play/pause, bigger/smaller, back to the tab.
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
                HStack(spacing: 10) {
                    control("xmark", "Kapat") { model.stopVideo() }
                    Spacer(minLength: 0)
                    control(media.playing ? "pause.fill" : "play.fill", media.playing ? "Duraklat" : "Oynat") { video.togglePlayback() }
                    control(video.large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                            video.large ? "Küçült" : "Büyüt") { video.large.toggle() }
                    control("arrow.up.forward.app", "Sekmeye dön") { video.showTab() }
                }
                .padding(8)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: video.large ? 14 : 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { video.togglePlayback() }
        // Only a fade: the buttons never move under the pointer.
        .animation(.easeOut(duration: 0.15), value: video.hovering)
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
