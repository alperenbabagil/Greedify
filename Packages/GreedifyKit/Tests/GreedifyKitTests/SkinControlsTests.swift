import CoreGraphics
import Foundation
import Testing
@testable import GreedifyKit

struct SkinControlPaletteTests {
    typealias S = SkinSheets

    func palette(cbuttons: Data = S.cbuttons()) -> Theme.Controls? {
        SkinControlPalette.make(cbuttons: S.bitmap(cbuttons), shufrep: S.bitmap(S.shufrep()), main: S.bitmap(S.main()))
    }

    @Test func samplesThePlayButton() throws {
        let c = try #require(palette())
        #expect(c.faceTop == S.color(S.faceTop))
        #expect(c.faceBottom == S.color(S.faceBottom))
        #expect(c.highlight == S.color(S.highlight))
        #expect(c.shadow == S.color(S.shadow))
        #expect(c.glyph == S.color(S.glyph))
        #expect(c.pressedFaceTop == S.color(S.pressedTop))
        #expect(c.pressedFaceBottom == S.color(S.pressedBottom))
        #expect(c.pressedGlyph == S.color(S.pressedGlyph))
    }

    @Test func findsTheLitIndicatorAndThePanel() throws {
        let c = try #require(palette())
        #expect(c.on == S.color(S.lit))
        #expect(c.panel == S.color(S.panel))
    }

    @Test func aGlyphThatBarelyShowsFallsBack() throws {
        let c = try #require(palette(cbuttons: S.cbuttons(glyphColor: (0x68, 0x78, 0xA8))))
        #expect(c.glyph == nil)
        #expect(c.faceTop == S.color(S.faceTop))
    }

    /// Review focus 1: a sheet larger than standard is still read at the standard coordinates.
    @Test func largerSheetsStillWork() throws {
        let c = try #require(palette(cbuttons: S.cbuttons(width: 200, height: 50)))
        #expect(c.faceTop == S.color(S.faceTop))
    }

    @Test func aSmallCbuttonsGivesNoControls() {
        #expect(palette(cbuttons: S.cbuttons(width: 100, height: 36)) == nil)
        #expect(SkinControlPalette.make(cbuttons: nil, shufrep: nil, main: S.bitmap(S.main())) == nil)
    }
}

struct SkinSpritesTests {
    typealias S = SkinSheets
    func decode(_ png: Data?) throws -> RGBAImage { try #require(png.flatMap { ThemeImage.cgImage($0) }.flatMap(RGBAImage.init)) }
    func rgba(_ c: S.RGB) -> UInt32 { UInt32(c.0) << 24 | UInt32(c.1) << 16 | UInt32(c.2) << 8 | 0xFF }

    @Test func seekBarKeepsGrooveAndBothHandles() throws {
        let strip = try decode(SkinSprites.seekBarPNG(from: S.posbar()))
        #expect(strip.width == 307 && strip.height == 10)
        #expect(strip[10, 5] == rgba(S.groove) && strip[250, 5] == rgba(S.handle) && strip[280, 5] == rgba(S.handlePressed))
    }

    @Test func aNarrowPosbarReusesTheHandleAsPressed() throws {
        let strip = try decode(SkinSprites.seekBarPNG(from: S.posbar(width: 280)))
        #expect(strip.width == 307 && strip[280, 5] == rgba(S.handle))
        #expect(SkinSprites.seekBarPNG(from: S.posbar(width: 270)) == nil)
    }

    /// Review focus 4: frames without handles are kept.
    @Test func volumeKeepsItsFramesWithOrWithoutHandles() throws {
        #expect(try decode(SkinSprites.volumePNG(from: S.volume())).height == 433)
        #expect(try decode(SkinSprites.volumePNG(from: S.volume(height: 420))).height == 420)
        #expect(SkinSprites.volumePNG(from: S.volume(height: 400)) == nil)
    }

    @Test func digitsPreferNumsEx() throws {
        #expect(try decode(SkinSprites.digitsPNG(numbers: S.numbers(), numsEx: nil)).width == 99)
        #expect(try decode(SkinSprites.digitsPNG(numbers: S.numbers(), numsEx: S.numbers(minus: true))).width == 108)
        #expect(SkinSprites.digitsPNG(numbers: nil, numsEx: nil) == nil)
    }

    @Test func importCarriesControlsAndImages() throws {
        let files: [String: Data] = [
            "pledit.txt": Data(SkinFixture.classicPledit.utf8), "main.bmp": S.main(), "cbuttons.bmp": S.cbuttons(),
            "shufrep.bmp": S.shufrep(), "posbar.bmp": S.posbar(), "VOLUME.BMP": S.volume(), "nums_ex.bmp": S.numbers(minus: true),
        ]
        let theme = try SkinThemeMapper.theme(fromArchive: SkinFixture.wsz(files), fileName: "t.wsz", installedFonts: [])
        #expect(theme.controls?.isUsable == true)
        #expect(theme.images.seekBar != nil && theme.images.volume != nil && theme.images.digits != nil)
        var missing = files; missing["VOLUME.BMP"] = nil
        let partial = try SkinThemeMapper.theme(fromArchive: SkinFixture.wsz(missing), fileName: "t.wsz", installedFonts: [])
        #expect(partial.images.volume == nil && partial.images.seekBar != nil && partial.controls != nil)
    }
}

struct SkinControlImagesTests {
    typealias S = SkinSheets
    func rgba(_ c: S.RGB) -> UInt32 { UInt32(c.0) << 24 | UInt32(c.1) << 16 | UInt32(c.2) << 8 | 0xFF }
    func images(volumeHeight: Int = 433, minus: Bool = true) -> Theme.Images {
        Theme.Images(seekBar: SkinSprites.seekBarPNG(from: S.posbar()), volume: SkinSprites.volumePNG(from: S.volume(height: volumeHeight)),
                     digits: minus ? SkinSprites.digitsPNG(numbers: nil, numsEx: S.numbers(minus: true))
                                   : SkinSprites.digitsPNG(numbers: S.numbers(), numsEx: nil))
    }
    func first(_ image: CGImage?) -> UInt32? { image.flatMap(RGBAImage.init).map { $0[0, 0] } }

    @Test func slicesAndScalesEveryPart() throws {
        let c = SkinControlImages(images())
        #expect(c.groove?.width == 992 && c.groove?.height == 40)
        #expect(c.handle?.width == 116 && c.handlePressed?.height == 40)
        #expect(first(c.groove) == rgba(S.groove) && first(c.handle) == rgba(S.handle) && first(c.handlePressed) == rgba(S.handlePressed))
        #expect(c.volumeFrames.count == 28 && c.volumeFrames.allSatisfy { $0.width == 272 && $0.height == 52 })
        #expect(first(c.volumeFrames[27]) == UInt32(9 * 27) << 24 | 0x40 << 16 | 0x40 << 8 | 0xFF)
        #expect(c.volumeHandle?.width == 56 && c.volumeHandlePressed?.height == 44)
        #expect(c.digits.count == 10 && c.digits.allSatisfy { $0.width == 36 && $0.height == 52 })
        #expect(c.minus != nil)
        #expect(c.digitInk == S.color(S.ink))
    }

    @Test func handlelessVolumeAndMinuslessDigits() {
        let c = SkinControlImages(images(volumeHeight: 420, minus: false))
        #expect(c.volumeFrames.count == 28 && c.volumeHandle == nil && c.volumeHandlePressed == nil)
        #expect(c.digits.count == 10 && c.minus == nil)
    }

    /// Review focus 3: before the images decode (or without them) every part is missing, so views fall back.
    @Test func emptyHasNoParts() {
        for c in [SkinControlImages.empty, SkinControlImages(Theme.Images())] {
            #expect(c.groove == nil && c.handle == nil && c.volumeFrames.isEmpty && c.digits.isEmpty && c.digitInk == nil)
        }
    }

    /// Review focus 2: the ends and anything out of range stay inside the 28 frames.
    @Test func volumeFrameIndexStaysInRange() {
        #expect(SkinControlImages.volumeFrameIndex(for: 0) == 0)
        #expect(SkinControlImages.volumeFrameIndex(for: 1) == 27)
        #expect(SkinControlImages.volumeFrameIndex(for: 0.5) == 14)
        #expect(SkinControlImages.volumeFrameIndex(for: -0.2) == 0)
        #expect(SkinControlImages.volumeFrameIndex(for: 1.3) == 27)
    }
}

struct SkinDigitMaskTests {
    /// Winamp5_Classified-style digits: white strokes on a dotted navy LED background. Drawn as pictures the dots
    /// blur into the strokes, so the digits are kept as ink shapes: paper transparent, ink opaque.
    @Test func dottedPaperBecomesTransparent() throws {
        let navy: SkinSheets.RGB = (0x10, 0x20, 0x60), dot: SkinSheets.RGB = (0x30, 0x40, 0x90), white: SkinSheets.RGB = (0xFF, 0xFF, 0xFF)
        let sheet = BMPBuilder.make(width: 99, height: 13) { x, y in
            if x < 90, x % 9 == 4 { return white }                 // one vertical stroke per digit
            return (x + y) % 2 == 0 ? dot : navy                   // dotted paper, blank cell included
        }
        let images = SkinControlImages(Theme.Images(digits: SkinSprites.digitsPNG(numbers: sheet, numsEx: nil)))
        let eight = try #require(images.digits.count == 10 ? RGBAImage(images.digits[8]) : nil)
        #expect(eight[4 * 4 + 1, 20] & 0xFF == 0xFF)               // the stroke (source x 4, scaled 4×) is opaque
        #expect(eight[0, 20] & 0xFF == 0 && eight[35, 51] & 0xFF == 0)   // the dotted paper is transparent
        #expect(images.digitInk == SkinSheets.color(white))
    }
}
