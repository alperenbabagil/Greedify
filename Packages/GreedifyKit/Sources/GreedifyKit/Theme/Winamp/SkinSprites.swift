import Foundation

/// Crops a classic skin's seek bar, volume and digit sheets into the PNGs a theme keeps (skinned controls spec §2, §3.3).
enum SkinSprites {
    static let grooveWidth = 248, handleWidth = 29, handleX = 248, pressedHandleX = 278, barHeight = 10, seekStripWidth = 307
    static let volumeWidth = 68, volumeMinHeight = 418, volumeFullHeight = 433
    static let digitWidth = 9, digitHeight = 13, digitsWidth = 99, digitsWithMinusWidth = 108

    static func decode(_ data: Data?) -> RGBAImage? { data.flatMap { ThemeImage.cgImage($0) }.flatMap(RGBAImage.init) }
    static func png(_ image: RGBAImage) -> Data? { image.cgImage().flatMap(ThemeImage.png) }

    /// A 307×10 strip: groove, handle, pressed handle. A posbar too narrow for the pressed handle reuses the normal one.
    static func seekBarPNG(from data: Data) -> Data? {
        guard let src = decode(data),
              let base = src.crop(x: 0, y: 0, width: handleX + handleWidth, height: barHeight),
              let handle = base.crop(x: handleX, y: 0, width: handleWidth, height: barHeight) else { return nil }
        var strip = RGBAImage(width: seekStripWidth, height: barHeight, fill: 0)
        strip.paste(base, x: 0, y: 0)
        strip.paste(src.crop(x: pressedHandleX, y: 0, width: handleWidth, height: barHeight) ?? handle, x: pressedHandleX, y: 0)
        return png(strip)
    }

    /// The 28 frames, plus the handles when the sheet is tall enough to hold them.
    static func volumePNG(from data: Data) -> Data? {
        guard let src = decode(data), src.height >= volumeMinHeight,
              let sheet = src.crop(x: 0, y: 0, width: volumeWidth, height: min(src.height, volumeFullHeight)) else { return nil }
        return png(sheet)
    }

    /// `nums_ex.bmp` (with a minus) wins over `numbers.bmp`.
    static func digitsPNG(numbers: Data?, numsEx: Data?) -> Data? {
        if let strip = decode(numsEx)?.crop(x: 0, y: 0, width: digitsWithMinusWidth, height: digitHeight) { return png(strip) }
        if let strip = decode(numbers)?.crop(x: 0, y: 0, width: digitsWidth, height: digitHeight) { return png(strip) }
        return nil
    }
}
