import AVFoundation
import SwiftUI

/// A quick look at yourself before a call. The camera runs only while this page is on screen; leaving the page
/// or closing the panel stops it (and the green light) at once. Nothing is recorded.
struct MirrorView: View {
    @StateObject private var camera = MirrorCamera()
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.5))
                switch camera.state {
                case .running:
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

final class MirrorCamera: ObservableObject {
    enum State { case starting, running, denied, unavailable }
    @Published private(set) var state: State = .starting
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.local.damla.mirror")
    private var configured = false
    private var wanted = false

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
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
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
                self.session.sessionPreset = .medium
                self.session.addInput(input)
                self.session.commitConfiguration()
                self.configured = true
            }
            // The pane may have closed while access was being asked.
            guard self.wanted else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }
    deinit { if session.isRunning { session.stopRunning() } }
}

/// The live picture, mirrored like a real mirror and filling its frame.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
