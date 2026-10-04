import Testing
@testable import GreedifyKit

struct ThemeColorTests {
    @Test func parsesHex() {
        #expect(ThemeColor(hex: "#FF8000") == ThemeColor(r: 1, g: 128.0 / 255, b: 0))
        #expect(ThemeColor(hex: "ff8000") == ThemeColor(hex: "#FF8000"))
        #expect(ThemeColor(hex: "#FF800080")?.a == 128.0 / 255)
        #expect(ThemeColor(hex: " #00ff00 ") == ThemeColor(r: 0, g: 1, b: 0))
    }

    @Test(arguments: ["", "#12345", "#1234567", "zzzzzz", "+12345", "#12 345"])
    func rejectsBadHex(_ text: String) {
        #expect(ThemeColor(hex: text) == nil)
    }

    @Test func printsHex() {
        #expect(ThemeColor(hex: "#1e1e1e")!.hex == "#1E1E1E")
        #expect(ThemeColor(hex: "#FFFFFF1A")!.hex == "#FFFFFF1A")
    }

    @Test func contrastMatchesWCAG() {
        #expect(abs(ThemeColor.black.contrast(with: .white) - 21) < 0.01)
        #expect(abs(ThemeColor(hex: "#777777")!.contrast(with: .white) - 4.48) < 0.01)
        #expect(ThemeColor.white.contrast(with: .white) == 1)
    }

    @Test func blendsAndMeasures() {
        #expect(ThemeColor.black.blended(toward: .white, 0.5) == ThemeColor(r: 0.5, g: 0.5, b: 0.5))
        #expect(ThemeColor(hex: "#FF0000")!.saturation == 1)
        #expect(ThemeColor(hex: "#808080")!.saturation == 0)
        #expect(ThemeColor.white.lightness == 1)
        #expect(ThemeColor.white.withAlpha(0.15).a == 0.15)
    }

    @Test func liftsLightnessKeepingHue() throws {
        let olive = try #require(ThemeColor(hex: "#978F60"))
        #expect(olive.lifted(0, lighter: true) == olive)
        let up = olive.lifted(0.3, lighter: true)
        #expect(abs(up.lightness - (olive.lightness + 0.3 * (1 - olive.lightness))) < 0.001)
        #expect(abs(up.hue - olive.hue) < 0.5)
        #expect(abs(up.saturation - olive.saturation) < 0.01)
        let down = olive.lifted(0.5, lighter: false)
        #expect(abs(down.lightness - olive.lightness * 0.5) < 0.001)
        #expect(abs(down.hue - olive.hue) < 0.5)
        #expect(ThemeColor(hex: "#808080")!.lifted(1, lighter: true) == .white)
        #expect(abs(ThemeColor(hex: "#FF0000")!.hue) < 0.001)
        #expect(abs(ThemeColor(hex: "#00FF00")!.hue - 120) < 0.001)
    }
}

struct EnsuringContrastTests {
    /// The bar's text must read on a skin's panel (final review: bar text over `panel`).
    @Test func textIsPushedUntilItReadsOnThePanel() throws {
        let panel = try #require(ThemeColor(hex: "#4A5A86"))
        let dim = try #require(ThemeColor(hex: "#5A6A96"))
        let readable = dim.ensuringContrast(on: [panel], 4.5)
        #expect(readable.contrast(with: panel) >= 4.5)
        let fine = ThemeColor.white
        #expect(fine.ensuringContrast(on: [panel], 4.5) == fine)   // already readable: unchanged
    }
}
