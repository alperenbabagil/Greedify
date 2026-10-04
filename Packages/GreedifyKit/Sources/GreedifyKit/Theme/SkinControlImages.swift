import CoreGraphics
import Foundation

/// A skin's control sprites, sliced from the theme's images and smoothed 4× (skinned controls spec §4–§5).
/// Built off the main actor with the theme's other images; a missing part means "draw that control the plain way".
public struct SkinControlImages: Sendable {
    public static let scale = 4
    public static let volumeFrameCount = 28

    public var groove: CGImage?
    public var handle: CGImage?
    public var handlePressed: CGImage?
    /// All 28 frames, or none.
    public var volumeFrames: [CGImage] = []
    public var volumeHandle: CGImage?
    public var volumeHandlePressed: CGImage?
    /// Digits 0–9, or none.
    public var digits: [CGImage] = []
    public var minus: CGImage?
    /// The digits' lit colour, for what the skin has no sprite for (the colon).
    public var digitInk: ThemeColor?

    public static let empty = SkinControlImages()
    private init() {}

    public init(_ images: Theme.Images) {
        typealias K = SkinSprites
        if let strip = K.decode(images.seekBar) {
            groove = Self.part(strip, 0, 0, K.grooveWidth, K.barHeight)
            handle = Self.part(strip, K.handleX, 0, K.handleWidth, K.barHeight)
            handlePressed = Self.part(strip, K.pressedHandleX, 0, K.handleWidth, K.barHeight)
        }
        if let sheet = K.decode(images.volume) {
            let frames = (0..<Self.volumeFrameCount).compactMap { Self.part(sheet, 0, $0 * 15, K.volumeWidth, 13) }
            volumeFrames = frames.count == Self.volumeFrameCount ? frames : []
            volumeHandlePressed = Self.part(sheet, 0, 422, 14, 11)
            volumeHandle = Self.part(sheet, 15, 422, 14, 11)
        }
        if let sheet = K.decode(images.digits) {
            let ink = Self.inkPixel(sheet)
            digitInk = ink.map { ThemeColor(r8: Int($0 >> 24), g8: Int($0 >> 16 & 0xFF), b8: Int($0 >> 8 & 0xFF)) }
            let strip = ink.map { Self.inkMask(sheet, ink: $0) } ?? sheet
            let cells = (0..<10).compactMap { Self.part(strip, $0 * K.digitWidth, 0, K.digitWidth, K.digitHeight) }
            digits = cells.count == 10 ? cells : []
            if strip.width >= K.digitsWithMinusWidth { minus = Self.part(strip, K.digitsWidth, 0, K.digitWidth, K.digitHeight) }
        }
    }

    /// The frame for a slider position 0…1: the nearest of the 28.
    public static func volumeFrameIndex(for fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * Double(volumeFrameCount - 1)).rounded())
    }

    static func part(_ image: RGBAImage, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGImage? {
        image.crop(x: x, y: y, width: w, height: h).map(PixelScaler.scale4x)?.cgImage()
    }

    /// Every colour of the blank cell: the LED background, dotted in some skins.
    static func paper(_ strip: RGBAImage) -> Set<UInt32> {
        var colors = Set<UInt32>()
        for y in 0..<SkinSprites.digitHeight { for x in 90..<SkinSprites.digitsWidth { colors.insert(strip[x, y]) } }
        return colors
    }

    /// Digit 8's most common colour that isn't paper: the lit segments.
    static func inkPixel(_ strip: RGBAImage) -> UInt32? {
        guard strip.width >= SkinSprites.digitsWidth, strip.height >= SkinSprites.digitHeight else { return nil }
        let paper = paper(strip)
        var counts: [UInt32: Int] = [:]
        for y in 0..<SkinSprites.digitHeight {
            for x in 72..<81 where !paper.contains(strip[x, y]) { counts[strip[x, y], default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    /// The digits as shapes: opaque white where a pixel is closer to the ink than to every paper colour, transparent
    /// elsewhere. The app tints them, so a dotted LED background can't blur into the strokes when scaled.
    static func inkMask(_ strip: RGBAImage, ink: UInt32) -> RGBAImage {
        let paper = paper(strip)
        func distance(_ a: UInt32, _ b: UInt32) -> Int {
            [24, 16, 8].reduce(0) { $0 + abs(Int(a >> UInt32($1) & 0xFF) - Int(b >> UInt32($1) & 0xFF)) }
        }
        var out = strip
        out.pixels = strip.pixels.map { p in
            if paper.contains(p) { return 0 }
            let nearestPaper = paper.map { distance(p, $0) }.min() ?? .max
            return distance(p, ink) < nearestPaper ? 0xFFFF_FFFF : 0
        }
        return out
    }
}
