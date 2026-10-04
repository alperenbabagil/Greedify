import Foundation

public enum ThemeBase: String, Codable, Sendable { case light, dark }
public enum ThemeButtonStyle: String, Codable, Sendable { case flat, outlined, filled, bevel }
public enum ThemeDensity: String, Codable, Sendable { case compact, regular }
public enum ThemeFontWeight: String, Codable, Sendable { case regular, semibold, bold, heavy }
public enum LyricsStyle: String, Codable, Sendable { case artwork, solid }

/// A Greedify theme (spec: docs/superpowers/specs/2026-09-30-themes-design.md §2).
/// Decoding is lenient: every key is optional, and a bad value falls back on its own.
public struct Theme: Equatable, Sendable {
    public static let currentVersion = 1
    public static let scaleRange = 0.8...1.4
    public static let radiusRange = 0.0...24.0
    public static let borderRange = 0.0...3.0

    public struct Colors: Equatable, Sendable {
        public var background, surface, raised, text, textSecondary, accent, onAccent, selection, divider, lyricsText: ThemeColor
    }

    public struct Fonts: Equatable, Sendable {
        public var family: String?
        public var scale: Double
        public var titleWeight: ThemeFontWeight
    }

    public struct Shapes: Equatable, Sendable {
        public var cardRadius, buttonRadius, artworkRadius, rowRadius, borderWidth: Double
        public var buttonStyle: ThemeButtonStyle
        public var density: ThemeDensity
    }

    /// Optional skin images, stored in the file as base64 PNG (theme images spec §2, skinned controls spec §3.3).
    public struct Images: Equatable, Sendable {
        public static let maxBytes = 524_288
        public var backdrop: Data?
        public var pixelFont: Data?
        /// `posbar.bmp` as a 307×10 strip: groove, handle, pressed handle.
        public var seekBar: Data?
        /// `volume.bmp`: 28 fill frames, then the handles when the skin has them.
        public var volume: Data?
        /// Digits 0–9 and a blank (99×13), plus a minus when the skin has one (108×13).
        public var digits: Data?
        public init(backdrop: Data? = nil, pixelFont: Data? = nil, seekBar: Data? = nil, volume: Data? = nil, digits: Data? = nil) {
            self.backdrop = backdrop; self.pixelFont = pixelFont; self.seekBar = seekBar; self.volume = volume; self.digits = digits
        }
        public var isEmpty: Bool { backdrop == nil && pixelFont == nil && seekBar == nil && volume == nil && digits == nil }

        /// PNG bytes within the size limit, else nil.
        static func accept(_ data: Data?) -> Data? {
            guard let data, data.count <= maxBytes, ThemeImage.isPNG(data) else { return nil }
            return data
        }
    }

    /// A skin's button colours, sampled from its sprites (skinned controls spec §3.2).
    public struct Controls: Equatable, Sendable {
        public var faceTop, faceBottom, highlight, shadow, glyph: ThemeColor?
        public var pressedFaceTop, pressedFaceBottom, pressedGlyph: ThemeColor?
        public var on, panel: ThemeColor?
        public init() {}
        /// Enough to draw a button and the bar.
        public var isUsable: Bool { faceTop != nil && faceBottom != nil && panel != nil }
    }

    public var version = Theme.currentVersion
    public var name: String
    public var author: String?
    public var source: String?
    public var base: ThemeBase
    public var colors: Colors
    public var fonts: Fonts
    public var shapes: Shapes
    public var lyrics: LyricsStyle
    public var images = Images()
    public var controls: Controls?
    /// A curated skin's recipe (curated skins spec §2); nil for every other theme.
    public var style: Style?
    /// Where the theme's art comes from (Settings → Credits).
    public var credits: [Credit] = []

    public struct Credit: Codable, Equatable, Sendable {
        public var title: String
        public var detail: String
        public var url: URL?
        public init(title: String, detail: String, url: URL?) { self.title = title; self.detail = detail; self.url = url }
    }

    /// What a theme gets for anything it leaves out: macOS's own dark or light colors.
    public static func defaults(for base: ThemeBase) -> Theme {
        func c(_ hex: String) -> ThemeColor { ThemeColor(hex: hex)! }
        let colors = base == .dark
            ? Colors(background: c("#1E1E1E"), surface: c("#282828"), raised: c("#323232"), text: c("#F2F2F2"),
                     textSecondary: c("#9A9A9A"), accent: c("#0A84FF"), onAccent: c("#FFFFFF"), selection: c("#3A3A3C"),
                     divider: c("#FFFFFF1A"), lyricsText: c("#FFFFFF"))
            : Colors(background: c("#FFFFFF"), surface: c("#F5F5F7"), raised: c("#FFFFFF"), text: c("#1D1D1F"),
                     textSecondary: c("#6E6E73"), accent: c("#007AFF"), onAccent: c("#FFFFFF"), selection: c("#E5E5EA"),
                     divider: c("#0000001A"), lyricsText: c("#1D1D1F"))
        return Theme(name: "Untitled", author: nil, source: nil, base: base, colors: colors,
                     fonts: Fonts(family: nil, scale: 1, titleWeight: .bold),
                     shapes: Shapes(cardRadius: 8, buttonRadius: 6, artworkRadius: 4, rowRadius: 6, borderWidth: 0,
                                    buttonStyle: .filled, density: .regular),
                     lyrics: .artwork)
    }

    public static func decode(from data: Data) throws -> Theme { try JSONDecoder().decode(Theme.self, from: data) }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

extension Theme: Codable {
    private enum Keys: String, CodingKey { case version, name, author, source, base, colors, fonts, shapes, lyrics, images, controls, style, credits }
    private enum ImageKeys: String, CodingKey { case backdrop, pixelFont, seekBar, volume, digits }
    private enum ControlKeys: String, CodingKey {
        case faceTop, faceBottom, highlight, shadow, glyph, pressedFaceTop, pressedFaceBottom, pressedGlyph, on, panel
    }
    private static var controlPaths: [(ControlKeys, WritableKeyPath<Controls, ThemeColor?>)] {
        [(.faceTop, \.faceTop), (.faceBottom, \.faceBottom), (.highlight, \.highlight), (.shadow, \.shadow), (.glyph, \.glyph),
         (.pressedFaceTop, \.pressedFaceTop), (.pressedFaceBottom, \.pressedFaceBottom), (.pressedGlyph, \.pressedGlyph),
         (.on, \.on), (.panel, \.panel)]
    }
    private enum ColorKeys: String, CodingKey {
        case background, surface, raised, text, textSecondary, accent, onAccent, selection, divider, lyricsText
    }
    private enum FontKeys: String, CodingKey { case family, scale, titleWeight }
    private enum ShapeKeys: String, CodingKey { case cardRadius, buttonRadius, artworkRadius, rowRadius, borderWidth, buttonStyle, density }

    // Computed, not stored: key paths aren't Sendable, so a static let would trip Swift 6's checks.
    private static var colorPaths: [(ColorKeys, WritableKeyPath<Colors, ThemeColor>)] {
        [(.background, \.background), (.surface, \.surface), (.raised, \.raised), (.text, \.text),
         (.textSecondary, \.textSecondary), (.accent, \.accent), (.onAccent, \.onAccent), (.selection, \.selection),
         (.divider, \.divider), (.lyricsText, \.lyricsText)]
    }
    private static var radiusPaths: [(ShapeKeys, WritableKeyPath<Shapes, Double>)] {
        [(.cardRadius, \.cardRadius), (.buttonRadius, \.buttonRadius), (.artworkRadius, \.artworkRadius), (.rowRadius, \.rowRadius)]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var t = Theme.defaults(for: (try? c.decode(ThemeBase.self, forKey: .base)) ?? .dark)
        t.version = (try? c.decode(Int.self, forKey: .version)) ?? Theme.currentVersion
        if let name = try? c.decode(String.self, forKey: .name), !name.isEmpty { t.name = name }
        t.author = try? c.decode(String.self, forKey: .author)
        t.source = try? c.decode(String.self, forKey: .source)
        if let lyrics = try? c.decode(LyricsStyle.self, forKey: .lyrics) { t.lyrics = lyrics }

        if let cc = try? c.nestedContainer(keyedBy: ColorKeys.self, forKey: .colors) {
            for (key, path) in Self.colorPaths {
                if let hex = try? cc.decode(String.self, forKey: key), let color = ThemeColor(hex: hex) { t.colors[keyPath: path] = color }
            }
        }
        if let fc = try? c.nestedContainer(keyedBy: FontKeys.self, forKey: .fonts) {
            if let family = try? fc.decode(String.self, forKey: .family) {
                let trimmed = family.trimmingCharacters(in: .whitespaces)
                t.fonts.family = trimmed.isEmpty ? nil : trimmed
            }
            if let scale = try? fc.decode(Double.self, forKey: .scale) { t.fonts.scale = scale.clamped(to: Self.scaleRange) }
            if let weight = try? fc.decode(ThemeFontWeight.self, forKey: .titleWeight) { t.fonts.titleWeight = weight }
        }
        if let sc = try? c.nestedContainer(keyedBy: ShapeKeys.self, forKey: .shapes) {
            for (key, path) in Self.radiusPaths {
                if let v = try? sc.decode(Double.self, forKey: key) { t.shapes[keyPath: path] = v.clamped(to: Self.radiusRange) }
            }
            if let v = try? sc.decode(Double.self, forKey: .borderWidth) { t.shapes.borderWidth = v.clamped(to: Self.borderRange) }
            if let v = try? sc.decode(ThemeButtonStyle.self, forKey: .buttonStyle) { t.shapes.buttonStyle = v }
            if let v = try? sc.decode(ThemeDensity.self, forKey: .density) { t.shapes.density = v }
        }
        if let ic = try? c.nestedContainer(keyedBy: ImageKeys.self, forKey: .images) {
            func image(_ key: ImageKeys) -> Data? {
                (try? ic.decode(String.self, forKey: key))
                    .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
                    .flatMap(Images.accept)
            }
            t.images = Images(backdrop: image(.backdrop), pixelFont: image(.pixelFont),
                              seekBar: image(.seekBar), volume: image(.volume), digits: image(.digits))
        }
        if let kc = try? c.nestedContainer(keyedBy: ControlKeys.self, forKey: .controls) {
            var controls = Controls()
            for (key, path) in Self.controlPaths {
                if let hex = try? kc.decode(String.self, forKey: key), let color = ThemeColor(hex: hex) { controls[keyPath: path] = color }
            }
            t.controls = controls.isUsable ? controls : nil
        }
        // Strict (tests of built-in recipes): a broken recipe is an error, not a silently plain theme.
        t.style = Style.strict ? try c.decodeIfPresent(Style.self, forKey: .style) : (try? c.decodeIfPresent(Style.self, forKey: .style)) ?? nil
        // Per entry: one bad credit doesn't hide the others.
        t.credits = ((try? c.decode([Failable<Credit>].self, forKey: .credits)) ?? []).compactMap(\.value)
        self = t
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encode(base, forKey: .base)
        try c.encode(lyrics, forKey: .lyrics)
        var cc = c.nestedContainer(keyedBy: ColorKeys.self, forKey: .colors)
        for (key, path) in Self.colorPaths { try cc.encode(colors[keyPath: path].hex, forKey: key) }
        var fc = c.nestedContainer(keyedBy: FontKeys.self, forKey: .fonts)
        try fc.encodeIfPresent(fonts.family, forKey: .family)
        try fc.encode(fonts.scale, forKey: .scale)
        try fc.encode(fonts.titleWeight, forKey: .titleWeight)
        var sc = c.nestedContainer(keyedBy: ShapeKeys.self, forKey: .shapes)
        for (key, path) in Self.radiusPaths { try sc.encode(shapes[keyPath: path], forKey: key) }
        try sc.encode(shapes.borderWidth, forKey: .borderWidth)
        try sc.encode(shapes.buttonStyle, forKey: .buttonStyle)
        try sc.encode(shapes.density, forKey: .density)
        if !images.isEmpty {
            var ic = c.nestedContainer(keyedBy: ImageKeys.self, forKey: .images)
            try ic.encodeIfPresent(images.backdrop?.base64EncodedString(), forKey: .backdrop)
            try ic.encodeIfPresent(images.pixelFont?.base64EncodedString(), forKey: .pixelFont)
            try ic.encodeIfPresent(images.seekBar?.base64EncodedString(), forKey: .seekBar)
            try ic.encodeIfPresent(images.volume?.base64EncodedString(), forKey: .volume)
            try ic.encodeIfPresent(images.digits?.base64EncodedString(), forKey: .digits)
        }
        try c.encodeIfPresent(style, forKey: .style)
        if !credits.isEmpty { try c.encode(credits, forKey: .credits) }
        if let controls, controls.isUsable {
            var kc = c.nestedContainer(keyedBy: ControlKeys.self, forKey: .controls)
            for (key, path) in Self.controlPaths { try kc.encodeIfPresent(controls[keyPath: path]?.hex, forKey: key) }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

extension Theme {
    /// Built-in theme files (`Theme/Builtin/<slug>.greedifytheme`), System first.
    public static let builtinOrder = ["system", "classic", "modern", "paper", "high-contrast", "winamp-classic", "winamp5-classified"]

    /// The themes that ship with Greedify, ids `builtin.<slug>` (spec §2).
    public static func builtins() -> [(id: String, theme: Theme)] {
        builtinOrder.compactMap { slug in
            guard let url = builtinURL(slug),
                  let data = try? Data(contentsOf: url), let theme = try? Theme.decode(from: data) else { return nil }
            return ("builtin.\(slug)", theme)
        }
    }

    static func builtinURL(_ slug: String) -> URL? { Bundle.module.url(forResource: slug, withExtension: "greedifytheme") }
}
