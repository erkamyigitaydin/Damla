import AppKit
import ImageIO

/// Images decoded no larger than they are drawn. ImageIO scales while it decodes, so a 5K screenshot or a
/// 3000 px album cover never becomes a full-size bitmap (59 MB, 36 MB) that then stays resident for as long as
/// the `NSImage` lives; after a day of copying and listening those bitmaps outweighed the rest of the app.
enum Thumbnails {
    /// Album covers: the panel draws them well under 300 px.
    static let artworkSize = 640

    static func decode(_ data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
