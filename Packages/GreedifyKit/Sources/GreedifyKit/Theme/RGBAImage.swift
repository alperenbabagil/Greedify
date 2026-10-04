import CoreGraphics
import Foundation

/// Straight (not premultiplied) RGBA pixels, row by row from the top, one `0xRRGGBBAA` per pixel.
/// Skin sprites are sliced and upscaled in this form (skinned controls spec §4).
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt32]

    public init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(width >= 0 && height >= 0 && pixels.count == width * height)
        self.width = width; self.height = height; self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt32) {
        self.init(width: width, height: height, pixels: Array(repeating: fill, count: width * height))
    }

    /// Decodes without smoothing, in the image's own RGB space so skin colours aren't converted.
    /// Skin sprites are opaque, so drawing premultiplied loses nothing.
    public init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w * h <= ThemeImage.maxPixels else { return nil }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(data: pointer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        self.init(width: w, height: h, pixels: stride(from: 0, to: bytes.count, by: 4).map { i in
            UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
        })
    }

    public subscript(x: Int, y: Int) -> UInt32 { pixels[y * width + x] }

    /// The rectangle as its own image; nil when it doesn't fit inside this one.
    public func crop(x: Int, y: Int, width w: Int, height h: Int) -> RGBAImage? {
        guard x >= 0, y >= 0, w > 0, h > 0, x + w <= width, y + h <= height else { return nil }
        var out: [UInt32] = []
        out.reserveCapacity(w * h)
        for row in y..<(y + h) { out += pixels[(row * width + x)..<(row * width + x + w)] }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    /// Copies `image` in with its top-left at (x, y); what falls outside is dropped.
    public mutating func paste(_ image: RGBAImage, x: Int, y: Int) {
        for row in 0..<image.height where (0..<height).contains(y + row) {
            for column in 0..<image.width where (0..<width).contains(x + column) {
                pixels[(y + row) * width + x + column] = image[column, row]
            }
        }
    }

    public func cgImage() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(pixels.count * 4)
        for p in pixels { bytes += [UInt8(p >> 24), UInt8(p >> 16 & 0xFF), UInt8(p >> 8 & 0xFF), UInt8(p & 0xFF)] }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
