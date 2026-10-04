import AppKit
import Foundation
import ImageIO

/// Artwork: decoded images in RAM (`NSCache`, cost = decoded bytes) backed by the disk `DataCache`.
/// Images are decoded at the pixel size they're shown at (Spotify sends 640 px covers, even for a 34 pt row),
/// which keeps the window's memory peak down; the disk keeps the original download.
public final class ImageCache: @unchecked Sendable {
    let memory = NSCache<NSString, NSImage>()
    let disk: DataCache
    let transport: HTTPTransport

    public init(disk: DataCache, transport: HTTPTransport, memoryLimitBytes: Int) {
        self.disk = disk
        self.transport = transport
        memory.totalCostLimit = memoryLimitBytes
    }

    public func setMemoryLimit(_ bytes: Int) { memory.totalCostLimit = bytes }
    public func clearMemory() { memory.removeAllObjects() }

    static func cost(of image: NSImage) -> Int {
        let rep = image.representations.first
        let w = rep?.pixelsWide ?? Int(image.size.width)
        let h = rep?.pixelsHigh ?? Int(image.size.height)
        return max(1, w * h * 4)
    }

    static func memoryKey(_ url: URL, _ maxPixelSize: Int?) -> NSString {
        "\(url.absoluteString)#\(maxPixelSize ?? 0)" as NSString
    }

    public func cached(_ url: URL, maxPixelSize: Int? = nil) -> NSImage? {
        memory.object(forKey: Self.memoryKey(url, maxPixelSize))
    }

    /// `maxPixelSize` is the longest side to decode to; nil decodes the full image.
    public func image(for url: URL, maxPixelSize: Int? = nil) async -> NSImage? {
        if let hit = cached(url, maxPixelSize: maxPixelSize) { return hit }
        let key = "art:\(url.absoluteString)"
        var data = await disk.data(for: key)
        if data == nil {
            guard let (fetched, http) = try? await transport.send(URLRequest(url: url)),
                  (200..<300).contains(http.statusCode) else { return nil }
            await disk.store(fetched, for: key)
            data = fetched
        }
        guard let data, let image = Self.decode(data, maxPixelSize: maxPixelSize) else { return nil }
        memory.setObject(image, forKey: Self.memoryKey(url, maxPixelSize), cost: Self.cost(of: image))
        return image
    }

    /// Decodes once, at the target size, into a bitmap-backed image (no lazily-decoded full-size copy).
    static func decode(_ data: Data, maxPixelSize: Int?) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // A bitmap rep reports its real pixel size (NSImage(cgImage:size:) reports screen-scaled pixels),
        // so the NSCache cost matches the memory actually used.
        let image = NSImage(size: NSSize(width: cg.width, height: cg.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return image
    }
}
