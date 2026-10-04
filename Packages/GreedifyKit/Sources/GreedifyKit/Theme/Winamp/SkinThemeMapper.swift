import Foundation

/// Turns a Winamp skin into a Greedify theme (spec §3).
public enum SkinThemeMapper {
    /// `installedFonts` are the Mac's font family names; the skin's font is near-matched against them.
    public static func theme(fromArchive data: Data, fileName: String, installedFonts: [String]) throws -> Theme {
        if (fileName as NSString).pathExtension.lowercased() == "wal" { throw ThemeImportError.unsupportedModernSkin }
        return theme(from: try WinampSkin(archive: data), fileName: fileName, installedFonts: installedFonts)
    }

    public static func theme(from skin: WinampSkin, fileName: String, installedFonts: [String]) -> Theme {
        let playlist = skin.playlist, genex = skin.genex
        let background = genex?.itemBackground ?? playlist?.normalBG ?? skin.frameColor ?? skin.visColors.first ?? .black
        // Dark when white text reads better on the background than black does, so `base` matches the text's polarity.
        let base: ThemeBase = farthest(from: background) == .white ? .dark : .light
        var text = ensureContrast(genex?.itemForeground ?? playlist?.normal ?? farthest(from: background), on: background, 4.5)

        // The sidebar and headers put text on `surface` and `raised` too, so text must read on all three.
        let shifted = background.blended(toward: base == .dark ? .white : .black, 0.08)
        var surface = skin.frameColor.flatMap { abs($0.lightness - background.lightness) * 100 >= 4 ? $0 : nil } ?? shifted
        if text.contrast(with: surface) < 4.5 { surface = shifted }
        func raised(_ surface: ThemeColor, _ text: ThemeColor) -> ThemeColor { surface.blended(toward: text, 0.06) }
        func readable(on surface: ThemeColor, from start: ThemeColor) -> ThemeColor {
            var t = start
            for _ in 0..<4 { // `raised` follows `text`, so settle it in a few rounds
                t = ensureContrast(t, on: [background, surface, raised(surface, t)], 4.5)
            }
            return t
        }
        let candidateText = readable(on: surface, from: text)
        if minContrast(candidateText, [background, surface, raised(surface, candidateText)]) >= 4.5 {
            text = candidateText
        } else { // even black or white can't read on the shifted surface: shift it the other way
            surface = background.blended(toward: farthest(from: text), 0.08)
            text = readable(on: surface, from: text)
        }
        let textSecondary = ensureContrast(text.blended(toward: background, 0.35), on: [background, surface], 3)
        let selection = ensureContrast(genex?.selectionBackground ?? playlist?.selectedBG ?? background.blended(toward: text, 0.2),
                                       on: [text], 4.5, toward: background)

        // Accent: the most saturated candidate, preferring ones that already read on the background.
        var candidates: [ThemeColor] = []
        if let current = playlist?.current { candidates.append(current) }
        if skin.visColors.count > 2 { candidates += skin.visColors[2..<min(18, skin.visColors.count)] } // the spectrum bars
        if let frame = skin.frameColor { candidates.append(frame) }
        let ranked = candidates.enumerated()
            .filter { $0.element.saturation >= 0.25 && $0.element.contrast(with: text) >= 1.5 }
            .sorted { a, b in
                let (ra, rb) = (a.element.contrast(with: background) >= 3, b.element.contrast(with: background) >= 3)
                if ra != rb { return ra }
                if a.element.saturation != b.element.saturation { return a.element.saturation > b.element.saturation }
                return a.offset < b.offset
            }
            .map { ensureContrast($0.element, on: [background], 3) }
        let accent = ranked.first { $0.saturation >= 0.25 && $0.contrast(with: text) >= 1.5 && $0.contrast(with: background) >= 3 }
            ?? ensureContrast(Theme.defaults(for: base).colors.accent, on: [background], 3)

        var theme = Theme.defaults(for: base)
        theme.name = (fileName as NSString).deletingPathExtension
        theme.source = "Winamp skin \(fileName)"
        theme.colors = Theme.Colors(
            background: background, surface: surface, raised: raised(surface, text), text: text,
            textSecondary: textSecondary,
            accent: accent, onAccent: accent.contrast(with: .black) >= accent.contrast(with: .white) ? .black : .white,
            selection: selection, divider: text.withAlpha(0.15), lyricsText: text)
        theme.fonts = Theme.Fonts(family: playlist?.font.flatMap { FontMatcher.bestFamily(for: $0, among: installedFonts) },
                                  scale: 1, titleWeight: .bold)
        theme.shapes = Theme.Shapes(cardRadius: 2, buttonRadius: 2, artworkRadius: 2, rowRadius: 2, borderWidth: 1,
                                    buttonStyle: .bevel, density: .compact)
        theme.lyrics = .solid
        theme.images = Theme.Images(backdrop: Theme.Images.accept(skin.backdropPNG),
                                    pixelFont: Theme.Images.accept(skin.pixelFontPNG),
                                    seekBar: Theme.Images.accept(skin.seekBarPNG),
                                    volume: Theme.Images.accept(skin.volumePNG),
                                    digits: Theme.Images.accept(skin.digitsPNG))
        theme.controls = skin.controls
        return theme
    }

    /// Pushes `color` toward white or black, whichever the background allows more of, until it reaches `ratio`.
    static func ensureContrast(_ color: ThemeColor, on background: ThemeColor, _ ratio: Double) -> ThemeColor {
        ensureContrast(color, on: [background], ratio)
    }

    /// Pushes `color` toward `target` (default: white or black, whichever the first background allows more of)
    /// until its lowest contrast over all `backgrounds` reaches `ratio`. Returns `target` if nothing closer does.
    static func ensureContrast(_ color: ThemeColor, on backgrounds: [ThemeColor], _ ratio: Double,
                               toward target: ThemeColor? = nil) -> ThemeColor {
        func worst(_ c: ThemeColor) -> Double { minContrast(c, backgrounds) }
        guard worst(color) < ratio, let first = backgrounds.first else { return color }
        let target = target ?? farthest(from: first)
        for step in 1...20 {
            let candidate = color.blended(toward: target, Double(step) / 20)
            if worst(candidate) >= ratio { return candidate }
        }
        return target
    }

    static func minContrast(_ color: ThemeColor, _ backgrounds: [ThemeColor]) -> Double {
        backgrounds.map { color.contrast(with: $0) }.min() ?? 21
    }

    static func farthest(from background: ThemeColor) -> ThemeColor {
        background.contrast(with: .white) >= background.contrast(with: .black) ? .white : .black
    }
}
