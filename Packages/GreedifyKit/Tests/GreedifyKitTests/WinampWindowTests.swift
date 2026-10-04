import Foundation
import Testing
@testable import GreedifyKit

/// The recipe options that make the whole window look like Winamp (winamp window spec).
struct WinampWindowTests {
    func c(_ hex: String) -> ThemeColor { ThemeColor(hex: hex)! }

    static let json = #"""
    {"name":"T","style":{
      "list":{"layout":"playlist","rowHeight":17,"font":"Arial","size":10},
      "pageHeader":{"layout":"strip","artwork":40},
      "frame":{"face":{"kind":"solid","color":"#39395A"},"bevel":{"style":"raised","light":"#5E5E84","dark":"#08080E","width":1},
               "thickness":4,"title":{"material":{"kind":"solid","color":"#B8A060"},"height":12,"text":"#E0D8B0","prefix":"WINAMP"}},
      "bar":{"layout":"winamp","analyser":["#FF0000","#FFFF00","#00FF00"],"readouts":true,"transport":"winamp"},
      "text":{"lyrics":{"size":13,"weight":"regular"}}
    }}
    """#

    @Test func theNewOptionsDecode() throws {
        let style = try #require(try Style.$strict.withValue(true) { try Theme.decode(from: Data(Self.json.utf8)) }.style)
        #expect(style.list == Style.ListSpec(layout: .playlist, rowHeight: 17, font: .family("Arial"), size: 10))
        #expect(style.pageHeader == Style.PageHeaderSpec(layout: .strip, artwork: 40))
        let frame = try #require(style.frame)
        #expect(frame.face == .solid(c("#39395A")) && frame.bevel?.kind == .raised && frame.thickness == 4)
        #expect(frame.title == Style.TitleStripSpec(material: .solid(c("#B8A060")), height: 12, text: c("#E0D8B0"), prefix: "WINAMP"))
        #expect(style.bar?.analyser == [c("#FF0000"), c("#FFFF00"), c("#00FF00")])
        #expect(style.bar?.readouts == true && style.bar?.transport == .winamp)
        #expect(style.text[.lyrics]?.size == 13)
    }

    @Test func theyRoundTrip() throws {
        let theme = try Theme.decode(from: Data(Self.json.utf8))
        #expect(try Theme.decode(from: theme.encoded()).style == theme.style)
    }

    @Test func absentMeansTodaysLook() throws {
        let style = try #require(try Theme.decode(from: Data(#"{"style":{"list":{},"pageHeader":{},"bar":{"layout":"winamp"}}}"#.utf8)).style)
        #expect(style.list?.layout == .cards && style.pageHeader?.layout == .hero)
        #expect(style.bar?.transport == nil && style.bar?.analyser == nil && style.frame == nil)
    }

    @Test func strictModeRejectsTypos() {
        #expect(throws: (any Error).self) {
            try Style.$strict.withValue(true) { try Theme.decode(from: Data(#"{"style":{"list":{"layot":"playlist"}}}"#.utf8)) }
        }
        #expect(throws: (any Error).self) {
            try Style.$strict.withValue(true) { try Theme.decode(from: Data(#"{"style":{"frame":{"title":{"prefx":"W"}}}}"#.utf8)) }
        }
    }

    @Test func analyserBarsAreStablePerSong() {
        let a = Analyser.bars(seed: "4uLU6hMCjMI75M1A2tKUQC", count: 19)
        #expect(a.count == 19)
        #expect(a.allSatisfy { (0...1).contains($0) })
        #expect(a == Analyser.bars(seed: "4uLU6hMCjMI75M1A2tKUQC", count: 19))
        #expect(a != Analyser.bars(seed: "7ouMYWpwJ422jRcDASZB7P", count: 19))
        #expect(Analyser.bars(seed: "", count: 0).isEmpty)
    }

    @Test func analyserFallsOffTowardTheHighBands() {
        // Averaged over many songs, the low half is taller than the high half, as in a real spectrum.
        var low = 0.0, high = 0.0
        for i in 0..<200 {
            let b = Analyser.bars(seed: "song\(i)", count: 20)
            low += b[..<10].reduce(0, +); high += b[10...].reduce(0, +)
        }
        #expect(low > high * 1.2)
    }

    // Winamp5 Classified's chrome: steel title bars with one silver groove, bold lettering, rounded LCDs, round
    // transport buttons and pill-shaped labelled ones.
    static let classifiedJSON = #"""
    {"name":"T","style":{
      "frame":{"title":{"material":{"kind":"solid","color":"#E0E6F0"},"background":{"kind":"solid","color":"#2A3A5E"},
               "stripeHeight":3,"rounded":true,"font":"system","size":12,"weight":"heavy","text":"#E8ECF4","prefix":"WINAMP"}},
      "lcd":{"radius":6},
      "button":{"shape":"circle","labelShape":"pill"}
    }}
    """#

    @Test func classifiedChromeDecodes() throws {
        let style = try #require(try Style.$strict.withValue(true) { try Theme.decode(from: Data(Self.classifiedJSON.utf8)) }.style)
        let title = try #require(style.frame?.title)
        #expect(title.background == .solid(c("#2A3A5E")) && title.stripeHeight == 3 && title.rounded == true)
        #expect(title.font == .system && title.size == 12 && title.weight == .heavy)
        #expect(style.lcd?.radius == 6)
        #expect(style.button?.shape == .circle && style.button?.labelShape == .pill)
    }

    @Test func classifiedChromeRoundTrips() throws {
        let theme = try Theme.decode(from: Data(Self.classifiedJSON.utf8))
        #expect(try Theme.decode(from: theme.encoded()).style == theme.style)
    }

    // The original skin's main window and playlist: content set into the frame with rounded corners and a dark
    // outline, a main-window player bar, a playlist footer and a skinned scroller.
    static let mainWindowJSON = #"""
    {"name":"T","style":{
      "frame":{"radius":6,"outline":"#0B1427"},
      "list":{"layout":"playlist",
              "scroller":{"track":{"kind":"solid","color":"#9CA3B0"},"thumb":{"kind":"solid","color":"#E0E4EC"},
                          "bevel":{"style":"raised","light":"#FFFFFF","dark":"#5D636E","width":1},"width":12}}
    }}
    """#

    @Test func mainWindowOptionsDecode() throws {
        let style = try #require(try Style.$strict.withValue(true) { try Theme.decode(from: Data(Self.mainWindowJSON.utf8)) }.style)
        #expect(style.frame?.radius == 6 && style.frame?.outline == c("#0B1427"))
        let scroller = try #require(style.list?.scroller)
        #expect(scroller.track == .solid(c("#9CA3B0")) && scroller.thumb == .solid(c("#E0E4EC")) && scroller.bevel?.kind == .raised && scroller.width == 12)
    }

    @Test func mainWindowOptionsRoundTrip() throws {
        let theme = try Theme.decode(from: Data(Self.mainWindowJSON.utf8))
        #expect(try Theme.decode(from: theme.encoded()).style == theme.style)
    }

    // The original's transport: glossy elliptical buttons in a dark outline and a light halo, a little apart, in a
    // recessed channel.
    static let transportJSON = #"""
    {"name":"T","style":{
      "button":{"outline":"#181D27","halo":"#B3B9C6","spacing":3},
      "bar":{"layout":"winamp","transportWell":{"kind":"solid","color":"#717A89"}}
    }}
    """#

    @Test func transportOptionsDecodeAndRoundTrip() throws {
        let theme = try Style.$strict.withValue(true) { try Theme.decode(from: Data(Self.transportJSON.utf8)) }
        let style = try #require(theme.style)
        #expect(style.button?.outline == c("#181D27") && style.button?.halo == c("#B3B9C6") && style.button?.spacing == 3)
        #expect(style.bar?.transportWell == .solid(c("#717A89")))
        #expect(try Theme.decode(from: theme.encoded()).style == style)
    }

    @Test func theFooterAndMainWindowAreGone() {
        #expect(throws: (any Error).self) {
            try Style.$strict.withValue(true) { try Theme.decode(from: Data(#"{"style":{"list":{"footer":true}}}"#.utf8)) }
        }
        #expect(throws: (any Error).self) {
            try Style.$strict.withValue(true) { try Theme.decode(from: Data(#"{"style":{"bar":{"layout":"winamp","mainWindow":true}}}"#.utf8)) }
        }
    }
}
