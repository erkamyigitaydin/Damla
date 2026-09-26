import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Quick conversions on shelf files. Each one writes a new file next to the original (or to Downloads when that
/// folder is read-only) and puts it on the shelf; the original is never changed.
enum ShelfAction: Equatable {
    case convert(UTType), halfSize, compress, mergePDFs

    var title: String {
        switch self {
        case .convert(let type): return String(localized: "\(type.preferredFilenameExtension?.uppercased() ?? "?") olarak kaydet")
        case .halfSize: return String(localized: "Yarı boyuta küçült")
        case .compress: return String(localized: "Sıkıştır (JPEG)")
        case .mergePDFs: return String(localized: "Raftaki PDF’leri birleştir")
        }
    }

    static func isImage(_ url: URL) -> Bool { (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image)) ?? false }
    static func isPDF(_ url: URL) -> Bool { (UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf)) ?? false }

    /// What the context menu offers for this file, given everything on the shelf.
    static func available(for url: URL, shelf: [URL]) -> [ShelfAction] {
        if isImage(url) {
            let type = UTType(filenameExtension: url.pathExtension)
            return [UTType.png, .jpeg, .heic].filter { $0 != type }.map { ShelfAction.convert($0) } + [.halfSize, .compress]
        }
        if isPDF(url), shelf.filter(isPDF).count >= 2 { return [.mergePDFs] }
        return []
    }

    /// Runs off the main thread; answers with the new file, or nil when it could not be made.
    func run(on url: URL, shelf: [URL], completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: URL?
            switch self {
            case .convert(let type): result = Self.writeImage(url, as: type, suffix: nil, scale: 1, quality: 0.9)
            case .halfSize: result = Self.writeImage(url, as: UTType(filenameExtension: url.pathExtension) ?? .png, suffix: String(localized: "küçük"), scale: 0.5, quality: 0.9)
            case .compress: result = Self.writeImage(url, as: .jpeg, suffix: String(localized: "sıkıştırılmış"), scale: 1, quality: 0.6)
            case .mergePDFs: result = Self.merge(shelf.filter(Self.isPDF), near: url)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func writeImage(_ url: URL, as type: UTType, suffix: String?, scale: CGFloat, quality: CGFloat) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? CGFloat ?? 0, height = properties[kCGImagePropertyPixelHeight] as? CGFloat ?? 0
        let image: CGImage?
        if scale < 1 {
            // The thumbnail API resizes with the photo's orientation applied, in one decode.
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: max(1, max(width, height) * scale)]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image, let ext = type.preferredFilenameExtension,
              let target = destination(for: url, suffix: suffix, ext: ext),
              let output = CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if scale >= 1, let orientation = properties[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(output, image, options as CFDictionary)
        return CGImageDestinationFinalize(output) ? target : nil
    }

    static func merge(_ pdfs: [URL], near url: URL) -> URL? {
        let merged = PDFDocument()
        for file in pdfs {
            guard let document = PDFDocument(url: file) else { continue }
            for index in 0..<document.pageCount {
                if let page = document.page(at: index) { merged.insert(page, at: merged.pageCount) }
            }
        }
        guard merged.pageCount > 0, let target = destination(for: url, suffix: String(localized: "birleştirilmiş"), ext: "pdf") else { return nil }
        return merged.write(to: target) ? target : nil
    }

    /// "foto.png" → "foto-küçük.jpg" in the same folder, or in Downloads when that folder is read-only; never
    /// over an existing file.
    static func destination(for url: URL, suffix: String?, ext: String) -> URL? {
        let fm = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent + (suffix.map { "-" + $0 } ?? "")
        var folder = url.deletingLastPathComponent()
        if !fm.isWritableFile(atPath: folder.path) {
            guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
            folder = downloads
        }
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var number = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }
}

/// New screenshots land on the shelf by themselves. Spotlight marks them (kMDItemIsScreenCapture), whatever the
/// system language or the folder they are saved to.
final class ScreenshotWatcher {
    var onNew: (([URL]) -> Void)?
    private var query: NSMetadataQuery?
    private var seen = Set<String>()
    private var started = Date()

    func start() {
        guard query == nil else { return }
        started = Date()
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentCreationDate >= %@", started as NSDate)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .NSMetadataQueryDidFinishGathering, object: query)
        self.query = query
        query.start()
    }
    func stop() {
        query?.stop()
        if let query { NotificationCenter.default.removeObserver(self, name: nil, object: query) }
        query = nil
    }

    @objc private func update() {
        guard let query else { return }
        query.disableUpdates(); defer { query.enableUpdates() }
        var fresh: [URL] = []
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String, seen.insert(path).inserted else { continue }
            fresh.append(URL(fileURLWithPath: path))
        }
        if !fresh.isEmpty { onNew?(fresh) }
    }
}
