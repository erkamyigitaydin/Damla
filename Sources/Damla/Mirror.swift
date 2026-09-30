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
    /// The camera can keep you in frame as you move (Center Stage, "Ana Sahne").
    @Published private(set) var centerStageSupported = false
    @Published private(set) var centerStage = UserDefaults.standard.object(forKey: "mirrorCenterStage") as? Bool ?? true

    /// Turns Center Stage on or off for Damla. Cooperative control keeps the Control Center switch working too.
    func setCenterStage(_ on: Bool) {
        centerStage = on
        UserDefaults.standard.set(on, forKey: "mirrorCenterStage")
        queue.async { Self.applyCenterStage(on) }
    }
    private static func applyCenterStage(_ on: Bool) {
        AVCaptureDevice.centerStageControlMode = .cooperative
        AVCaptureDevice.isCenterStageEnabled = on
    }
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
            let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device
            let supported = device?.activeFormat.isCenterStageSupported ?? false
            if supported { Self.applyCenterStage(self.centerStage) }
            DispatchQueue.main.async { self.centerStageSupported = supported }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); latest = buffer; lock.unlock()
    }

    /// The newest frame, mirrored like the preview and cropped to the viewfinder's shape (what you see is what
    /// you get), in the chosen look.
    func snapshot(look: FilmLook, aspect: CGFloat) -> CGImage? {
        lock.lock(); let buffer = latest; lock.unlock()
        guard let buffer, aspect > 0 else { return nil }
        var image = CIImage(cvPixelBuffer: buffer)
        image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -image.extent.width, y: 0))
        let extent = image.extent
        var crop = extent
        if extent.width / extent.height > aspect { crop.size.width = (extent.height * aspect).rounded() }
        else { crop.size.height = (extent.width / aspect).rounded() }
        crop.origin = CGPoint(x: extent.midX - crop.width / 2, y: extent.midY - crop.height / 2)
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        image = look.develop(image)
        return MirrorAlbum.context.createCGImage(image, from: CGRect(origin: .zero, size: crop.size))
    }

    deinit { if session.isRunning { session.stopRunning() } }
}

// MARK: - Album

/// Prints saved as JPEG files in ~/Pictures/Damla. The page shows the newest one as a small card in the
/// corner, like the Camera app's thumbnail.
final class MirrorAlbum: ObservableObject {
    struct Photo: Identifiable, Equatable {
        let url: URL
        let thumbnail: NSImage
        var id: URL { url }
        static func == (a: Photo, b: Photo) -> Bool { a.url == b.url }
    }
    static let context = CIContext()
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
    @Published private(set) var latest: Photo?
    @Published private(set) var total = 0

    static var folder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("Damla", isDirectory: true)
    }

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let files = ((try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
                .filter { Self.extensions.contains($0.pathExtension.lowercased()) }
            let newest = files.max {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a < b
            }
            let photo = newest.flatMap { url in Self.thumbnail(of: url).map { Photo(url: url, thumbnail: $0) } }
            DispatchQueue.main.async {
                if photo != self.latest { self.latest = photo }
                self.total = files.count
            }
        }
    }

    /// A small copy for the corner; the full photo is never held in memory.
    static func thumbnail(of url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 200,
                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    /// Prints the photo as a wide instant-film card and writes it; the page shows it once it has flown into the corner.
    @MainActor
    func save(_ photo: CGImage, taken: Date) -> Photo? {
        let size = CGSize(width: photo.width, height: photo.height)
        let renderer = ImageRenderer(content: PolaroidCard(photo: NSImage(cgImage: photo, size: size), taken: taken, photoSize: size,
                                                           dated: PolaroidCard.datedSetting))
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return nil }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = Self.folder.appendingPathComponent("Damla \(formatter.string(from: taken)).jpg")
        guard (try? jpeg.write(to: url)) != nil, let thumbnail = Self.thumbnail(of: url) else { return nil }
        return Photo(url: url, thumbnail: thumbnail)
    }

    func show(_ photo: Photo) {
        latest = photo
        total += 1
    }

    func trash(_ photo: Photo) {
        try? FileManager.default.trashItem(at: photo.url, resultingItemURL: nil)
        load()
    }
}

// MARK: - The card

/// A wide instant-film card: cream frame around the photo, exactly as the viewfinder framed it, an orange date
/// stamp burnt into its corner like an old point-and-shoot, and the date written by hand in the wide bottom margin.
/// The frame is measured from the photo's height, so any viewfinder shape gets the same border.
struct PolaroidCard: View {
    static let side: CGFloat = 0.06     // left, right and top border, per photo height
    static let bottom: CGFloat = 0.3    // the writing margin, per photo height
    static let cream = Color(red: 0.97, green: 0.95, blue: 0.9)
    let photo: NSImage
    let taken: Date
    let photoSize: CGSize
    /// The orange stamp on the photo and the handwritten date under it; off leaves a plain cream margin.
    var dated = true
    static let datedKey = "mirrorDate"
    static var datedSetting: Bool { UserDefaults.standard.object(forKey: datedKey) as? Bool ?? true }

    /// The whole card for a photo of this size.
    static func size(photo: CGSize) -> CGSize {
        CGSize(width: photo.width + 2 * side * photo.height, height: photo.height * (1 + side + bottom))
    }

    var body: some View {
        let h = photoSize.height
        VStack(spacing: 0) {
            Image(nsImage: photo).resizable().interpolation(.high)
                .frame(width: photoSize.width, height: h)
                .overlay(alignment: .bottomTrailing) {
                    if dated {
                    Text(verbatim: Self.stamp(taken))
                        .font(.system(size: h * 0.068, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 1, green: 0.56, blue: 0.16))
                        .shadow(color: Color(red: 1, green: 0.4, blue: 0.05).opacity(0.9), radius: h * 0.012)
                        .blur(radius: h * 0.0015)
                        .padding(h * 0.06)
                    }
                }
                .padding(.top, h * Self.side)
            Text(verbatim: Self.caption(taken))
                .font(.custom("Bradley Hand", size: h * 0.11).weight(.bold))
                .foregroundStyle(Color(red: 0.19, green: 0.22, blue: 0.34).opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(dated ? 1 : 0)
        }
        .frame(width: Self.size(photo: photoSize).width, height: Self.size(photo: photoSize).height)
        .background(Self.cream)
    }

    /// "'26 9 27", the way film cameras printed the date.
    static func stamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "’%02d %d %d", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0)
    }
    /// "1 Ekim 2026 · 14:05"
    static func caption(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year()) + " · " + date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - The page

/// Ayna: an instant camera in the notch. The viewfinder spans the panel; a 3-2-1 countdown, a flash, and the photo
/// shrinks into the corner, growing its cream frame on the way, as a small print in the bottom-left. The camera runs only while this page is on screen.
struct MirrorView: View {
    @ObservedObject private var camera = MirrorCamera.shared
    @StateObject private var album = MirrorAlbum()
    @AppStorage("mirrorLook") private var lookName = FilmLook.nostalgia.rawValue
    @AppStorage("mirrorTimer") private var useTimer = true
    @AppStorage(PolaroidCard.datedKey) private var dated = true
    @State private var countdown: Int?
    @State private var flash = false
    @State private var frameSize = CGSize(width: 380, height: 162)
    /// The photo just taken, on its way from the viewfinder into the corner.
    @State private var flying: NSImage?
    @State private var landed = false

    private var look: FilmLook { FilmLook(rawValue: lookName) ?? .nostalgia }
    static let thumbWidth: CGFloat = 64   // the print in the corner
    static let thumbTilt: Double = -4
    static let corner: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            viewfinder
                .onAppear { frameSize = geo.size }
                .onChange(of: geo.size) { _, size in frameSize = size }
        }
        // Wider than the other pages: the picture runs almost to the panel's edges.
        .padding(.horizontal, -12)
        .onAppear { camera.start(); album.load() }
        .onDisappear { camera.stop(); countdown = nil; camera.busy = false; flying = nil }
    }

    // Viewfinder

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        return ZStack {
            shape.fill(Color.black)
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
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 8) {
                            // The date the photo will carry, in the corner the controls leave free.
                            if dated { TimelineView(.everyMinute) { context in
                                Text(verbatim: PolaroidCard.stamp(context.date))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(red: 1, green: 0.56, blue: 0.16))
                                    .shadow(color: Color(red: 1, green: 0.4, blue: 0.05).opacity(0.9), radius: 2.5)
                            } }
                            if showControls && camera.centerStageSupported { centerStageButton.transition(.opacity) }
                        }
                        .padding(9)
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
                Text("\(countdown)").font(.system(size: 58, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .contentTransition(.numericText(countsDown: true))
                    .transition(.scale.combined(with: .opacity))
            }
            if showControls {
                // The shutter row sits over the foot of the picture whenever nothing is being shot.
                VStack(spacing: 0) {
                    Spacer()
                    controls.padding(.horizontal, 10).padding(.bottom, 8).padding(.top, 24)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
            Color.white.opacity(flash ? 0.95 : 0).allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) { corner }
        .clipShape(shape)
        .contentShape(shape)
        .animation(.easeOut(duration: 0.18), value: countdown == nil)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    /// The controls stay on the picture; only a countdown or a shot in progress clears them away.
    private var showControls: Bool { camera.state == .running && countdown == nil && !camera.busy }

    private var centerStageButton: some View {
        Button { camera.setCenterStage(!camera.centerStage) } label: {
            Label("Ana Sahne", systemImage: camera.centerStage ? "person.and.background.dotted" : "person.crop.rectangle")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(camera.centerStage ? Color.black : .white.opacity(0.9))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(camera.centerStage ? AnyShapeStyle(Color.white.opacity(0.9)) : AnyShapeStyle(Color.black.opacity(0.35)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(camera.centerStage ? "Ana Sahne açık: kamera seni kadrajda tutar · kapat" : "Ana Sahne kapalı · aç")
    }

    private var controls: some View {
        ZStack {
            Button(action: shoot) {
                ZStack {
                    Circle().fill(.white).frame(width: 34, height: 34)
                    Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2.5).frame(width: 43, height: 43)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(camera.state != .running || countdown != nil)
            .opacity(camera.state == .running ? 1 : 0.4)
            .help(useTimer ? "3 saniye sonra çek" : "Çek")
            HStack(spacing: 8) {
                Spacer()
                Button { withAnimation(Theme.quick) { lookName = look.next.rawValue } } label: {
                    Image(systemName: look.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).contentShape(Circle())
                }
                .buttonStyle(GlassCircleStyle())
                .help(String(localized: "Film görünümü: \(look.title) · değiştir"))
                Button { useTimer.toggle() } label: {
                    Image(systemName: useTimer ? "3.circle" : "bolt.fill").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(useTimer ? Theme.accent : .white).contentTransition(.symbolEffect(.replace))
                        .frame(width: 30, height: 30).contentShape(Circle())
                }
                .buttonStyle(GlassCircleStyle())
                .help(useTimer ? "3 saniye geri sayım · kapat" : "Hemen çeker · geri sayımı aç")
            }
        }
        .frame(height: 43)
    }

    // The newest photo in the corner

    @ViewBuilder private var corner: some View {
        if let flying {
            // Fills the viewfinder at the flash, then shrinks into the corner as the card's frame grows around it.
            let aspect = frameSize.height > 0 ? frameSize.width / frameSize.height : 16 / 9
            let photoHeight = Self.thumbWidth / (aspect + 2 * PolaroidCard.side)
            Image(nsImage: flying).resizable().aspectRatio(contentMode: .fill)
                .frame(width: landed ? photoHeight * aspect : frameSize.width, height: landed ? photoHeight : frameSize.height)
                .clipped()
                .padding(.horizontal, landed ? photoHeight * PolaroidCard.side : 0)
                .padding(.top, landed ? photoHeight * PolaroidCard.side : 0)
                .padding(.bottom, landed ? photoHeight * PolaroidCard.bottom : 0)
                .background(PolaroidCard.cream.opacity(landed ? 1 : 0))
                .clipShape(RoundedRectangle(cornerRadius: landed ? 2 : Self.corner, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                .rotationEffect(.degrees(landed ? Self.thumbTilt : 0))
                .padding(.leading, landed ? 11 : 0).padding(.bottom, landed ? 11 : 0)
                .allowsHitTesting(false)
        } else if let photo = album.latest, camera.state == .running {
            ThumbnailView(photo: photo, album: album).padding(11).transition(.opacity)
        }
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
        let aspect = frameSize.height > 0 ? frameSize.width / frameSize.height : 16 / 9
        guard let photo = camera.snapshot(look: look, aspect: aspect) else { camera.busy = false; return }
        MirrorView.shutter?.stop(); MirrorView.shutter?.play()
        flash = true
        withAnimation(.easeOut(duration: 0.45)) { flash = false }
        let saved = album.save(photo, taken: Date())
        landed = false
        flying = NSImage(cgImage: photo, size: .zero)
        // A beat on the full picture after the flash, then into the corner.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(duration: 0.55, bounce: 0.14)) { landed = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            if let saved { album.show(saved) }
            flying = nil
            camera.busy = false
        }
    }

    static let shutter: NSSound? = NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif", byReference: true)
        ?? NSSound(named: "Tink")
}

/// The newest print, small and a little askew in the corner: click opens it, drag takes it anywhere.
private struct ThumbnailView: View {
    let photo: MirrorAlbum.Photo
    @ObservedObject var album: MirrorAlbum
    @State private var hovering = false
    var body: some View {
        let size = photo.thumbnail.size
        let width = MirrorView.thumbWidth
        let height = size.width > 0 ? width * size.height / size.width : width
        Image(nsImage: photo.thumbnail).resizable().interpolation(.high)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
            .rotationEffect(.degrees(hovering ? 0 : MirrorView.thumbTilt))
            .scaleEffect(hovering ? 1.08 : 1, anchor: .bottomLeading)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { NSWorkspace.shared.open(photo.url) }
            .onDrag { NSItemProvider(object: photo.url as NSURL) }
            .contextMenu {
                Button("Aç") { NSWorkspace.shared.open(photo.url) }
                Button("Finder’da göster") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                Button(String(localized: "Tüm fotoğraflar (\(album.total))")) { NSWorkspace.shared.open(MirrorAlbum.folder) }
                Divider()
                Button("Çöpe at") { album.trash(photo) }
            }
            .help(String(localized: "Tıkla: aç · sürükle: istediğin yere bırak"))
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
