import AppKit
import Quartz
import QuickLookThumbnailing

/// Real previews for shelf tiles and the drag tray. Generated once per path on a background queue;
/// `isPreview` is false when Quick Look could only offer the generic file icon.
final class ThumbnailStore: ObservableObject {
    struct Thumb { let image: NSImage; let isPreview: Bool }
    static let shared = ThumbnailStore()
    @Published private(set) var thumbs: [String: Thumb] = [:]
    private var pending = Set<String>()
    /// Paths in the order their thumbnails arrived. Past the limit the oldest go: every file dragged anywhere
    /// while the basket was up asked for one, and a day of drags and shelved screenshots must not keep them all.
    private var order: [String] = []
    private static let limit = 160

    func thumbnail(for url: URL, size: CGSize = CGSize(width: 72, height: 58)) -> Thumb? {
        let key = url.path
        if let thumb = thumbs[key] { return thumb }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending.remove(key)
                self.thumbs[key] = representation.map { Thumb(image: $0.nsImage, isPreview: $0.type != .icon) }
                    ?? Thumb(image: NSWorkspace.shared.icon(forFile: url.path), isPreview: false)
                self.order.append(key)
                if self.order.count > Self.limit { self.thumbs.removeValue(forKey: self.order.removeFirst()) }
            }
        }
        return nil
    }
}

/// Feeds the system Quick Look panel from the shelf. The notch window hands control to this object
/// through the responder-chain hooks on `NotchPanel`.
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    unowned let model: AppState
    init(model: AppState) { self.model = model }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { model.files.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard model.files.indices.contains(index) else { return nil }
        return model.files[index].url as NSURL
    }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool { false }

    static var isShowing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }
}
