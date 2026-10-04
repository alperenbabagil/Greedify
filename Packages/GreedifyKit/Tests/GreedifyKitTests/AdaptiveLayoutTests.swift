import Foundation
import Testing
@testable import GreedifyKit

struct AdaptiveLayoutTests {
    func layout(_ width: CGFloat, lyrics: CGFloat = 300) -> WindowLayout {
        var l = WindowLayout(lyricsWidth: lyrics)
        l.resize(to: width)
        return l
    }

    @Test func narrowingHidesTheLyricsFirstThenTheSidebar() {
        #expect(layout(1180).showsLyrics && layout(1180).showsSidebar)
        #expect(layout(940).showsLyrics)
        #expect(!layout(939).showsLyrics && layout(939).showsSidebar)
        #expect(layout(720).showsSidebar)
        #expect(!layout(719).showsSidebar && !layout(719).showsLyrics)
        #expect(!layout(AdaptiveLayout.windowMinWidth).showsSidebar)
    }

    @Test func aDragWobblingAtAThresholdDoesNotFlipBackAndForth() {
        // Each switch needs the width to move a margin past its threshold before it switches back.
        var l = layout(1180)
        l.resize(to: 719)
        #expect(!l.showsSidebar)
        l.resize(to: 725)
        #expect(!l.showsSidebar)           // just back over 720: stays collapsed
        l.resize(to: 720 + AdaptiveLayout.hysteresis)
        #expect(l.showsSidebar)
        l.resize(to: 939)
        #expect(!l.showsLyrics)
        l.resize(to: 945)
        #expect(!l.showsLyrics)
        l.resize(to: 940 + AdaptiveLayout.hysteresis)
        #expect(l.showsLyrics)
    }

    @Test func theHeaderAlsoWaitsForTheMargin() {
        #expect(AdaptiveLayout.stacksHeader(width: 519, wasStacked: false))
        #expect(AdaptiveLayout.stacksHeader(width: 540, wasStacked: true))
        #expect(!AdaptiveLayout.stacksHeader(width: 520 + AdaptiveLayout.hysteresis, wasStacked: true))
    }

    @Test func widerLyricsHideSooner() {
        #expect(!layout(1000, lyrics: 400).showsLyrics)
        #expect(layout(1040, lyrics: 400).showsLyrics)
    }

    @Test func theToggleOverridesTheWidthUntilItsThresholdIsCrossed() {
        var l = layout(600)
        l.toggleSidebar()
        #expect(l.showsSidebar)            // shown in a narrow window on request
        l.resize(to: 700)
        #expect(l.showsSidebar)            // still below 720: the choice stands
        l.resize(to: 800)
        #expect(l.showsSidebar)            // crossed 720: automatic again (shows)
        l.toggleSidebar()
        #expect(!l.showsSidebar)           // hidden in a wide window on request
    }

    @Test func hidingTheSidebarGivesTheLyricsItsRoom() {
        var l = layout(900)
        #expect(!l.showsLyrics)
        l.toggleSidebar()
        #expect(!l.showsSidebar && l.showsLyrics) // 900 ≥ page 300 + lyrics 300
    }

    @Test func theLyricsWidthStaysInRangeAndLeavesThePageItsMinimum() {
        var l = layout(1180)
        l.setLyricsWidth(1000)
        #expect(l.lyricsWidth == AdaptiveLayout.lyricsMaxWidth)
        l.setLyricsWidth(10)
        #expect(l.lyricsWidth == AdaptiveLayout.lyricsMinWidth)
        var narrow = layout(960)
        narrow.setLyricsWidth(400)
        #expect(narrow.lyricsWidth == 960 - AdaptiveLayout.sidebarMaxWidth - AdaptiveLayout.pageWidthBesideLyrics)
        #expect(narrow.showsLyrics)
    }

    @Test func whatShowsAlwaysFits() {
        // Every visible column at its minimum fits the window, so the split view is never over-constrained (the
        // "too many Update Constraints passes" abort): the sidebar can be shown even at the window's minimum.
        #expect(AdaptiveLayout.sidebarMinWidth + AdaptiveLayout.detailMinWidth <= AdaptiveLayout.windowMinWidth)
        for width in stride(from: AdaptiveLayout.windowMinWidth, through: 1400, by: 10) {
            for toggled in [false, true] {
                var l = layout(width)
                if toggled { l.toggleSidebar() }
                let used = (l.showsSidebar ? AdaptiveLayout.sidebarMinWidth : 0) + AdaptiveLayout.detailMinWidth
                    + (l.showsLyrics ? l.lyricsWidth : 0)
                #expect(used <= width)
            }
        }
    }

    @Test func theBarLeavesItsWideLayoutWhenTheRightHandGroupNoLongerFitsItsSide() {
        // The transport is centred between two equal sides: each needs room for the wider of the two groups.
        let bar = AdaptiveLayout.BarMetrics(chrome: 372, wideExtras: 330, mediumExtras: 170)
        #expect(bar.mode(width: 1032, current: .wide) == .wide)       // 372 + 2 × 330
        #expect(bar.mode(width: 1031, current: .wide) == .medium)     // the long device name would overlap
        #expect(bar.mode(width: 1050, current: .medium) == .medium)   // back only past the margin
        #expect(bar.mode(width: 1072, current: .medium) == .wide)
        #expect(bar.mode(width: 712, current: .medium) == .medium)    // 372 + 2 × 170
        #expect(bar.mode(width: 711, current: .medium) == .compact)
        #expect(bar.mode(width: 751, current: .compact) == .compact)
        #expect(bar.mode(width: 752, current: .compact) == .medium)
        // A short group still keeps each side at its minimum (180 wide, 140 medium).
        let short = AdaptiveLayout.BarMetrics(chrome: 372, wideExtras: 100, mediumExtras: 80)
        #expect(short.mode(width: 732, current: .wide) == .wide)
        #expect(short.mode(width: 731, current: .wide) == .medium)
    }

    @Test func tablesDropTheAlbumColumnAndHeadersStackWhenNarrow() {
        #expect(AdaptiveLayout.showsAlbumColumn(tableWidth: 560))
        #expect(!AdaptiveLayout.showsAlbumColumn(tableWidth: 559))
        #expect(!AdaptiveLayout.stacksHeader(width: 520))
        #expect(AdaptiveLayout.stacksHeader(width: 519))
    }
}
