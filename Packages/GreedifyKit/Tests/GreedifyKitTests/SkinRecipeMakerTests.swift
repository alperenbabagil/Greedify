import Foundation
import Testing
@testable import GreedifyKit

/// The converter that drafts a curated recipe from a `.wsz` (curated skins spec §5). Synthetic skins only.
struct SkinRecipeMakerTests {
    typealias S = SkinSheets
    func bitmap(_ w: Int, _ h: Int, _ px: @escaping (Int, Int) -> S.RGB) -> SkinBitmap { S.bitmap(BMPBuilder.make(width: w, height: h, pixel: px)) }
    func c(_ rgb: S.RGB) -> ThemeColor { S.color(rgb) }

    @Test func aDottedDisplayIsADotGrid() {
        let navy: S.RGB = (0x10, 0x1C, 0x48), dot: S.RGB = (0x24, 0x34, 0x6A)
        let dotted = bitmap(275, 116) { x, y in x % 2 == 0 && y % 2 == 0 ? dot : navy }
        #expect(SkinRecipeMaker.lcdMaterial(main: dotted) == .dotGrid(base: c(navy), dot: c(dot), pitch: 2, size: 1))
        let flat = bitmap(275, 116) { _, _ in navy }
        #expect(SkinRecipeMaker.lcdMaterial(main: flat) == .solid(c(navy)))
    }

    @Test func sevenSegmentDigitsAreSegments() {
        #expect(SkinRecipeMaker.digits(numbers: SkinRecipeMakerTests.segmentSheet()) == .segment)
        let blob = S.bitmap(BMPBuilder.make(width: 99, height: 13) { x, y in (x / 9 < 10 && (x % 9 + y) % 3 == 0) ? (255, 255, 255) : (0, 0, 0) })
        #expect(SkinRecipeMaker.digits(numbers: blob) == .pixel)
        #expect(SkinRecipeMaker.digits(numbers: nil) == .mono)
    }

    /// A 7-segment 8 in every digit cell: bars at rows 0, 6 and 12, sides at columns 1 and 7.
    static func segmentSheet() -> SkinBitmap {
        S.bitmap(BMPBuilder.make(width: 99, height: 13) { x, y in
            let cx = x % 9
            guard x < 90 else { return (0, 0, 0) }
            let bar = (y == 0 || y == 6 || y == 12) && (2...6).contains(cx)
            let side = (cx == 1 || cx == 7) && y != 0 && y != 6 && y != 12
            return bar || side ? (255, 255, 255) : (0, 0, 0)
        })
    }

    @Test func buttonShapes() {
        func sheet(_ inside: @escaping (Int, Int) -> Bool) -> SkinBitmap {
            bitmap(136, 36) { x, y in
                guard (23..<46).contains(x), y < 18 else { return (0x10, 0x10, 0x10) }
                return inside(x - 23, y) ? (0x60, 0x70, 0xA0) : (0x10, 0x10, 0x10)
            }
        }
        #expect(SkinRecipeMaker.buttonShape(cbuttons: sheet { _, _ in true }) == .rect)
        #expect(SkinRecipeMaker.buttonShape(cbuttons: sheet { x, y in !((x == 0 || x == 22) && (y == 0 || y == 17)) }) == .rounded)
        #expect(SkinRecipeMaker.buttonShape(cbuttons: sheet { x, y in
            let dx = Double(x) - 11, dy = Double(y) - 8.5
            return dx * dx / 121 + dy * dy / 72 <= 1
        }) == .circle)
    }

    @Test func theVolumeRampComesFromThreeFrames() {
        let volume = S.bitmap(S.volume())                                   // frame i is red 9·i
        let ramp = SkinRecipeMaker.volumeRamp(volume: volume)
        #expect(ramp == [c((0, 0x40, 0x40)), c((126, 0x40, 0x40)), c((243, 0x40, 0x40))])
    }

    @Test func surfaceMaterials() {
        let flat = bitmap(275, 116) { _, _ in (0x40, 0x40, 0x48) }
        #expect(SkinRecipeMaker.surfaceMaterial(main: flat) == .solid(c((0x40, 0x40, 0x48))))
        var rng = SplitMix64(seed: 1)
        let grain = (0..<(275 * 116)).map { _ in UInt8(0x40 + Int(rng.unit() * 40)) }
        let noisy = bitmap(275, 116) { x, y in let v = grain[y * 275 + x]; return (v, v, v) }
        guard case .noise = SkinRecipeMaker.surfaceMaterial(main: noisy) else { Issue.record("expected noise"); return }
        let rows = (0..<116).map { _ in UInt8(0x90 + Int(rng.unit() * 40)) }
        let brushed = bitmap(275, 116) { _, y in (rows[y], rows[y], rows[y]) }
        guard case .brushed = SkinRecipeMaker.surfaceMaterial(main: brushed) else { Issue.record("expected brushed"); return }
    }

    @Test func aWholeSkinBecomesAStrictRecipe() throws {
        let files: [String: Data] = [
            "pledit.txt": Data(SkinFixture.classicPledit.utf8), "main.bmp": S.main(), "cbuttons.bmp": S.cbuttons(),
            "shufrep.bmp": S.shufrep(), "posbar.bmp": S.posbar(), "volume.bmp": S.volume(), "nums_ex.bmp": S.numbers(minus: true),
        ]
        let draft = try SkinRecipeMaker.recipe(fromArchive: SkinFixture.wsz(files), name: "Test Skin", fileName: "test.wsz")
        let style = try #require(draft.theme.style)
        #expect(draft.theme.name == "Test Skin" && draft.theme.source == "Winamp skin test.wsz")
        #expect(style.bar?.layout == .winamp && style.lcd != nil && style.button?.face != nil && style.volume?.fill?.kind == .ramp)
        #expect(style.rows.selected?.fill == .solid(ThemeColor(hex: "#0000C6")!))
        #expect(draft.theme.images.backdrop == nil && draft.theme.controls == nil)   // no bitmaps in a recipe
        #expect(!draft.notes.isEmpty && draft.contactSheet.map(ThemeImage.isPNG) == true)
        _ = try Style.$strict.withValue(true) { try Theme.decode(from: draft.theme.encoded()) }
    }
}
