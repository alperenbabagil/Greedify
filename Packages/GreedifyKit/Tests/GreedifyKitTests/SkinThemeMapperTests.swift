import Foundation
import Testing
@testable import GreedifyKit

private func hex(_ s: String) -> ThemeColor { ThemeColor(hex: s)! }
private let fonts = ["Arial"]

struct SkinThemeMapperTests {
    let green = WinampSkin(playlist: .init(normal: hex("#00FF00"), current: hex("#FFFFFF"), normalBG: hex("#000000"),
                                           selectedBG: hex("#0000C6"), font: "Arial"),
                           visColors: [hex("#000000"), hex("#181818"), hex("#10107F"), hex("#FF8000")],
                           frameColor: hex("#3A3A5A"), genex: nil)

    @Test func mapsAClassicGreenSkin() {
        let t = SkinThemeMapper.theme(from: green, fileName: "Green Machine.wsz", installedFonts: fonts)
        #expect(t.name == "Green Machine")
        #expect(t.source == "Winamp skin Green Machine.wsz")
        #expect(t.base == .dark)
        #expect(t.colors.background == hex("#000000"))
        #expect(t.colors.text == hex("#00FF00"))
        #expect(t.colors.selection == hex("#0000C6"))
        #expect(t.colors.surface == hex("#3A3A5A"))
        #expect(t.colors.lyricsText == t.colors.text)
        #expect(t.colors.divider == hex("#00FF00").withAlpha(0.15))
        #expect(t.shapes == Theme.Shapes(cardRadius: 2, buttonRadius: 2, artworkRadius: 2, rowRadius: 2, borderWidth: 1,
                                         buttonStyle: .bevel, density: .compact))
        #expect(t.lyrics == .solid)
        #expect(t.fonts.family == "Arial")
    }

    @Test func accentIsTheMostSaturatedReadableColor() {
        let t = SkinThemeMapper.theme(from: green, fileName: "g.wsz", installedFonts: fonts)
        // White "current" isn't saturated, and #10107F is too dark on black, so the orange wins.
        #expect(t.colors.accent == hex("#FF8000"))
        #expect(t.colors.onAccent == .black)
    }

    @Test func unreadableTextIsPushedToReadable() {
        let skin = WinampSkin(playlist: .init(normal: hex("#202020"), normalBG: hex("#000000")))
        let t = SkinThemeMapper.theme(from: skin, fileName: "dim.wsz", installedFonts: fonts)
        #expect(t.colors.text.contrast(with: t.colors.background) >= 4.5)
        #expect(t.colors.textSecondary.contrast(with: t.colors.background) >= 3)
    }

    @Test func lightSkinsGetALightBase() {
        let skin = WinampSkin(playlist: .init(normal: hex("#000000"), normalBG: hex("#F0F0F0")))
        let t = SkinThemeMapper.theme(from: skin, fileName: "light.wsz", installedFonts: fonts)
        #expect(t.base == .light)
        #expect(t.colors.surface == hex("#F0F0F0").blended(toward: .black, 0.08)) // no main.bmp: shifted background
    }

    @Test func surfaceFallsBackWhenFrameMatchesBackground() {
        var skin = green
        skin.frameColor = hex("#020202")
        let t = SkinThemeMapper.theme(from: skin, fileName: "g.wsz", installedFonts: fonts)
        #expect(t.colors.surface == ThemeColor.black.blended(toward: .white, 0.08))
    }

    @Test func surfaceFallsBackWhenTextIsUnreadableOnIt() {
        var skin = green
        skin.frameColor = hex("#00C000") // green frame under green text
        let t = SkinThemeMapper.theme(from: skin, fileName: "g.wsz", installedFonts: fonts)
        #expect(t.colors.surface == ThemeColor.black.blended(toward: .white, 0.08))
    }

    @Test func missingFontsAreDropped() {
        #expect(SkinThemeMapper.theme(from: green, fileName: "g.wsz", installedFonts: []).fonts.family == nil)
    }

    @Test func genexOverridesPledit() {
        var skin = green
        skin.genex = .init(itemBackground: hex("#102030"), itemForeground: hex("#E0E0E0"), windowBackground: hex("#000000"),
                           buttonText: hex("#FFFFFF"), windowText: hex("#FFFFFF"), divider: hex("#333333"),
                           selectionBackground: hex("#405060"))
        let t = SkinThemeMapper.theme(from: skin, fileName: "g.wsz", installedFonts: fonts)
        #expect(t.colors.background == hex("#102030"))
        #expect(t.colors.text == hex("#E0E0E0"))
        #expect(t.colors.selection == hex("#405060"))
    }

    @Test func frameOnlySkinsUseTheFrame() {
        let t = SkinThemeMapper.theme(from: WinampSkin(frameColor: hex("#203040")), fileName: "f.wsz", installedFonts: fonts)
        #expect(t.colors.background == hex("#203040"))
        #expect(t.colors.text == .white)
    }

    @Test func walFilesAreRejected() {
        #expect(throws: ThemeImportError.unsupportedModernSkin) {
            try SkinThemeMapper.theme(fromArchive: Data(), fileName: "Big Bento.wal", installedFonts: fonts)
        }
    }

    @Test func importsAnArchiveEndToEnd() throws {
        let data = SkinFixture.wsz(["pledit.txt": Data(SkinFixture.classicPledit.utf8)])
        let t = try SkinThemeMapper.theme(fromArchive: data, fileName: "Green.wsz", installedFonts: fonts)
        #expect(t.colors.text == hex("#00FF00"))
        #expect(t.name == "Green")
    }
    // MARK: contrast guard across surfaces (F1)

    func expectReadable(_ t: Theme, sourceLocation: SourceLocation = #_sourceLocation) {
        let c = t.colors
        for bg in [c.background, c.surface, c.raised] {
            #expect(c.text.contrast(with: bg) >= 4.5, "text \(c.text.hex) on \(bg.hex)", sourceLocation: sourceLocation)
        }
        for bg in [c.background, c.surface] {
            #expect(c.textSecondary.contrast(with: bg) >= 3, "secondary \(c.textSecondary.hex) on \(bg.hex)",
                    sourceLocation: sourceLocation)
        }
        #expect(c.text.contrast(with: c.selection) >= 4.5, "text on selection \(c.selection.hex)", sourceLocation: sourceLocation)
        #expect(c.accent.contrast(with: c.background) >= 3, "accent \(c.accent.hex)", sourceLocation: sourceLocation)
    }

    @Test func pinkiesLikeSkinStaysReadableOnSurfaceAndRaised() {
        let skin = WinampSkin(playlist: .init(normal: hex("#7F707F"), normalBG: hex("#FFFFFF")))
        let t = SkinThemeMapper.theme(from: skin, fileName: "pinkies.wsz", installedFonts: fonts)
        #expect(t.colors.background == hex("#FFFFFF"))
        expectReadable(t)
    }

    @Test func midGreyBackgroundStaysReadable() {
        let skin = WinampSkin(playlist: .init(normal: hex("#000000"), normalBG: hex("#777777")))
        let t = SkinThemeMapper.theme(from: skin, fileName: "grey.wsz", installedFonts: fonts)
        expectReadable(t)
    }

    @Test func lightGreyBackgroundStaysReadable() {
        let skin = WinampSkin(playlist: .init(normal: hex("#303030"), normalBG: hex("#AAAEB0"), selectedBG: hex("#404040")),
                              visColors: [hex("#000000"), hex("#181818"), hex("#FFFFFF"), hex("#EEEEEE")])
        let t = SkinThemeMapper.theme(from: skin, fileName: "e.wsz", installedFonts: fonts)
        expectReadable(t)
    }

    @Test func selectionMovesTowardBackgroundWhenTextIsUnreadableOnIt() {
        let skin = WinampSkin(playlist: .init(normal: hex("#FFFFFF"), normalBG: hex("#000000"), selectedBG: hex("#E0E0E0")))
        let t = SkinThemeMapper.theme(from: skin, fileName: "s.wsz", installedFonts: fonts)
        #expect(t.colors.text.contrast(with: t.colors.selection) >= 4.5)
        #expect(t.colors.selection != t.colors.background)
    }

    // MARK: base polarity (F3)

    @Test func baseFollowsTheTextPolarity() {
        let light = WinampSkin(playlist: .init(normal: hex("#000000"), normalBG: hex("#AAAEB0")))
        #expect(SkinThemeMapper.theme(from: light, fileName: "a.wsz", installedFonts: fonts).base == .light)
        let grey = WinampSkin(playlist: .init(normal: hex("#000000"), normalBG: hex("#777777")))
        let expected: ThemeBase = SkinThemeMapper.farthest(from: hex("#777777")) == .white ? .dark : .light
        #expect(SkinThemeMapper.theme(from: grey, fileName: "g.wsz", installedFonts: fonts).base == expected)
        #expect(expected == .light)
    }

    // MARK: accent (F2)

    @Test func accentOnMidToneBackgroundIsSaturatedAndReadable() {
        let skin = WinampSkin(playlist: .init(normal: hex("#000000"), normalBG: hex("#AAAEB0")),
                              visColors: [hex("#000000"), hex("#181818"), hex("#FFFF00"), hex("#00FFFF"), hex("#FFFFFF")])
        let t = SkinThemeMapper.theme(from: skin, fileName: "e.wsz", installedFonts: fonts)
        #expect(t.colors.accent.saturation >= 0.25)
        #expect(t.colors.accent.contrast(with: t.colors.background) >= 3)
        #expect(t.colors.accent != t.colors.text)
    }

    @Test func accentFallsBackToTheBaseDefault() {
        let skin = WinampSkin(playlist: .init(normal: hex("#000000"), current: hex("#808080"), normalBG: hex("#FFFFFF")),
                              visColors: [hex("#000000"), hex("#181818"), hex("#202020"), hex("#C0C0C0")])
        let t = SkinThemeMapper.theme(from: skin, fileName: "grey.wsz", installedFonts: fonts)
        let expected = SkinThemeMapper.ensureContrast(Theme.defaults(for: .light).colors.accent, on: [hex("#FFFFFF")], 3)
        #expect(t.colors.accent == expected)
        #expect(t.colors.accent != t.colors.text)
    }

    @Test func accentTiesKeepTheFirstCandidate() {
        let skin = WinampSkin(playlist: .init(normal: hex("#FFFFFF"), current: hex("#FF0000"), normalBG: hex("#000000")),
                              visColors: [hex("#000000"), hex("#181818"), hex("#00FF00")])
        #expect(SkinThemeMapper.theme(from: skin, fileName: "t.wsz", installedFonts: fonts).colors.accent == hex("#FF0000"))
    }

    @Test func darkAccentGetsWhiteOnAccent() {
        let skin = WinampSkin(playlist: .init(normal: hex("#000000"), current: hex("#1E50D0"), normalBG: hex("#FFFFFF")))
        let t = SkinThemeMapper.theme(from: skin, fileName: "d.wsz", installedFonts: fonts)
        #expect(t.colors.accent == hex("#1E50D0"))
        #expect(t.colors.onAccent == .white)
    }

    @Test func ensureContrastMeetsTheMinimumOverAllBackgrounds() {
        let backgrounds = [hex("#FFFFFF"), hex("#EBEBEB")]
        let c = SkinThemeMapper.ensureContrast(hex("#7F707F"), on: backgrounds, 4.5)
        #expect(backgrounds.allSatisfy { c.contrast(with: $0) >= 4.5 })
        #expect(c.luminance < hex("#7F707F").luminance) // pushed toward black, the far side of white
        #expect(SkinThemeMapper.ensureContrast(hex("#000000"), on: backgrounds, 4.5) == hex("#000000"))
    }

    @Test func imagesAreCopiedIntoTheTheme() {
        var skin = green
        skin.backdropPNG = PNGFixture.make(width: 4, height: 4) { _, _ in (200, 0, 0) }
        skin.pixelFontPNG = PNGFixture.make(width: 155, height: 18) { _, _ in (0, 0, 0) }
        let t = SkinThemeMapper.theme(from: skin, fileName: "g.wsz", installedFonts: fonts)
        #expect(t.images.backdrop == skin.backdropPNG)
        #expect(t.images.pixelFont == skin.pixelFontPNG)
    }

    @Test func fontNamesAreNearMatched() {
        var skin = green
        skin.playlist?.font = "Copperplate Gothic Light"
        #expect(SkinThemeMapper.theme(from: skin, fileName: "d.wsz", installedFonts: ["Copperplate"]).fonts.family == "Copperplate")
    }
}
