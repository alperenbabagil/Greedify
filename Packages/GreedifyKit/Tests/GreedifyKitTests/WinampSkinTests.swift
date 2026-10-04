import Foundation
import Testing
@testable import GreedifyKit

private func hex(_ s: String) -> ThemeColor { ThemeColor(hex: s)! }
private func close(_ a: ThemeColor?, _ b: ThemeColor) -> Bool {
    guard let a else { return false }
    return abs(a.r - b.r) < 3 / 255 && abs(a.g - b.g) < 3 / 255 && abs(a.b - b.b) < 3 / 255
}

struct WinampSkinTests {
    @Test func pleditQuirks() throws {
        let text = "[Text]\r\nnormal=00FF00 ; green\r\nCurrent=#FFFFFF\r\nNormalBG=#000000\r\nSelectedBG = #0000C6\r\nFont=Arial Narrow\r\n[Other]\r\nNormal=#FF0000\r\n"
        let p = try #require(WinampSkin.parsePledit(text))
        #expect(p.normal == hex("#00FF00"))
        #expect(p.current == hex("#FFFFFF"))
        #expect(p.normalBG == hex("#000000"))
        #expect(p.selectedBG == hex("#0000C6"))
        #expect(p.font == "Arial Narrow")
        #expect(WinampSkin.parsePledit("[Other]\nNormal=#FF0000\n") == nil)
    }

    @Test func pleditInWindowsEncoding() throws {
        let pledit = try #require("[Text]\r\nNormal=#00FF00 ; green\r\nFont=Café Sans ; my font\r\n".data(using: .windowsCP1252))
        let skin = try WinampSkin(archive: SkinFixture.wsz(["pledit.txt": pledit]))
        #expect(skin.playlist?.normal == hex("#00FF00"))
        #expect(skin.playlist?.font == "Café Sans")
    }

    @Test func viscolorSkipsCommentsAndBadLines() {
        let colors = WinampSkin.parseViscolor("0,0,0, // background\n24,33,41,\n\n// comment only\n255, 0, 0\n300,0,0\n")
        #expect(colors == [hex("#000000"), hex("#182129"), hex("#FF0000")])
    }

    @Test func frameColorIsTheDominantBorderColor() throws {
        let main = BMPBuilder.make(width: 275, height: 116) { x, y in
            if y < 14 || y >= 102 { return x % 50 == 0 ? (255, 0, 0) : (0x20, 0x40, 0xA0) } // blue border, a few red pixels
            return (0, 200, 0)                                                              // green middle
        }
        let skin = try WinampSkin(archive: SkinFixture.wsz(["main.bmp": main]))
        #expect(close(skin.frameColor, hex("#2040A0")))
    }

    @Test func genexColorsComeFromTheirPixels() throws {
        let swatches: [Int: (UInt8, UInt8, UInt8)] = [48: (0x10, 0x20, 0x30), 50: (255, 255, 255), 60: (0, 0, 0xC0)]
        let genex = BMPBuilder.make(width: 100, height: 20) { x, y in
            y == 0 ? (swatches[x] ?? (0x55, 0x55, 0x55)) : (0x55, 0x55, 0x55)
        }
        let skin = try WinampSkin(archive: SkinFixture.wsz(["genex.bmp": genex]))
        #expect(close(skin.genex?.itemBackground, hex("#102030")))
        #expect(close(skin.genex?.itemForeground, hex("#FFFFFF")))
        #expect(close(skin.genex?.selectionBackground, hex("#0000C0")))
    }

    @Test func readsSkinsInsideAFolder() throws {
        let skin = try WinampSkin(archive: SkinFixture.wsz(["PLEDIT.TXT": Data(SkinFixture.classicPledit.utf8)], folder: "Green/"))
        #expect(skin.playlist?.normal == hex("#00FF00"))
    }

    @Test func modernSkinsAreRejected() {
        let data = SkinFixture.wsz(["skin.xml": Data("<WinampAbstractionLayer/>".utf8)])
        #expect(throws: ThemeImportError.unsupportedModernSkin) { try WinampSkin(archive: data) }
    }

    @Test func skinsWithoutColorFilesAreRejected() {
        let data = SkinFixture.wsz(["readme.txt": Data("hi".utf8)])
        #expect(throws: ThemeImportError.noColorSources) { try WinampSkin(archive: data) }
    }

    @Test func garbageIsUnreadable() {
        #expect(throws: ThemeImportError.unreadable) { try WinampSkin(archive: Data("nope".utf8)) }
    }

    @Test func errorMessagesArePlainWords() {
        #expect(ThemeImportError.unsupportedModernSkin.errorDescription == "This looks like a Winamp 3/5 skin; only classic (.wsz) skins are supported.")
        #expect(ThemeImportError.noColorSources.errorDescription == "No color files found in this skin.")
        #expect(ThemeImportError.unreadable.errorDescription == "Couldn't read this file.")
    }

    @Test func mainAndTextBitmapsBecomePNGsAtNativeSize() throws {
        let main = BMPBuilder.make(width: 275, height: 116) { x, _ in (UInt8(x % 256), 40, 60) }
        let text = BMPBuilder.make(width: 155, height: 18) { _, _ in (0, 0, 0) }
        let skin = try WinampSkin(archive: SkinFixture.wsz(["main.bmp": main, "text.bmp": text]))
        let backdrop = try #require(skin.backdropPNG.flatMap(ThemeImage.cgImage))
        #expect(ThemeImage.isPNG(skin.backdropPNG!))
        #expect(backdrop.width == 275 && backdrop.height == 116)
        let font = try #require(skin.pixelFontPNG.flatMap(ThemeImage.cgImage))
        #expect(font.width == 155 && font.height == 18)
    }

    @Test func smallTextBitmapIsIgnored() throws {
        let text = BMPBuilder.make(width: 100, height: 10) { _, _ in (0, 0, 0) }
        let skin = try WinampSkin(archive: SkinFixture.wsz(["pledit.txt": Data(SkinFixture.classicPledit.utf8), "text.bmp": text]))
        #expect(skin.pixelFontPNG == nil)
    }

    @Test func skinsWithoutImagesStillImport() throws {
        let skin = try WinampSkin(archive: SkinFixture.wsz(["pledit.txt": Data(SkinFixture.classicPledit.utf8)]))
        #expect(skin.backdropPNG == nil && skin.pixelFontPNG == nil)
    }
}
