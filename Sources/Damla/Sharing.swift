import AppKit

/// Owns the system picker and its service until completion/cancellation.
final class ShelfSharing: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private weak var model: AppState?
    private weak var window: NSWindow?
    private var picker: NSSharingServicePicker?
    private var scopedURLs: [URL] = []
    private var wasPinned = false
    private var active = false

    func show(_ url: URL, from view: NSView, model: AppState) {
        guard !active else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            model.showNotice(String(localized: "Dosya bulunamadı. Rafa yeniden ekleyebilirsin.")); return
        }
        if scoped { scopedURLs = [url] }
        self.model = model; window = view.window
        wasPinned = model.pinnedOpen; active = true
        model.pinnedOpen = true
        model.setDialogMode?(true)
        view.window?.makeKeyAndOrderFront(nil)
        let picker = NSSharingServicePicker(items: [url])
        self.picker = picker; picker.delegate = self
        // The screen-saver-level notch must yield to the native sharing popover/composer.
        let rect = NSRect(x: view.bounds.midX - 12, y: view.bounds.maxY - 110, width: 24, height: 24)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? { self }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { finish() }
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        finish()
        if (error as NSError).code != NSUserCancelledError { model?.showNotice(String(localized: "Paylaşım tamamlanamadı: \(error.localizedDescription)")) }
    }
    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any], sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? { window }

    func finish() {
        guard active else { return }
        active = false
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }; scopedURLs = []
        model?.setDialogMode?(false); model?.pinnedOpen = wasPinned
        picker = nil
    }
}
