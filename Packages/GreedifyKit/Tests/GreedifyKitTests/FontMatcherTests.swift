import Testing
@testable import GreedifyKit

struct FontMatcherTests {
    let installed = ["Arial", "Arial Narrow", "Copperplate", "Geneva", "Monaco", "Verdana"]

    @Test func exactMatchIgnoresCase() {
        #expect(FontMatcher.bestFamily(for: "verdana", among: installed) == "Verdana")
        #expect(FontMatcher.bestFamily(for: "Arial Narrow", among: installed) == "Arial Narrow")
    }

    @Test func wholeWordPrefix() {
        #expect(FontMatcher.bestFamily(for: "Copperplate Gothic Light", among: installed) == "Copperplate")
        #expect(FontMatcher.bestFamily(for: "Arial Black", among: installed) == "Arial")
        #expect(FontMatcher.bestFamily(for: "Arialish", among: installed) == nil) // not a whole word
    }

    @Test func windowsTable() {
        #expect(FontMatcher.bestFamily(for: "MS Sans Serif", among: installed) == "Geneva")
        #expect(FontMatcher.bestFamily(for: "Small Fonts", among: installed) == "Monaco")
        #expect(FontMatcher.bestFamily(for: "Terminal", among: installed) == "Monaco")
        #expect(FontMatcher.bestFamily(for: "System", among: installed) == nil)
    }

    @Test func noMatch() {
        #expect(FontMatcher.bestFamily(for: "Comic Sans MS", among: installed) == nil)
        #expect(FontMatcher.bestFamily(for: "  ", among: installed) == nil)
        #expect(FontMatcher.bestFamily(for: "Geneva", among: []) == nil)
    }
}
