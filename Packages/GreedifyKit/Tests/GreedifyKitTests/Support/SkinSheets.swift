import Foundation
@testable import GreedifyKit

/// Standard-size Winamp sprite sheets with known colours (never real skins: those belong to their authors).
enum SkinSheets {
    typealias RGB = (UInt8, UInt8, UInt8)
    static let back: RGB = (0x10, 0x10, 0x10)
    static let highlight: RGB = (0xC0, 0xC8, 0xE0), shadow: RGB = (0x20, 0x28, 0x40)
    static let faceTop: RGB = (0x60, 0x70, 0xA0), faceBottom: RGB = (0x40, 0x50, 0x80), glyph: RGB = (0xF0, 0xF0, 0xF0)
    static let pressedTop: RGB = (0x40, 0x50, 0x78), pressedBottom: RGB = (0x30, 0x40, 0x68), pressedGlyph: RGB = (0xFF, 0xFF, 0xFF)
    static let lit: RGB = (0x7C, 0xFF, 0x4F), panel: RGB = (0x4A, 0x5A, 0x86)
    static let groove: RGB = (0x11, 0x22, 0x33), handle: RGB = (0xA0, 0xA0, 0xA0), handlePressed: RGB = (0xB0, 0xB0, 0xB0)
    static let ink: RGB = (0x00, 0xC8, 0x00)

    static func color(_ c: RGB) -> ThemeColor { ThemeColor(r8: Int(c.0), g8: Int(c.1), b8: Int(c.2)) }
    static func bitmap(_ data: Data) -> SkinBitmap { SkinBitmap(data: data)! }

    /// Play button at (23, 0, 23, 18), pressed at (23, 18, 23, 18): a highlight top/left edge, a shadow bottom/right
    /// edge, a face darker in its lower half, and a 6×6 glyph at x 31…36, y 6…11 (offset by 18 when pressed).
    static func cbuttons(width: Int = 136, height: Int = 36, glyphColor: RGB = glyph) -> Data {
        BMPBuilder.make(width: width, height: height) { x, y in
            guard (23..<46).contains(x), y < 36 else { return back }
            let pressed = y >= 18, top = pressed ? 18 : 0, ly = y - top
            if ly == 0 || x == 23 { return highlight }
            if ly == 17 || x == 45 { return shadow }
            if (31...36).contains(x), (6...11).contains(ly) { return pressed ? pressedGlyph : glyphColor }
            return ly < 9 ? (pressed ? pressedTop : faceTop) : (pressed ? pressedBottom : faceBottom)
        }
    }

    /// Grey sheet with a lit indicator inside the shuffle-on sprite (28, 30, 47, 15).
    static func shufrep() -> Data {
        BMPBuilder.make(width: 92, height: 85) { x, y in (40..<44).contains(x) && (36..<39).contains(y) ? lit : (0x30, 0x30, 0x30) }
    }

    /// Mostly red, with the control area (rows 88…115) in the panel colour.
    static func main() -> Data { BMPBuilder.make(width: 275, height: 116) { _, y in y >= 88 ? panel : (0x90, 0x10, 0x10) } }

    /// Groove over x 0…247, handle at 248…276, pressed handle at 278…306 (when wide enough).
    static func posbar(width: Int = 307) -> Data {
        BMPBuilder.make(width: width, height: 10) { x, _ in x < 248 ? groove : x < 277 ? handle : x >= 278 ? handlePressed : back }
    }

    /// Frame i (rows 15i…15i+12) is filled with red = 9·i; the handles at y 422 are pressed (x 0…13) and normal (x 15…28).
    static func volume(height: Int = 433) -> Data {
        BMPBuilder.make(width: 68, height: height) { x, y in
            if y >= 422 { return x < 14 ? handlePressed : (15..<29).contains(x) ? handle : back }
            return y % 15 < 13 ? (UInt8(9 * (y / 15)), 0x40, 0x40) : back
        }
    }

    /// Digit d (x 9d…9d+8) is black paper with an ink column at x = 9d + d % 9; the blank cell (x 90…98) is paper only.
    /// With `minus`, 108 px wide and an ink row across x 99…107 at y 6.
    static func numbers(minus: Bool = false) -> Data {
        BMPBuilder.make(width: minus ? 108 : 99, height: 13) { x, y in
            if x >= 99 { return y == 6 ? ink : (0, 0, 0) }
            let d = x / 9
            return d < 10 && x == 9 * d + d % 9 ? ink : (0, 0, 0)
        }
    }
}
