import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG plumbing for theme images (theme images spec §2–§3), all through ImageIO.
public enum ThemeImage {
    public static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    /// A skin's `text.bmp` must hold the full 5×6 glyph grid (31 columns × 3 rows).
    public static let pixelFontMinWidth = 155
    public static let pixelFontMinHeight = 18

    public static func isPNG(_ data: Data) -> Bool { data.starts(with: pngSignature) }

    /// The most pixels a theme image may have (2048×2048). A flat PNG under the 512 KB file limit can still
    /// describe hundreds of megabytes of pixels, so the size is read from the header before anything is decoded.
    public static let maxPixels = 2048 * 2048

    /// Decodes any ImageIO-readable image (PNG, BMP…) of at most `ThemeImage.maxPixels`.
    public static func cgImage(_ data: Data) -> CGImage? { cgImage(data, maxPixels: maxPixels) }

    /// Decodes any ImageIO-readable image of at most `maxPixels`, checking the header before decoding.
    public static func cgImage(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= maxPixels, height <= maxPixels, width * height <= maxPixels else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    /// Re-encodes an image (a skin's BMP) as PNG at its native size.
    public static func png(fromImageData data: Data) -> Data? { cgImage(data).flatMap(png) }
}
