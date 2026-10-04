import CoreGraphics
import Foundation
import ImageIO

/// A decoded skin bitmap, kept only while a skin is imported (spec §3).
struct SkinBitmap {
    let width: Int
    let height: Int
    private let rgba: [UInt8]

    init?(data: Data) {
        guard let image = ThemeImage.cgImage(data) else { return nil }
        self.init(image: image)
    }

    init?(image: CGImage) {
        guard image.width > 0, image.height > 0, image.width * image.height <= ThemeImage.maxPixels else { return nil }
        self.init(image: image, width: image.width, height: image.height)
    }

    /// `image` sampled (nearest pixel, never averaged) down to at most `maxPixels`, keeping its aspect.
    init?(image: CGImage, fittingIn maxPixels: Int) {
        guard image.width > 0, image.height > 0, maxPixels > 0 else { return nil }
        let scale = min(1, (Double(maxPixels) / Double(image.width * image.height)).squareRoot())
        self.init(image: image, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)))
    }

    private init?(image: CGImage, width w: Int, height h: Int) {
        // Draw into the image's own RGB space so the pixel values aren't color-converted.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(data: pointer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w; height = h; rgba = buffer
    }

    /// Calls `body` with each pixel's 8-bit red, green and blue, row by row from the top.
    func forEachPixel(_ body: (UInt8, UInt8, UInt8) -> Void) {
        for i in stride(from: 0, to: rgba.count, by: 4) { body(rgba[i], rgba[i + 1], rgba[i + 2]) }
    }

    /// The pixel at (x, y), y = 0 at the top.
    func color(x: Int, y: Int) -> ThemeColor? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        let i = (y * width + x) * 4
        return ThemeColor(r8: Int(rgba[i]), g8: Int(rgba[i + 1]), b8: Int(rgba[i + 2]))
    }

    /// The average of the most common color bucket (4 bits per channel) across `regions`.
    func dominantColor(in regions: [(xs: Range<Int>, ys: Range<Int>)]) -> ThemeColor? {
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for region in regions {
            for y in region.ys.clamped(to: 0..<height) {
                for x in region.xs.clamped(to: 0..<width) {
                    let i = (y * width + x) * 4
                    let (r, g, b) = (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
                    let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
                    let old = buckets[key] ?? (0, 0, 0, 0)
                    buckets[key] = (old.count + 1, old.r + r, old.g + g, old.b + b)
                }
            }
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        let n = Double(best.count) * 255
        return ThemeColor(r: Double(best.r) / n, g: Double(best.g) / n, b: Double(best.b) / n)
    }

    /// The pixels of a rectangle, row by row; the parts outside the bitmap are skipped.
    func colors(in r: SkinControlPalette.Rect) -> [ThemeColor] {
        var out: [ThemeColor] = []
        for y in stride(from: max(0, r.y), to: min(height, r.y + r.h), by: 1) {
            for x in stride(from: max(0, r.x), to: min(width, r.x + r.w), by: 1) {
                if let c = color(x: x, y: y) { out.append(c) }
            }
        }
        return out
    }
}
