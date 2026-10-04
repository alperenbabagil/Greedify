import AppKit
import GreedifyKit
import SwiftUI

/// The selected theme as SwiftUI values, built once per theme change (spec §5).
/// System uses live system colors, so it looks exactly like the app did before themes.
struct ResolvedTheme: Sendable {
    var isSystem: Bool
    var background, surface, raised, text, textSecondary, textTertiary, accent, onAccent, selection, divider, lyricsText: Color
    var family: String?
    var scale: CGFloat
    var titleWeight: Font.Weight
    var cardRadius, buttonRadius, artworkRadius, rowRadius, borderWidth: CGFloat
    var buttonStyle: ThemeButtonStyle
    var density: ThemeDensity
    var lyrics: LyricsStyle
    /// The skin's letterforms (`text.bmp`), decoded off the main actor after each theme change; nil until then.
    var pixelFont: PixelFont?
    /// A curated skin's recipe (curated skins spec §2); nil for System and the plain built-ins.
    var style: Style?
    var isWinamp: Bool { style?.bar?.layout == .winamp }
    /// Song lists drawn as Winamp's playlist editor: one dense line per song, no artwork (winamp window spec).
    var isPlaylistList: Bool { style?.list?.layout == .playlist }
    var isStripHeader: Bool { style?.pageHeader?.layout == .strip }

    /// The playlist editor's font: the recipe's list font, else the system font, at 11 pt.
    func listFont(weight: Font.Weight = .regular) -> Font {
        let size = CGFloat(style?.list?.size ?? 11)
        if case .family(let name)? = style?.list?.font { return Font.custom(name, fixedSize: size).weight(weight) }
        return .system(size: size, weight: weight)
    }

    init(_ entry: ThemeEntry, images: ThemeImages? = nil) {
        let t = entry.theme ?? Theme.defaults(for: .dark)
        isSystem = entry.isSystem
        if entry.isSystem {
            background = Color(nsColor: .windowBackgroundColor)
            surface = Color(nsColor: .underPageBackgroundColor)
            raised = Color(nsColor: .controlBackgroundColor)
            text = .primary
            textSecondary = .secondary
            textTertiary = Color(nsColor: .tertiaryLabelColor)
            accent = .accentColor
            onAccent = .white
            selection = Color.primary.opacity(0.1)
            divider = Color(nsColor: .separatorColor)
            lyricsText = .primary
        } else {
            let c = t.colors
            background = Color(c.background); surface = Color(c.surface); raised = Color(c.raised)
            text = Color(c.text); textSecondary = Color(c.textSecondary); textTertiary = Color(c.textSecondary).opacity(0.75)
            accent = Color(c.accent); onAccent = Color(c.onAccent); selection = Color(c.selection)
            divider = Color(c.divider); lyricsText = Color(c.lyricsText)
        }
        family = t.fonts.family // Font.custom falls back to the system font when a family isn't installed
        scale = t.fonts.scale
        titleWeight = switch t.fonts.titleWeight {
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
        cardRadius = t.shapes.cardRadius
        buttonRadius = t.shapes.buttonRadius
        artworkRadius = t.shapes.artworkRadius
        rowRadius = t.shapes.rowRadius
        borderWidth = t.shapes.borderWidth
        buttonStyle = t.shapes.buttonStyle
        density = t.shapes.density
        lyrics = entry.isSystem ? .solid : t.lyrics // System: plain window background, no blurred artwork
        if let images, !entry.isSystem { pixelFont = images.pixelFont }
        if !entry.isSystem, let style = t.style {
            self.style = style
            // The recipe's playlist colours are the text colours everywhere (curated skins spec §3).
            if let c = style.rows.normal?.text { text = Color(c) }
            if let c = style.rows.normal?.secondary { textSecondary = Color(c); textTertiary = Color(c).opacity(0.75) }
            if let c = style.rows.playing?.text ?? style.button?.active {
                accent = Color(c)
                // Text on accent-filled buttons: whichever of black or white reads on the new accent.
                onAccent = c.contrast(with: .black) >= c.contrast(with: .white) ? .black : .white
            }
            if let fill = style.rows.selected?.fill { selection = Color(fill.base) }
            if let c = style.divider { divider = Color(c) }
            if let c = style.text[.body]?.color { lyricsText = Color(c) }
            if case .family(let name)? = style.text[.body]?.font { family = name }
        }
    }

    static let system = ResolvedTheme(ThemeEntry(id: ThemeStore.systemID, theme: Theme.defaults(for: .dark), error: nil, isBuiltin: true))

    var rowHeight: CGFloat { density == .compact ? 44 : 56 }
    /// A playlist-editor line; episodes keep `rowHeight` (two lines).
    var playlistRowHeight: CGFloat { CGFloat(style?.list?.rowHeight ?? 18) }
    var rowArtworkSize: CGFloat { density == .compact ? 36 : 44 }
    var playerBarHeight: CGFloat { density == .compact ? 64 : 76 }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family { return Font.custom(family, fixedSize: size * scale).weight(weight) }
        return .system(size: size * scale, weight: weight)
    }

    func font(_ style: ThemeFontStyle) -> Font {
        if isSystem { return style.system }
        switch style {
        case .headline: return font(style.size, weight: .semibold)
        case .title, .display: return font(style.size, weight: titleWeight)
        default: return font(style.size)
        }
    }

    func color(_ role: TextRole) -> Color {
        switch role {
        case .primary: text
        case .secondary: textSecondary
        case .tertiary: textTertiary
        case .accent: accent
        }
    }
}

/// A theme's decoded pixel font. Built off the main actor (`AppModel.loadThemeImages`), so a theme switch never waits.
struct ThemeImages: Sendable {
    var pixelFont: PixelFont?

    init(_ theme: Theme) {
        pixelFont = theme.images.pixelFont.flatMap(PixelFont.init(png:))
    }
}

enum TextRole { case primary, secondary, tertiary, accent }

/// Text sizes. On System they map to the exact fonts the app used before themes.
enum ThemeFontStyle {
    case body, callout, subheadline, caption, caption2, headline, title, display

    var size: CGFloat {
        switch self {
        case .body, .headline: 13
        case .callout: 12
        case .subheadline: 11
        case .caption, .caption2: 10
        case .title: 17
        case .display: 34
        }
    }

    var system: Font {
        switch self {
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .caption: .caption
        case .caption2: .caption2
        case .headline: .headline
        case .title: .title2.bold()
        case .display: .system(size: 34, weight: .bold)
        }
    }
}

extension Color {
    init(_ c: ThemeColor) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }
}

extension EnvironmentValues {
    @Entry var theme: ResolvedTheme = .system
}

/// Root wrapper: puts the model's current theme into the environment and follows its changes.
struct Themed<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: Content
    var body: some View {
        // Every control inside (switches, links, spinners, fields, sheets, popovers) takes the theme's accent;
        // System keeps the Mac's own accent colour.
        content.environment(\.theme, model.theme).tint(model.theme.isSystem ? nil : model.theme.accent)
    }
}
