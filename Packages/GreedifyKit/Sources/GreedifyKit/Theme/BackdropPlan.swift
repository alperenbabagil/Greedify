import CoreGraphics
import Foundation

/// How opaque each panel must be over the backdrop, and how far the text colors are lifted, so text stays
/// readable while the art still shows (theme images spec §5).
public struct BackdropPlan: Equatable, Sendable {
    /// Over `surface`: the sidebar and the player-bar tiles.
    public let sidebarAlpha: Double
    /// Over `background`: the detail content.
    public let contentAlpha: Double
    /// Over `background`: the solid-mode lyrics panel. Never above `contentAlpha`.
    public let lyricsAlpha: Double
    /// The share of the remaining HSL lightness the text colors moved away from the background (0 = unchanged).
    public let lift: Double
    /// The theme's text colors after the lift; use these instead of the theme's while the backdrop shows.
    public let text: ThemeColor
    public let textSecondary: ThemeColor
    public let lyricsText: ThemeColor

    public init(sidebarAlpha: Double, contentAlpha: Double, lyricsAlpha: Double, lift: Double,
                text: ThemeColor, textSecondary: ThemeColor, lyricsText: ThemeColor) {
        self.sidebarAlpha = sidebarAlpha
        self.contentAlpha = contentAlpha
        self.lyricsAlpha = lyricsAlpha
        self.lift = lift
        self.text = text
        self.textSecondary = textSecondary
        self.lyricsText = lyricsText
    }

    public static let minAlpha = 0.35
    public static let maxAlpha = 0.95
    /// The lift stops at the first step where the lyrics show at least 40% art and the other panels 20%.
    public static let lyricsTarget = 0.6
    public static let panelTarget = 0.8
    public static let liftStep = 0.05
    public static let maxLift = 0.6
    /// The worst case is taken from at most this many pixels (the image is sampled down first).
    public static let planningPixels = 65_536

    /// nil when the backdrop can't be decoded or is over `ThemeImage.maxPixels`.
    public static func make(backdrop: Data, colors: Theme.Colors, base: ThemeBase) -> BackdropPlan? {
        ThemeImage.cgImage(backdrop).flatMap { make(image: $0, colors: colors, base: base) }
    }

    public static func make(image: CGImage, colors: Theme.Colors, base: ThemeBase) -> BackdropPlan? {
        guard let worst = worstCase(image, base: base) else { return nil }
        let steps = Int((maxLift / liftStep).rounded())
        let candidates = (0...steps).map { plan(worst: worst, colors: colors, base: base, lift: (Double($0) * liftStep * 100).rounded() / 100) }
        if let first = candidates.first(where: { $0.lyricsAlpha <= lyricsTarget && $0.sidebarAlpha <= panelTarget && $0.contentAlpha <= panelTarget }) {
            return first
        }
        // Out of reach: the alphas of the largest lift, from the smallest lift that already gets them, so a
        // lift that no longer lowers any alpha doesn't wash out the colors for nothing.
        let most = candidates[candidates.count - 1]
        return candidates.first { $0.sidebarAlpha <= most.sidebarAlpha && $0.contentAlpha <= most.contentAlpha && $0.lyricsAlpha <= most.lyricsAlpha } ?? most
    }

    /// The alphas for the theme's text colors lifted by `lift`.
    static func plan(worst: ThemeColor, colors: Theme.Colors, base: ThemeBase, lift: Double) -> BackdropPlan {
        let lighter = base == .dark
        let text = colors.text.lifted(lift, lighter: lighter)
        let secondary = colors.textSecondary.lifted(lift, lighter: lighter)
        let lyricsText = colors.lyricsText.lifted(lift, lighter: lighter)
        let lists = [(text, 4.5), (secondary, 3.0)]
        let sidebar = smallestAlpha(worst: worst, over: colors.surface, needs: lists, base: base)
        let content = smallestAlpha(worst: worst, over: colors.background, needs: lists, base: base)
        let lyrics = smallestAlpha(worst: worst, over: colors.background, needs: lists + [(lyricsText, 4.5)], base: base)
        // Lyrics check a superset of content's colors over the same fill, so they can't need less; when a dim
        // lyrics color needs more, content follows, keeping the art behind the lyrics at least as visible.
        return BackdropPlan(sidebarAlpha: sidebar, contentAlpha: max(content, lyrics), lyricsAlpha: lyrics, lift: lift,
                            text: text, textSecondary: secondary, lyricsText: lyricsText)
    }

    /// The panel color `area` at `alpha` over the backdrop color `worst`.
    public static func blend(_ worst: ThemeColor, over area: ThemeColor, alpha: Double) -> ThemeColor {
        worst.blended(toward: area.withAlpha(1), alpha)
    }

    /// The smallest alpha in `minAlpha...maxAlpha`, rounded up to 0.01, at which every color meets its ratio
    /// on the blend and stays on the text's side of it (lighter on a dark base); 1 when even `maxAlpha` fails.
    static func smallestAlpha(worst: ThemeColor, over area: ThemeColor, needs: [(ThemeColor, Double)], base: ThemeBase) -> Double {
        func passes(_ alpha: Double) -> Bool {
            let panel = blend(worst, over: area, alpha: alpha)
            return needs.allSatisfy { color, ratio in
                color.contrast(with: panel) >= ratio && (base == .dark ? color.luminance >= panel.luminance : color.luminance <= panel.luminance)
            }
        }
        if passes(minAlpha) { return minAlpha }
        guard passes(maxAlpha) else { return 1 }
        var (low, high) = (minAlpha, maxAlpha) // fails at low, passes at high
        while high - low > 0.001 {
            let mid = (low + high) / 2
            if passes(mid) { high = mid } else { low = mid }
        }
        // Round up to hundredths; step up once more if rounding landed on a failing value.
        var alpha = min(maxAlpha, (high * 100 - 1e-9).rounded(.up) / 100)
        if !passes(alpha) { alpha = min(maxAlpha, alpha + 0.01) }
        return alpha
    }

    /// The pixel at the 95th luminance percentile (dark base: bright art fights light text) or the 5th
    /// (light base), from the image sampled down to `planningPixels`.
    static func worstCase(_ image: CGImage, base: ThemeBase) -> ThemeColor? {
        guard let bitmap = SkinBitmap(image: image, fittingIn: planningPixels) else { return nil }
        let linear = (0...255).map { v -> Float in
            let c = Double(v) / 255
            return Float(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
        let bins = 1024
        var luminances: [Float] = []
        var rgb: [(UInt8, UInt8, UInt8)] = []
        luminances.reserveCapacity(bitmap.width * bitmap.height)
        rgb.reserveCapacity(bitmap.width * bitmap.height)
        var histogram = [Int](repeating: 0, count: bins)
        func bin(_ y: Float) -> Int { min(bins - 1, Int(y * Float(bins))) }
        bitmap.forEachPixel { r, g, b in
            let y = 0.2126 * linear[Int(r)] + 0.7152 * linear[Int(g)] + 0.0722 * linear[Int(b)]
            luminances.append(y)
            rgb.append((r, g, b))
            histogram[bin(y)] += 1
        }
        guard !luminances.isEmpty else { return nil }
        let rank = Int(Double(luminances.count - 1) * (base == .dark ? 0.95 : 0.05))
        // Find the bin holding the rank, then order only that bin's pixels.
        var below = 0, target = 0
        while below + histogram[target] <= rank { below += histogram[target]; target += 1 }
        let inBin = luminances.indices.filter { bin(luminances[$0]) == target }.sorted { luminances[$0] < luminances[$1] }
        let (r, g, b) = rgb[inBin[rank - below]]
        return ThemeColor(r8: Int(r), g8: Int(g), b8: Int(b))
    }
}
