import AVFoundation
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Film looks

/// How the viewfinder and the printed photo look. The preview applies the same Core Image filters live.
enum FilmLook: String, CaseIterable {
    case nostalgia, mono, natural
    var title: String {
        switch self {
        case .nostalgia: return String(localized: "Nostalji")
        case .mono: return String(localized: "Siyah beyaz")
        case .natural: return String(localized: "Doğal")
        }
    }
    var icon: String {
        switch self { case .nostalgia: return "sun.haze"; case .mono: return "circle.lefthalf.filled"; case .natural: return "camera" }
    }
    var next: FilmLook { let all = Self.allCases; return all[(all.firstIndex(of: self)! + 1) % all.count] }

    /// Filters for the live preview layer.
    func previewFilters() -> [CIFilter] {
        switch self {
        case .nostalgia:
            // Faded instant-film colour, pulled back a little so faces keep their warmth.
            return [CIFilter(name: "CIPhotoEffectInstant"),
                    CIFilter(name: "CIColorControls", parameters: [kCIInputContrastKey: 1.08, kCIInputSaturationKey: 1.25, kCIInputBrightnessKey: -0.05]),
                    CIFilter(name: "CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5600, y: 0)]),
                    CIFilter(name: "CIVignette", parameters: [kCIInputIntensityKey: 0.6, kCIInputRadiusKey: 1.6])].compactMap { $0 }
        case .mono: return [CIFilter(name: "CIPhotoEffectTonal"), CIFilter(name: "CIVignette", parameters: [kCIInputIntensityKey: 0.5, kCIInputRadiusKey: 1.8])].compactMap { $0 }
        case .natural: return []
        }
    }

    /// The printed photo: the same look plus film grain, so the card feels like a print, not a screenshot.
    func develop(_ image: CIImage) -> CIImage {
        var output = image
        for filter in previewFilters() {
            filter.setValue(output, forKey: kCIInputImageKey)
            output = filter.outputImage ?? output
        }
        guard self != .natural, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return output }
        let grain = noise.cropped(to: output.extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.07),
            ])
        return grain.composited(over: output).cropped(to: output.extent)
    }
}

// MARK: - Camera

/// The camera behind the Ayna page. It runs only while the page is on screen and keeps the newest frame so
/// the shutter can take it without a separate photo pipeline.
final class MirrorCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// One camera for the app: its session is set up once, so opening the page again only has to start it.
    static let shared = MirrorCamera()
    enum State { case starting, running, denied, unavailable }
    @Published private(set) var state: State = .starting
    /// A countdown or a print is under way: the panel stays open until the card has landed.
    @Published var busy = false
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.local.damla.mirror")
    private var configured = false
    private var wanted = false
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    func start() {
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.run() : (self.state = .denied) }
            }
        default: state = .denied
        }
    }

    func stop() {
        wanted = false
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.lock.lock(); self.latest = nil; self.lock.unlock()
        }
    }

    private func run() {
        guard wanted else { return }
        queue.async {
            if !self.configured {
                guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                self.session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(output) { self.session.addOutput(output) }
                self.session.commitConfiguration()
                self.configured = true
            }
            // The page may have closed while access was being asked.
            guard self.wanted else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); latest = buffer; lock.unlock()
    }

    /// The newest frame, mirrored like the preview and cropped to a square, in the chosen look.
    func snapshot(look: FilmLook) -> CGImage? {
        lock.lock(); let buffer = latest; lock.unlock()
        guard let buffer else { return nil }
        var image = CIImage(cvPixelBuffer: buffer)
        image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -image.extent.width, y: 0))
        let side = min(image.extent.width, image.extent.height)
        let square = CGRect(x: image.extent.midX - side / 2, y: image.extent.midY - side / 2, width: side, height: side)
        image = image.cropped(to: square).transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))
        image = look.develop(image)
        return MirrorAlbum.context.createCGImage(image, from: CGRect(x: 0, y: 0, width: side, height: side))
    }

    deinit { if session.isRunning { session.stopRunning() } }
}

// MARK: - Album

/// Printed cards, saved as PNG files in ~/Pictures/Damla. The page shows the newest few as a pile.
final class MirrorAlbum: ObservableObject {
    struct Print: Identifiable, Equatable {
        let url: URL
        let image: NSImage
        var id: URL { url }
        static func == (a: Print, b: Print) -> Bool { a.url == b.url }
    }
    static let context = CIContext()
    static let pileSize = 5
    @Published private(set) var prints: [Print] = []
    @Published private(set) var total = 0
    /// The print that just came out: it slides out of the notch and develops.
    @Published private(set) var fresh: URL?

    static var folder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("Damla", isDirectory: true)
    }

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let files = ((try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
                .filter { $0.pathExtension.lowercased() == "png" }
            let sorted = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a > b
            }
            let prints = sorted.prefix(Self.pileSize).compactMap { url in NSImage(contentsOf: url).map { Print(url: url, image: $0) } }
            DispatchQueue.main.async {
                if prints != self.prints { self.prints = prints }
                self.total = files.count
            }
        }
    }

    /// Renders the card at print resolution and puts it on top of the pile.
    @MainActor
    func print(_ photo: CGImage, taken: Date) -> URL? {
        let card = PhotoCard(photo: NSImage(cgImage: photo, size: .zero), taken: taken, width: PhotoCard.printWidth)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = Self.folder.appendingPathComponent("Damla \(formatter.string(from: taken)).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        fresh = url
        prints.insert(Print(url: url, image: image), at: 0)
        if prints.count > Self.pileSize { prints.removeLast(prints.count - Self.pileSize) }
        total += 1
        return url
    }

    func settle() { fresh = nil }

    func trash(_ print: Print) {
        try? FileManager.default.trashItem(at: print.url, resultingItemURL: nil)
        load()
    }
}

// MARK: - The card

/// An instant-film card: cream frame, square photo with an orange date stamp burnt in the corner like an old
/// point-and-shoot, and the date written by hand in the wide bottom margin.
struct PhotoCard: View {
    static let printWidth: CGFloat = 300
    static let aspect: CGFloat = 1.26
    let photo: NSImage
    let taken: Date
    let width: CGFloat
    var body: some View {
        let margin = width * 0.07, side = width * 0.86
        VStack(spacing: 0) {
            Image(nsImage: photo).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .frame(width: side, height: side).clipped()
                .overlay(alignment: .bottomTrailing) {
                    Text(verbatim: PhotoCard.stamp(taken))
                        .font(.system(size: side * 0.068, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 1, green: 0.56, blue: 0.16))
                        .shadow(color: Color(red: 1, green: 0.4, blue: 0.05).opacity(0.9), radius: side * 0.012)
                        .blur(radius: side * 0.0015)
                        .padding(side * 0.05)
                }
                .padding(.top, margin)
            Text(verbatim: PhotoCard.caption(taken))
                .font(.custom("Bradley Hand", size: width * 0.072).weight(.bold))
                .foregroundStyle(Color(red: 0.19, green: 0.22, blue: 0.34).opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: width * Self.aspect)
        .background(Color(red: 0.97, green: 0.95, blue: 0.9), in: RoundedRectangle(cornerRadius: width * 0.025, style: .continuous))
    }

    /// "'26 9 27", the way film cameras printed the date.
    static func stamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "’%02d %d %d", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0)
    }
    /// "27 Eylül 2026 · 01:45"
    static func caption(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year()) + " · " + date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - The page

/// Ayna: an instant camera in the notch. A 3-2-1 countdown, a flash, and the card prints out of the notch,
/// developing from white as it drops onto the pile. The camera runs only while this page is on screen.
struct MirrorView: View {
    @ObservedObject private var camera = MirrorCamera.shared
    @StateObject private var album = MirrorAlbum()
    @AppStorage("mirrorLook") private var lookName = FilmLook.nostalgia.rawValue
    @AppStorage("mirrorTimer") private var useTimer = true
    @State private var countdown: Int?
    @State private var flash = false
    @State private var hovering = false

    private var look: FilmLook { FilmLook(rawValue: lookName) ?? .nostalgia }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            viewfinder.frame(width: 214, height: 214)
            pile.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { camera.start(); album.load() }
        .onDisappear { camera.stop(); countdown = nil; camera.busy = false }
    }

    // Viewfinder

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black)
            switch camera.state {
            case .running:
                CameraPreview(session: camera.session, filters: look.previewFilters())
                    .overlay(FilmGrain().opacity(look == .natural ? 0 : 0.5).blendMode(.overlay).allowsHitTesting(false))
                    .overlay(alignment: .topLeading) {
                        if showControls {
                            Text(look.title).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 7).padding(.vertical, 3).background(.black.opacity(0.35), in: Capsule())
                                .padding(9).transition(.opacity)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        TimelineView(.everyMinute) { context in
                            Text(verbatim: PhotoCard.stamp(context.date))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(red: 1, green: 0.56, blue: 0.16))
                                .shadow(color: Color(red: 1, green: 0.4, blue: 0.05).opacity(0.9), radius: 2.5)
                                .padding(10)
                        }
                    }
            case .denied:
                VStack(spacing: 8) {
                    Label("Kamera izni kapalı", systemImage: "video.slash").font(.system(size: 12, weight: .medium))
                    Button("Ayarları aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
                    }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(PillStyle())
                }
            case .unavailable:
                Label("Kamera bulunamadı", systemImage: "video.slash").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.dim)
            case .starting:
                ProgressView().controlSize(.small)
            }
            if let countdown {
                Text("\(countdown)").font(.system(size: 72, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .contentTransition(.numericText(countsDown: true))
                    .transition(.scale.combined(with: .opacity))
            }
            if showControls {
                // The shutter row appears over the picture only while the pointer is on it and nothing is being shot.
                VStack(spacing: 0) {
                    Spacer()
                    controls.padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 28)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
            Color.white.opacity(flash ? 0.95 : 0).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { inside in withAnimation(.easeOut(duration: 0.18)) { hovering = inside } }
        .animation(.easeOut(duration: 0.18), value: countdown == nil)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private var showControls: Bool { hovering && camera.state == .running && countdown == nil && !camera.busy }

    private var controls: some View {
        HStack {
            Button { withAnimation(Theme.quick) { lookName = look.next.rawValue } } label: {
                Image(systemName: look.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).contentShape(Circle())
            }
            .buttonStyle(GlassCircleStyle())
            .help(String(localized: "Film görünümü: \(look.title) · değiştir"))
            Spacer(minLength: 6)
            Button(action: shoot) {
                ZStack {
                    Circle().fill(.white).frame(width: 40, height: 40)
                    Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2.5).frame(width: 50, height: 50)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(camera.state != .running || countdown != nil)
            .opacity(camera.state == .running ? 1 : 0.4)
            .help(useTimer ? "3 saniye sonra çek" : "Çek")
            Spacer(minLength: 6)
            Button { useTimer.toggle() } label: {
                Image(systemName: useTimer ? "3.circle" : "bolt.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(useTimer ? Theme.accent : .white).contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34).contentShape(Circle())
            }
            .buttonStyle(GlassCircleStyle())
            .help(useTimer ? "3 saniye geri sayım · kapat" : "Hemen çeker · geri sayımı aç")
        }
    }

    // Pile of prints

    private var pile: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                if album.prints.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.faint)
                        Text("Çektiklerin burada birikir").font(.system(size: 10.5)).foregroundStyle(Theme.faint).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }
                ForEach(Array(album.prints.enumerated().reversed()), id: \.element.id) { index, print in
                    PrintView(print: print, fresh: album.fresh == print.url, album: album, onSettled: { album.settle() })
                        .rotationEffect(.degrees(Self.tilt(print.url)))
                        .offset(x: CGFloat(index) * 3, y: CGFloat(index) * 5)
                        .zIndex(Double(album.prints.count - index))
                        .transition(.printOut)
                }
            }
            .frame(height: 178, alignment: .top)
            Spacer(minLength: 0)
            Button { NSWorkspace.shared.open(MirrorAlbum.folder) } label: {
                Label(album.total == 0 ? String(localized: "Klasör") : String(localized: "\(album.total) fotoğraf"), systemImage: "folder")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .help(MirrorAlbum.folder.path)
        }
    }

    /// Each print lies at its own slight angle, stable across launches.
    static func tilt(_ url: URL) -> Double {
        let hash = url.lastPathComponent.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Double(hash % 13) - 6
    }

    // Shooting

    private func shoot() {
        guard camera.state == .running, countdown == nil, !camera.busy else { return }
        camera.busy = true
        if useTimer { tick(3) } else { take() }
    }

    private func tick(_ value: Int) {
        guard camera.state == .running else { countdown = nil; camera.busy = false; return }
        if value == 0 { withAnimation(.easeOut(duration: 0.15)) { countdown = nil }; take(); return }
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { countdown = value }
        NSSound(named: "Tink")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick(value - 1) }
    }

    private func take() {
        guard let photo = camera.snapshot(look: look) else { camera.busy = false; return }
        MirrorView.shutter?.stop(); MirrorView.shutter?.play()
        flash = true
        withAnimation(.easeOut(duration: 0.45)) { flash = false }
        // The card prints a beat after the flash, like an instant camera ejecting it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(duration: 1.1, bounce: 0.22)) {
                _ = album.print(photo, taken: Date())
            }
            // Let the card land before the panel may fold away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { camera.busy = false }
        }
    }

    static let shutter: NSSound? = NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif", byReference: true)
        ?? NSSound(named: "Tink")
}

/// One print on the pile. The fresh one develops: its photo starts as a blank cream square and comes up over a
/// few seconds, colour last.
private struct PrintView: View {
    let print: MirrorAlbum.Print
    let fresh: Bool
    @ObservedObject var album: MirrorAlbum
    let onSettled: () -> Void
    @State private var developed = false
    static let width: CGFloat = 118
    var body: some View {
        let w = Self.width, margin = w * 0.07, side = w * 0.86
        Image(nsImage: print.image).resizable().interpolation(.high)
            .frame(width: w, height: w * PhotoCard.aspect)
            .overlay(alignment: .top) {
                // The undeveloped emulsion over the photo area only.
                Rectangle().fill(Color(red: 0.93, green: 0.92, blue: 0.88))
                    .frame(width: side, height: side).padding(.top, margin)
                    .opacity(fresh && !developed ? 0.97 : 0)
            }
            .saturation(fresh && !developed ? 0.2 : 1)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
            .onAppear {
                guard fresh else { return }
                withAnimation(.easeIn(duration: 3.2).delay(0.8)) { developed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { onSettled() }
            }
            .onTapGesture(count: 2) { NSWorkspace.shared.open(print.url) }
            .onDrag { NSItemProvider(object: print.url as NSURL) }
            .contextMenu {
                Button("Aç") { NSWorkspace.shared.open(print.url) }
                Button("Finder’da göster") { NSWorkspace.shared.activateFileViewerSelecting([print.url]) }
                Divider()
                Button("Çöpe at") { album.trash(print) }
            }
            .help(String(localized: "Çift tıkla: aç · sürükle: istediğin yere bırak"))
    }
}

/// The card slides down out of the notch, turning as it falls onto the pile.
private struct PrintOut: ViewModifier {
    let progress: CGFloat
    func body(content: Content) -> some View {
        content
            .offset(y: (1 - progress) * -340)
            .rotationEffect(.degrees(Double(1 - progress) * -8))
            .opacity(progress == 0 ? 0 : 1)
    }
}
private extension AnyTransition {
    static var printOut: AnyTransition {
        .asymmetric(insertion: .modifier(active: PrintOut(progress: 0.001), identity: PrintOut(progress: 1)),
                    removal: .opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// Fine static film grain for the viewfinder.
private struct FilmGrain: View {
    static let image: NSImage? = {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0]),
              let cg = MirrorAlbum.context.createCGImage(noise, from: CGRect(x: 0, y: 0, width: 256, height: 256)) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 256, height: 256))
    }()
    var body: some View {
        if let image = Self.image { Image(nsImage: image).resizable(resizingMode: .tile) }
    }
}

/// The live picture, mirrored like a real mirror and filling its frame, with the film look applied by the layer.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let filters: [CIFilter]
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        layer.filters = filters
        view.layer = layer
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.filters = filters
    }
}
