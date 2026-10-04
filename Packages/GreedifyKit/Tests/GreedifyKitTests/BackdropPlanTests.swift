import CoreGraphics
import Foundation
import Testing
@testable import GreedifyKit

struct BackdropPlanTests {
    let dark = Theme.defaults(for: .dark).colors
    let light = Theme.defaults(for: .light).colors
    func solid(_ c: UInt8, size: Int = 8) -> Data { PNGFixture.make(width: size, height: size) { _, _ in (c, c, c) } }

    /// A dark skin's colors (a dim olive text on black).
    var darkSkinColors: Theme.Colors {
        var c = dark
        c.background = ThemeColor(hex: "#000000")!
        c.surface = ThemeColor(hex: "#141414")!
        c.text = ThemeColor(hex: "#978F60")!
        c.textSecondary = ThemeColor(hex: "#6A6548")!
        c.lyricsText = ThemeColor(hex: "#978F60")!
        return c
    }

    /// 100 px: 6 bright orange (a dark skin's 95th-percentile pixel), the rest near black.
    let darkSkinArt = PNGFixture.make(width: 10, height: 10) { x, y in y * 10 + x < 6 ? (0xFB, 0x8D, 0x2E) : (0x10, 0x08, 0x00) }

    enum Area { case sidebar, content, lyrics }

    /// The returned colors at `alpha` over the blended worst case for `area`.
    func readable(_ plan: BackdropPlan, _ area: Area, alpha: Double, worst: ThemeColor, colors: Theme.Colors) -> Bool {
        let panel = BackdropPlan.blend(worst, over: area == .sidebar ? colors.surface : colors.background, alpha: alpha)
        var ok = plan.text.contrast(with: panel) >= 4.5 && plan.textSecondary.contrast(with: panel) >= 3
        if area == .lyrics { ok = ok && plan.lyricsText.contrast(with: panel) >= 4.5 }
        return ok
    }

    func readable(_ plan: BackdropPlan, worst: ThemeColor, colors: Theme.Colors) -> Bool {
        readable(plan, .sidebar, alpha: plan.sidebarAlpha, worst: worst, colors: colors)
            && readable(plan, .content, alpha: plan.contentAlpha, worst: worst, colors: colors)
            && readable(plan, .lyrics, alpha: plan.lyricsAlpha, worst: worst, colors: colors)
    }

    @Test func brightArtNeedsMoreTintOnADarkTheme() throws {
        let white = try #require(BackdropPlan.make(backdrop: solid(255), colors: dark, base: .dark))
        let black = try #require(BackdropPlan.make(backdrop: solid(0), colors: dark, base: .dark))
        #expect(white.sidebarAlpha > black.sidebarAlpha)
        #expect(black.sidebarAlpha == 0.35 && black.contentAlpha == 0.35 && black.lyricsAlpha == 0.35)
        #expect(readable(white, worst: .white, colors: dark))
    }

    @Test func lightBaseUsesDarkestPixels() throws {
        let blackArt = try #require(BackdropPlan.make(backdrop: solid(0), colors: light, base: .light))
        let whiteArt = try #require(BackdropPlan.make(backdrop: solid(255), colors: light, base: .light))
        #expect(blackArt.contentAlpha > whiteArt.contentAlpha)
        #expect(readable(blackArt, worst: .black, colors: light))
    }

    @Test func alphasAreHundredthsInRangeAndLyricsNeverExceedContent() throws {
        for c: UInt8 in [0, 60, 128, 200, 255] {
            let plan = try #require(BackdropPlan.make(backdrop: solid(c), colors: dark, base: .dark))
            for alpha in [plan.sidebarAlpha, plan.contentAlpha, plan.lyricsAlpha] {
                #expect((0.35...0.95).contains(alpha) || alpha == 1)
                #expect(abs(alpha * 100 - (alpha * 100).rounded()) < 1e-9)
            }
            #expect(plan.lyricsAlpha <= plan.contentAlpha)
        }
    }

    @Test func percentileIgnoresASmallBrightSpeck() throws {
        // 1 white pixel in 100 is under the 95th percentile, so the plan treats the art as black.
        let speck = PNGFixture.make(width: 10, height: 10) { x, y in x == 0 && y == 0 ? (255, 255, 255) : (0, 0, 0) }
        #expect(BackdropPlan.make(backdrop: speck, colors: dark, base: .dark)?.sidebarAlpha == 0.35)
    }

    @Test func dimTextIsLiftedSoTheArtShows() throws {
        let colors = darkSkinColors
        let plan = try #require(BackdropPlan.make(backdrop: darkSkinArt, colors: colors, base: .dark))
        let worst = ThemeColor(hex: "#FB8D2E")!
        #expect(plan.lift > 0)
        #expect(plan.lyricsAlpha <= 0.6)
        #expect(1 - plan.lyricsAlpha >= 0.4)
        #expect(plan.sidebarAlpha <= 0.8 && plan.contentAlpha <= 0.8)
        #expect(readable(plan, worst: worst, colors: colors))
        for (lifted, original) in [(plan.text, colors.text), (plan.textSecondary, colors.textSecondary), (plan.lyricsText, colors.lyricsText)] {
            #expect(abs(lifted.hue - original.hue) <= 3)
            #expect(lifted.lightness > original.lightness)
        }
        // The smallest lift that reaches the targets: one step less misses them.
        let less = BackdropPlan.plan(worst: worst, colors: colors, base: .dark, lift: plan.lift - BackdropPlan.liftStep)
        #expect(less.lyricsAlpha > 0.6 || less.sidebarAlpha > 0.8 || less.contentAlpha > 0.8)
    }

    @Test func alphasAreTheSmallestThatPass() throws {
        let colors = darkSkinColors
        let plan = try #require(BackdropPlan.make(backdrop: darkSkinArt, colors: colors, base: .dark))
        let worst = ThemeColor(hex: "#FB8D2E")!
        #expect(plan.sidebarAlpha > 0.37 && plan.contentAlpha > 0.37)
        #expect(!readable(plan, .sidebar, alpha: plan.sidebarAlpha - 0.02, worst: worst, colors: colors))
        #expect(!readable(plan, .content, alpha: plan.contentAlpha - 0.02, worst: worst, colors: colors))
        #expect(!readable(plan, .lyrics, alpha: plan.lyricsAlpha - 0.02, worst: worst, colors: colors))
    }

    @Test func readableColorsAreNotLifted() throws {
        let black = try #require(BackdropPlan.make(backdrop: solid(0), colors: darkSkinColors, base: .dark))
        #expect(black.lift == 0)
        #expect(black.text == darkSkinColors.text && black.textSecondary == darkSkinColors.textSecondary && black.lyricsText == darkSkinColors.lyricsText)

        // base-2.91: bright green on black, over grey-blue art.
        var base = dark
        base.background = ThemeColor(hex: "#000000")!
        base.surface = ThemeColor(hex: "#373756")!
        base.text = ThemeColor(hex: "#00FF00")!
        base.textSecondary = ThemeColor(hex: "#00A600")!
        base.lyricsText = ThemeColor(hex: "#00FF00")!
        let art = PNGFixture.make(width: 10, height: 10) { _, _ in (0x62, 0x62, 0x6D) }
        let plan = try #require(BackdropPlan.make(backdrop: art, colors: base, base: .dark))
        #expect(plan.lift == 0)
        #expect(plan.text == base.text)
        #expect(plan.sidebarAlpha <= 0.8 && plan.lyricsAlpha <= 0.6)
    }

    @Test func dimLyricsTextIsChecked() throws {
        var colors = dark
        colors.lyricsText = ThemeColor(hex: "#3A3A3A")! // readable text, near-invisible lyrics
        let plan = try #require(BackdropPlan.make(backdrop: solid(0), colors: colors, base: .dark))
        #expect(readable(plan, .lyrics, alpha: plan.lyricsAlpha, worst: .black, colors: colors))
        #expect(plan.lyricsAlpha <= plan.contentAlpha)
    }

    @Test func aLiftRescuesUnreadableText() throws {
        var bad = dark
        bad.text = ThemeColor(hex: "#202020")! // unreadable even on its own background
        let plan = try #require(BackdropPlan.make(backdrop: solid(255), colors: bad, base: .dark))
        #expect(plan.lift > 0)
        #expect(plan.lyricsAlpha < 1)
        #expect(readable(plan, worst: .white, colors: bad))
    }

    @Test func noLiftCanFixAGreyBackgroundSoPanelsGoOpaque() throws {
        var grey = dark
        grey.background = ThemeColor(hex: "#909090")!
        grey.surface = ThemeColor(hex: "#909090")!
        let plan = try #require(BackdropPlan.make(backdrop: solid(255), colors: grey, base: .dark))
        #expect(plan.sidebarAlpha == 1 && plan.contentAlpha == 1 && plan.lyricsAlpha == 1)
        #expect(plan.lift == 0) // lifting buys nothing, so the colors stay the theme's
    }

    @Test func whenTargetsAreOutOfReachTheLiftStopsWhereItStopsHelping() throws {
        // Winamp5 Classified: white text over near-white art on a blue background. White can't get lighter,
        // so past some step the lift only washes out the secondary color.
        var colors = dark
        colors.background = ThemeColor(hex: "#1C3D7D")!
        colors.surface = ThemeColor(hex: "#000101")!
        colors.text = .white
        colors.textSecondary = ThemeColor(hex: "#B0BBD2")!
        colors.lyricsText = .white
        let art = PNGFixture.make(width: 10, height: 10) { _, _ in (0xF4, 0xF4, 0xF6) }
        let plan = try #require(BackdropPlan.make(backdrop: art, colors: colors, base: .dark))
        let worst = ThemeColor(hex: "#F4F4F6")!
        let most = BackdropPlan.plan(worst: worst, colors: colors, base: .dark, lift: BackdropPlan.maxLift)
        #expect(plan.lyricsAlpha > 0.6) // out of reach
        #expect(plan.sidebarAlpha == most.sidebarAlpha && plan.contentAlpha == most.contentAlpha && plan.lyricsAlpha == most.lyricsAlpha)
        #expect(plan.lift < BackdropPlan.maxLift)
        if plan.lift > 0 {
            let less = BackdropPlan.plan(worst: worst, colors: colors, base: .dark, lift: plan.lift - BackdropPlan.liftStep)
            #expect(less.sidebarAlpha > plan.sidebarAlpha || less.contentAlpha > plan.contentAlpha || less.lyricsAlpha > plan.lyricsAlpha)
        }
        #expect(readable(plan, worst: worst, colors: colors))
    }

    @Test func tinyBackdropStillPlans() {
        #expect(BackdropPlan.make(backdrop: solid(0, size: 1), colors: dark, base: .dark) != nil)
        #expect(BackdropPlan.make(backdrop: Data("nope".utf8), colors: dark, base: .dark) == nil)
    }

    @Test func plansALargeImageQuickly() throws {
        let side = 2000
        let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.06, green: 0.03, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(CGColor(red: 0.98, green: 0.55, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side / 5)) // 20% bright: above the 95th percentile
        let image = try #require(context.makeImage())
        let start = ContinuousClock.now
        let plan = try #require(BackdropPlan.make(image: image, colors: darkSkinColors, base: .dark))
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(plan.lift > 0) // the bright band decides
    }
}
