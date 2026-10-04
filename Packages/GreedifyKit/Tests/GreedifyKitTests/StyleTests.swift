import Foundation
import Testing
@testable import GreedifyKit

/// The curated-skin recipe (curated skins spec §2).
struct StyleTests {
    func c(_ hex: String) -> ThemeColor { ThemeColor(hex: hex)! }

    static let fullJSON = #"""
    {"name":"T","style":{
      "materials":{"window":{"kind":"solid","color":"#2A3350"},
                   "sidebar":{"kind":"gradient","angle":90,"stops":[{"color":"#6070A0","at":0},{"color":"#405080","at":1}]},
                   "header":{"kind":"dotGrid","base":"#101C48","dot":"#24346A","pitch":2,"size":1},
                   "bar":{"kind":"brushed","base":"#B8BCC4","streak":"#9EA3AC","density":0.35,"seed":7},
                   "popover":{"kind":"noise","base":"#2B2420","amount":0.08,"seed":3},
                   "lyrics":{"kind":"pattern","width":2,"height":2,"scale":1,"colors":["#000000","#FFFFFF","#FFFFFF","#000000"]}},
      "bevels":{"panel":{"style":"sunken","light":"#C0C8E0","dark":"#202840","width":1},"bar":{"style":"double","light":"#FFFFFF","dark":"#000000","width":2}},
      "divider":"#FFFFFF22",
      "rows":{"normal":{"fill":{"kind":"solid","color":"#000000"},"text":"#00FF00","secondary":"#008800"},
              "alternate":{"fill":{"kind":"solid","color":"#050505"}},"hover":{"fill":{"kind":"solid","color":"#101010"}},
              "selected":{"fill":{"kind":"solid","color":"#0000C6"},"text":"#FFFFFF"},"playing":{"text":"#FFFFFF"}},
      "lcd":{"material":{"kind":"solid","color":"#000000"},"bevel":{"style":"sunken","light":"#FFFFFF","dark":"#000000","width":1},
             "digits":"segment","text":"#00FF00","info":"#00AA00","glow":2},
      "button":{"shape":"rounded","radius":3,"face":{"kind":"solid","color":"#333333"},"bevel":{"style":"raised","light":"#FFFFFF","dark":"#000000","width":1},
                "glyph":"#EEEEEE","glyphWeight":"semibold","pressed":{"face":{"kind":"solid","color":"#222222"},"glyph":"#FFFFFF"},"active":"#7CFF4F"},
      "slider":{"groove":{"material":{"kind":"solid","color":"#111111"},"height":6},"fill":{"kind":"ramp","colors":["#00FF00","#FFFF00","#FF0000"]},
                "thumb":{"shape":"rect","width":22,"height":12,"face":{"kind":"solid","color":"#AAAAAA"}}},
      "volume":{"fill":{"kind":"solid","colors":["#00FF00"]}},
      "text":{"title":{"font":"pixel","size":13,"weight":"bold","color":"#00FF00","glow":1},"body":{"font":"system","size":12},"header":{"font":"Copperplate"}},
      "bar":{"layout":"winamp","height":110,"artwork":false}
    }}
    """#

    @Test func everyPrimitiveDecodes() throws {
        let style = try #require(try Theme.decode(from: Data(Self.fullJSON.utf8)).style)
        #expect(style.materials[.window] == .solid(c("#2A3350")))
        #expect(style.materials[.sidebar] == .gradient(angle: 90, stops: [.init(color: c("#6070A0"), at: 0), .init(color: c("#405080"), at: 1)]))
        #expect(style.materials[.header] == .dotGrid(base: c("#101C48"), dot: c("#24346A"), pitch: 2, size: 1))
        #expect(style.materials[.bar] == .brushed(base: c("#B8BCC4"), streak: c("#9EA3AC"), density: 0.35, seed: 7))
        #expect(style.materials[.popover] == .noise(base: c("#2B2420"), amount: 0.08, seed: 3))
        #expect(style.materials[.lyrics] == .pattern(width: 2, height: 2, scale: 1, colors: [c("#000000"), c("#FFFFFF"), c("#FFFFFF"), c("#000000")]))
        #expect(style.bevels[.panel] == Style.Bevel(kind: .sunken, light: c("#C0C8E0"), dark: c("#202840"), width: 1))
        #expect(style.divider == c("#FFFFFF22"))
        #expect(style.rows.selected?.text == c("#FFFFFF") && style.rows.playing?.text == c("#FFFFFF"))
        #expect(style.lcd?.digits == .segment && style.lcd?.glow == 2)
        #expect(style.button?.shape == .rounded && style.button?.pressed?.glyph == c("#FFFFFF") && style.button?.active == c("#7CFF4F"))
        #expect(style.slider?.fill?.kind == .ramp && style.slider?.fill?.colors.count == 3 && style.slider?.thumb?.width == 22)
        #expect(style.volume?.fill?.kind == .solid)
        #expect(style.text[.title]?.font == .pixel && style.text[.header]?.font == .family("Copperplate"))
        #expect(style.bar == Style.BarSpec(layout: .winamp, height: 110, artwork: false))
    }

    @Test func aRecipeRoundTrips() throws {
        let theme = try Theme.decode(from: Data(Self.fullJSON.utf8))
        #expect(try Theme.decode(from: theme.encoded()).style == theme.style)
    }

    @Test func anInvalidValueIsDroppedAlone() throws {
        let json = ##"{"style":{"materials":{"window":{"kind":"plaid"},"sidebar":{"kind":"solid","color":"#123456"}},"lcd":{"digits":"nixie","text":"#00FF00"}}}"##
        let style = try #require(try Theme.decode(from: Data(json.utf8)).style)
        #expect(style.materials[.window] == nil && style.materials[.sidebar] == .solid(c("#123456")))
        #expect(style.lcd?.digits == nil && style.lcd?.text == c("#00FF00"))
    }

    @Test func aThemeWithoutStyleIsUnchanged() throws {
        let theme = try Theme.decode(from: Data(#"{"name":"Plain"}"#.utf8))
        #expect(theme.style == nil)
        #expect(!String(decoding: try theme.encoded(), as: UTF8.self).contains("style"))
    }

    /// Built-in recipes must not ship with typos: strict decoding reports what lenient decoding would drop.
    @Test func strictDecodingReportsDroppedAndUnknownKeys() throws {
        #expect(throws: (any Error).self) {
            try Style.$strict.withValue(true) { try Theme.decode(from: Data(#"{"style":{"lcd":{"digitz":"segment"}}}"#.utf8)) }
        }
        #expect(throws: (any Error).self) {
            try Style.$strict.withValue(true) { try Theme.decode(from: Data(#"{"style":{"materials":{"window":{"kind":"plaid"}}}}"#.utf8)) }
        }
        _ = try Style.$strict.withValue(true) { try Theme.decode(from: Data(Self.fullJSON.utf8)) }
    }
}

/// Atmosphere: glows and stacked materials (curated skins: backgrounds that feel like the skin).
struct StyleAtmosphereTests {
    func c(_ hex: String) -> ThemeColor { ThemeColor(hex: hex)! }

    @Test func radialAndLayersDecodeAndRoundTrip() throws {
        let json = ##"""
        {"style":{"materials":{"window":{"kind":"layers","layers":[
          {"kind":"gradient","angle":90,"stops":[{"color":"#000000","at":0},{"color":"#3A0A04","at":1}]},
          {"kind":"radial","x":0.5,"y":1.1,"radius":0.9,"stops":[{"color":"#FF6A1A66","at":0},{"color":"#FF6A1A00","at":1}]},
          {"kind":"noise","base":"#FFFFFF10","amount":0.06,"seed":9}]}}}}
        """##
        let theme = try Style.$strict.withValue(true) { try Theme.decode(from: Data(json.utf8)) }
        guard case .layers(let layers)? = theme.style?.materials[.window] else { Issue.record("expected layers"); return }
        #expect(layers.count == 3)
        #expect(layers[1] == .radial(x: 0.5, y: 1.1, radius: 0.9, stops: [.init(color: c("#FF6A1A66"), at: 0), .init(color: c("#FF6A1A00"), at: 1)]))
        #expect(try Theme.decode(from: theme.encoded()).style == theme.style)
        #expect(Style.Material.layers(layers).base == c("#000000"))           // the bottom layer stands for the stack
    }

    @Test func emptyOrNestedTooDeepIsDropped() throws {
        let empty = #"{"style":{"materials":{"window":{"kind":"layers","layers":[]}}}}"#
        #expect(try Theme.decode(from: Data(empty.utf8)).style?.materials[.window] == nil)
        #expect(MaterialTile.make(.radial(x: 0.5, y: 0.5, radius: 1, stops: [.init(color: c("#000000"), at: 0)]), scale: 2) == nil)
    }
}

/// Picture backgrounds shipped with a curated recipe (the user's own art for a skin).
struct StyleImageTests {
    @Test func anImageMaterialRoundTrips() throws {
        let json = #"{"style":{"materials":{"bar":{"kind":"image","name":"bar.jpg","focusX":0.5,"focusY":0.4,"opacity":0.9}}}}"#
        let theme = try Style.$strict.withValue(true) { try Theme.decode(from: Data(json.utf8)) }
        #expect(theme.style?.materials[.bar] == .image(name: "bar.jpg", focusX: 0.5, focusY: 0.4, opacity: 0.9))
        #expect(try Theme.decode(from: theme.encoded()).style == theme.style)
        #expect(MaterialTile.make(.image(name: "x.jpg", focusX: 0.5, focusY: 0.5, opacity: 1), scale: 2) == nil)
    }

    @Test func aNameCantLeaveItsFolder() throws {
        let json = #"{"style":{"materials":{"bar":{"kind":"image","name":"../../etc/passwd"}}}}"#
        #expect(try Theme.decode(from: Data(json.utf8)).style?.materials[.bar] == nil)
    }

    @Test func aMissingRecipeImageIsNotFound() {
        #expect(Theme.recipeImageURL("missing.jpg") == nil)
    }
}
