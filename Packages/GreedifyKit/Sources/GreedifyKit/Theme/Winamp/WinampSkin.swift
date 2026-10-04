import Foundation

/// Why a skin or theme file couldn't be imported; the messages are shown to the user as-is.
public enum ThemeImportError: Error, Equatable, LocalizedError {
    case unsupportedModernSkin, noColorSources, unreadable

    public var errorDescription: String? {
        switch self {
        case .unsupportedModernSkin: "This looks like a Winamp 3/5 skin; only classic (.wsz) skins are supported."
        case .noColorSources: "No color files found in this skin."
        case .unreadable: "Couldn't read this file."
        }
    }
}

/// What Greedify reads from a classic Winamp 2 skin: colours, main.bmp and text.bmp (themes and theme images specs), and the control sprites (skinned controls spec).
public struct WinampSkin: Equatable, Sendable {
    public struct PlaylistColors: Equatable, Sendable {
        public var normal: ThemeColor?
        public var current: ThemeColor?
        public var normalBG: ThemeColor?
        public var selectedBG: ThemeColor?
        public var font: String?
    }

    /// Winamp 2.9 `genex.bmp` swatches, read at x = 48, 50, 52… on row 0 (as Webamp does).
    public struct GenexColors: Equatable, Sendable {
        public var itemBackground, itemForeground, windowBackground, buttonText, windowText, divider, selectionBackground: ThemeColor
    }

    public var playlist: PlaylistColors?
    public var visColors: [ThemeColor] = []
    public var frameColor: ThemeColor?
    public var genex: GenexColors?
    /// `main.bmp` re-encoded as PNG: the theme's backdrop (theme images spec §3).
    public var backdropPNG: Data?
    /// `text.bmp` re-encoded as PNG when it holds the full glyph grid: the pixel font.
    public var pixelFontPNG: Data?
    /// Button colours sampled from `cbuttons.bmp`, `shufrep.bmp` and `main.bmp` (skinned controls spec §3.2).
    public var controls: Theme.Controls?
    /// `posbar.bmp`, `volume.bmp` and the digits, cropped (skinned controls spec §3.3).
    public var seekBarPNG: Data?
    public var volumePNG: Data?
    public var digitsPNG: Data?
}

extension WinampSkin {
    public init(archive data: Data) throws {
        let zip: ZipReader
        do { zip = try ZipReader(data: data) } catch { throw ThemeImportError.unreadable }
        if zip.entry(named: "skin.xml") != nil { throw ThemeImportError.unsupportedModernSkin }
        func read(_ name: String) -> Data? { zip.entry(named: name).flatMap { try? zip.contents(of: $0) } }

        self.init()
        playlist = read("pledit.txt").flatMap { Self.parsePledit(Self.text($0)) }
        visColors = read("viscolor.txt").map { Self.parseViscolor(Self.text($0)) } ?? []
        let main = read("main.bmp")
        let mainBitmap = main.flatMap(SkinBitmap.init(data:))
        frameColor = mainBitmap.flatMap(Self.frameColor(of:))
        controls = SkinControlPalette.make(cbuttons: read("cbuttons.bmp").flatMap(SkinBitmap.init(data:)),
                                           shufrep: read("shufrep.bmp").flatMap(SkinBitmap.init(data:)), main: mainBitmap)
        seekBarPNG = read("posbar.bmp").flatMap(SkinSprites.seekBarPNG(from:))
        volumePNG = read("volume.bmp").flatMap(SkinSprites.volumePNG(from:))
        digitsPNG = SkinSprites.digitsPNG(numbers: read("numbers.bmp"), numsEx: read("nums_ex.bmp"))
        backdropPNG = main.flatMap(ThemeImage.png(fromImageData:))
        pixelFontPNG = read("text.bmp").flatMap(Self.pixelFontPNG(from:))
        genex = read("genex.bmp").flatMap(SkinBitmap.init(data:)).flatMap(Self.genexColors(of:))
        guard playlist != nil || !visColors.isEmpty || frameColor != nil || genex != nil else { throw ThemeImportError.noColorSources }
    }

    /// Skins from the Winamp era are often Windows-1252, not UTF-8.
    static func text(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// The `[Text]` section of `pledit.txt`. Keys ignore case, `#` is optional; colors and the font name are cut at a trailing `;` comment.
    static func parsePledit(_ text: String) -> PlaylistColors? {
        var section = "", values: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { section = line.lowercased(); continue }
            guard section == "[text]", let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            values[key] = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        }
        func color(_ key: String) -> ThemeColor? {
            values[key].flatMap { ThemeColor(hex: String($0.prefix { !$0.isWhitespace && $0 != ";" && $0 != "/" })) }
        }
        let font = values["font"].flatMap { raw -> String? in
            let name = (raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? raw)
                .trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        let colors = PlaylistColors(normal: color("normal"), current: color("current"), normalBG: color("normalbg"),
                                    selectedBG: color("selectedbg"), font: font)
        return colors == PlaylistColors() ? nil : colors
    }

    /// Up to 24 `r,g,b` lines; `//` comments and lines without three 0...255 numbers are skipped.
    static func parseViscolor(_ text: String) -> [ThemeColor] {
        var colors: [ThemeColor] = []
        for line in text.components(separatedBy: .newlines) {
            let code = line.components(separatedBy: "//")[0]
            let numbers = code.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Int($0) }
            guard numbers.count >= 3, numbers.prefix(3).allSatisfy({ (0...255).contains($0) }) else { continue }
            colors.append(ThemeColor(r8: numbers[0], g8: numbers[1], b8: numbers[2]))
            if colors.count == 24 { break }
        }
        return colors
    }

    /// `text.bmp` as PNG, or nil when it's too small to hold the full glyph grid.
    static func pixelFontPNG(from data: Data) -> Data? {
        guard let image = ThemeImage.cgImage(data),
              image.width >= ThemeImage.pixelFontMinWidth, image.height >= ThemeImage.pixelFontMinHeight else { return nil }
        return ThemeImage.png(image)
    }

    /// `main.bmp`'s dominant color along its top and bottom 14-pixel strips (the window frame).
    static func frameColor(of bitmap: SkinBitmap) -> ThemeColor? {
        let strip = min(14, bitmap.height)
        return bitmap.dominantColor(in: [(0..<bitmap.width, 0..<strip),
                                         (0..<bitmap.width, (bitmap.height - strip)..<bitmap.height)])
    }

    static func genexColors(of bitmap: SkinBitmap) -> GenexColors? {
        let swatches = (0..<7).compactMap { bitmap.color(x: 48 + $0 * 2, y: 0) }
        guard swatches.count == 7 else { return nil }
        return GenexColors(itemBackground: swatches[0], itemForeground: swatches[1], windowBackground: swatches[2],
                           buttonText: swatches[3], windowText: swatches[4], divider: swatches[5], selectionBackground: swatches[6])
    }
}
