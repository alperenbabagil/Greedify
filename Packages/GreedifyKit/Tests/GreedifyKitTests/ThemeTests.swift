import Foundation
import Testing
@testable import GreedifyKit

struct ThemeTests {
    func decode(_ json: String) throws -> Theme { try Theme.decode(from: Data(json.utf8)) }

    @Test func decodesACompleteFile() throws {
        let t = try decode("{\"version\":1,\"name\":\"Neon\",\"author\":\"me\",\"base\":\"dark\",\"lyrics\":\"solid\",\"colors\":{\"background\":\"#000000\",\"surface\":\"#111111\",\"raised\":\"#222222\",\"text\":\"#FFFFFF\",\"textSecondary\":\"#AAAAAA\",\"accent\":\"#FF00FF\",\"onAccent\":\"#000000\",\"selection\":\"#330033\",\"divider\":\"#FFFFFF22\",\"lyricsText\":\"#FFEEFF\"},\"fonts\":{\"family\":\"Menlo\",\"scale\":1.2,\"titleWeight\":\"heavy\"},\"shapes\":{\"cardRadius\":10,\"buttonRadius\":4,\"artworkRadius\":3,\"rowRadius\":2,\"borderWidth\":1,\"buttonStyle\":\"bevel\",\"density\":\"compact\"}}")
        #expect(t.name == "Neon")
        #expect(t.author == "me")
        #expect(t.colors.accent == ThemeColor(hex: "#FF00FF"))
        #expect(t.colors.divider.hex == "#FFFFFF22")
        #expect(t.fonts == Theme.Fonts(family: "Menlo", scale: 1.2, titleWeight: .heavy))
        #expect(t.shapes.buttonStyle == .bevel)
        #expect(t.shapes.density == .compact)
        #expect(t.lyrics == .solid)
    }

    @Test func missingValuesComeFromTheBaseDefaults() throws {
        let t = try decode("{\"name\":\"Tiny\",\"base\":\"light\",\"colors\":{\"accent\":\"#FF0000\"}}")
        let light = Theme.defaults(for: .light)
        #expect(t.colors.accent == ThemeColor(hex: "#FF0000"))
        #expect(t.colors.background == light.colors.background)
        #expect(t.fonts == light.fonts)
        #expect(t.shapes == light.shapes)
    }

    @Test func missingBaseMeansDark() throws {
        #expect(try decode("{}").base == .dark)
        #expect(try decode("{}").colors == Theme.defaults(for: .dark).colors)
        #expect(try decode("{\"name\":\"\"}").name == "Untitled")
    }

    @Test func outOfRangeValuesAreClamped() throws {
        let t = try decode("{\"fonts\":{\"scale\":5},\"shapes\":{\"cardRadius\":-3,\"buttonRadius\":99,\"borderWidth\":9}}")
        #expect(t.fonts.scale == 1.4)
        #expect(t.shapes.cardRadius == 0)
        #expect(t.shapes.buttonRadius == 24)
        #expect(t.shapes.borderWidth == 3)
    }

    @Test func aBadValueFallsBackAlone() throws {
        let t = try decode("{\"colors\":{\"text\":\"banana\",\"accent\":\"#00FF00\"},\"shapes\":{\"buttonStyle\":\"wobbly\",\"density\":\"compact\"}}")
        #expect(t.colors.text == Theme.defaults(for: .dark).colors.text)
        #expect(t.colors.accent == ThemeColor(hex: "#00FF00"))
        #expect(t.shapes.buttonStyle == Theme.defaults(for: .dark).shapes.buttonStyle)
        #expect(t.shapes.density == .compact)
    }

    @Test func unknownKeysAndNewerVersionsStillLoad() throws {
        let t = try decode("{\"version\":7,\"name\":\"Future\",\"sparkles\":true,\"colors\":{\"accent\":\"#123456\",\"glow\":\"#FFFFFF\"}}")
        #expect(t.version == 7)
        #expect(t.name == "Future")
        #expect(t.colors.accent == ThemeColor(hex: "#123456"))
    }

    @Test func notJSONThrows() {
        #expect(throws: (any Error).self) { try decode("not json") }
        #expect(throws: (any Error).self) { try decode("[1,2]") }
    }

    @Test func roundTrips() throws {
        var t = Theme.defaults(for: .light)
        t.name = "Round"
        t.fonts.family = "Georgia"
        t.shapes.buttonStyle = .outlined
        #expect(try Theme.decode(from: t.encoded()) == t)
    }
}

struct ThemeControlsCodecTests {
    func png() -> Data { PNGFixture.make(width: 2, height: 2) { _, _ in (10, 20, 30) } }

    @Test func controlsAndControlImagesRoundTrip() throws {
        var theme = Theme.defaults(for: .dark)
        var controls = Theme.Controls()
        controls.faceTop = ThemeColor(hex: "#6070A0"); controls.faceBottom = ThemeColor(hex: "#405080")
        controls.panel = ThemeColor(hex: "#4A5A86"); controls.glyph = ThemeColor(hex: "#F0F0F0"); controls.on = ThemeColor(hex: "#7CFF4F")
        theme.controls = controls
        theme.images = Theme.Images(seekBar: png(), volume: png(), digits: png())
        let back = try Theme.decode(from: theme.encoded())
        #expect(back.controls == controls)
        #expect(back.images == theme.images)
    }

    @Test func oldFilesHaveNoControls() throws {
        let theme = try Theme.decode(from: Data(#"{"version":1,"name":"Old","images":{"backdrop":""}}"#.utf8))
        #expect(theme.controls == nil)
        #expect(theme.images.seekBar == nil && theme.images.volume == nil && theme.images.digits == nil)
    }

    @Test func aBadColourIsDroppedAlone() throws {
        let json = ##"{"controls":{"faceTop":"#6070A0","faceBottom":"#405080","panel":"#4A5A86","glyph":"nope"}}"##
        let controls = try #require(try Theme.decode(from: Data(json.utf8)).controls)
        #expect(controls.glyph == nil && controls.faceTop == ThemeColor(hex: "#6070A0"))
    }

    @Test func controlsWithoutAFaceOrPanelAreDropped() throws {
        let json = ##"{"controls":{"faceTop":"#6070A0","glyph":"#FFFFFF"}}"##
        #expect(try Theme.decode(from: Data(json.utf8)).controls == nil)
        var theme = Theme.defaults(for: .dark)
        theme.controls = Theme.Controls()           // unusable: not written
        #expect(!String(decoding: try theme.encoded(), as: UTF8.self).contains("controls"))
    }

    @Test func aBadControlImageIsDroppedAlone() throws {
        let good = png().base64EncodedString()
        let json = #"{"images":{"seekBar":"\#(good)","volume":"bm90IGEgcG5n","digits":"\#(good)"}}"#
        let images = try Theme.decode(from: Data(json.utf8)).images
        #expect(images.seekBar != nil && images.volume == nil && images.digits != nil)
    }
}

/// Where a curated theme's art comes from, for Settings → Credits.
struct ThemeCreditsTests {
    @Test func creditsRoundTripAndBadEntriesDropAlone() throws {
        let json = #"{"name":"T","credits":[{"title":"Background art","detail":"Key art","url":"https://example.com/a.webp"},{"detail":"no title"},{"title":"Skin","detail":"by A. Skinner"}]}"#
        let theme = try Theme.decode(from: Data(json.utf8))
        #expect(theme.credits == [Theme.Credit(title: "Background art", detail: "Key art", url: URL(string: "https://example.com/a.webp")),
                                  Theme.Credit(title: "Skin", detail: "by A. Skinner", url: nil)])
        #expect(try Theme.decode(from: theme.encoded()).credits == theme.credits)
        #expect(!String(decoding: try Theme.defaults(for: .dark).encoded(), as: UTF8.self).contains("credits"))
    }

    @Test func everyCuratedThemeCreditsItsSkin() {
        for (id, theme) in Theme.builtins() where theme.style != nil {
            #expect(!theme.credits.isEmpty, "\(id)")
        }
    }
}
