import Foundation
import Testing
@testable import GreedifyKit

struct PixelFontTests {
    func at(_ c: Character) -> [Int] { let cell = PixelFont.cell(for: c); return [cell.row, cell.column] }

    @Test func glyphMap() {
        #expect(at("A") == [0, 0])
        #expect(at("Z") == [0, 25])
        #expect(at("\"") == [0, 26])
        #expect(at("@") == [0, 27])
        #expect(at(" ") == [0, 30])
        #expect(at("0") == [1, 0])
        #expect(at("9") == [1, 9])
        #expect(at("…") == [1, 10])
        #expect(at(".") == [1, 11])
        #expect(at("#") == [1, 30])
        #expect(at("Å") == [2, 0])
        #expect(at("*") == [2, 4])
    }

    @Test func lowercaseAndDiacriticsFold() {
        #expect(at("a") == [0, 0])
        #expect(PixelFont.glyphs(for: "Oğlan qızı").map { $0.column } == PixelFont.glyphs(for: "OGLAN QIZI").map { $0.column })
        #expect(PixelFont.glyphs(for: "Oğlan qızı").map { $0.row } == PixelFont.glyphs(for: "OGLAN QIZI").map { $0.row })
        #expect(at("ö") == [2, 1]) // Ö has its own glyph
    }

    @Test func unknownAndEmptyTitles() {
        #expect(PixelFont.glyphs(for: "").isEmpty)
        #expect(at("日") == [0, 30])
        #expect(at("🎵") == [0, 30])
        #expect(at("ß") == [0, 30])
    }

    /// Black paper; cell (0,0) has ink at its top-left and bottom-right pixels only.
    func fontPNG(paper: (UInt8, UInt8, UInt8) = (0, 0, 0)) -> Data {
        PNGFixture.make(width: 155, height: 18) { x, y in
            (x == 0 && y == 0) || (x == 4 && y == 5) ? (0, 255, 0) : paper
        }
    }

    @Test func masksMarkInk() throws {
        let font = try #require(PixelFont(png: fontPNG()))
        let a = font.mask(row: 0, column: 0)
        #expect(a.count == 30)
        #expect(a[0] && a[29])
        #expect(a.filter { $0 }.count == 2)
        #expect(!font.mask(row: 1, column: 0).contains(true))
        #expect(!font.mask(row: 0, column: 30).contains(true)) // space
    }

    @Test func smallOrUndecodableImagesAreRejected() {
        #expect(PixelFont(png: PNGFixture.make(width: 100, height: 10) { _, _ in (0, 0, 0) }) == nil)
        #expect(PixelFont(png: Data("nope".utf8)) == nil)
    }

    @Test func patternedPaperIsRejected() {
        // Ink in the space cell means the font has no plain paper to measure against.
        let png = PNGFixture.make(width: 155, height: 18) { x, y in (x + y) % 2 == 0 ? (255, 255, 255) : (0, 0, 0) }
        #expect(PixelFont(png: png) == nil)
    }
}

struct PixelFontShadingTests {
    /// Glow-style glyphs: a bright core with a dim halo around it on black paper. The halo is shading, not ink,
    /// or every glyph fills its cell and the title reads as blocks.
    @Test func dimShadingIsNotInk() throws {
        let png = PNGFixture.make(width: 155, height: 18) { x, y in
            guard x < 5, y < 6 else { return (0, 0, 0) }        // cell "A": core column 2, halo everywhere else
            return x == 2 ? (255, 255, 0) : (70, 70, 0)
        }
        let font = try #require(PixelFont(png: png))
        let a = font.mask(row: 0, column: 0)
        #expect((0..<6).allSatisfy { a[$0 * 5 + 2] })          // the core is ink
        #expect(a.enumerated().filter { $0.offset % 5 != 2 }.allSatisfy { !$0.element })   // the halo isn't
    }
}
