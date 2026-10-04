import Foundation
import Testing
@testable import GreedifyKit

struct BuiltinThemeTests {
    @Test func allBuiltinsLoadInOrder() {
        let builtins = Theme.builtins()
        #expect(builtins.map { $0.id } == ["builtin.system", "builtin.classic", "builtin.modern", "builtin.paper", "builtin.high-contrast",
                                           "builtin.winamp-classic", "builtin.winamp5-classified"])
        #expect(builtins.map { $0.theme.name } == ["System", "Classic", "Modern", "Paper", "High Contrast", "Winamp Classic", "Winamp5 Classified"])
    }

    @Test func builtinsAreReadable() {
        for (id, t) in Theme.builtins() {
            let c = t.colors
            #expect(c.text.contrast(with: c.background) >= 4.5, "\(id): text on background")
            #expect(c.text.contrast(with: c.surface) >= 4.5, "\(id): text on surface")
            #expect(c.textSecondary.contrast(with: c.background) >= 3, "\(id): secondary text")
            #expect(c.onAccent.contrast(with: c.accent) >= 3, "\(id): text on accent")
        }
    }

    @Test func classicIsWinampFlavoured() throws {
        let t = try #require(Theme.builtins().first { $0.id == "builtin.classic" }).theme
        #expect(t.shapes.buttonStyle == .bevel)
        #expect(t.shapes.density == .compact)
        #expect(t.shapes.cardRadius == 2)
        #expect(t.lyrics == .solid)
    }

    /// A typo in a color would silently fall back to a default, so every non-System file must spell out all ten.
    @Test func builtinFilesSpellOutEveryColor() throws {
        for slug in Theme.builtinOrder where slug != "system" {
            let url = try #require(Theme.builtinURL(slug)) // Bundle.module here would be the test bundle
            let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let colors = try #require(json["colors"] as? [String: String], "\(slug)")
            #expect(colors.count == 10, "\(slug)")
            #expect(colors.values.allSatisfy { ThemeColor(hex: $0) != nil }, "\(slug)")
        }
    }
}
