import Foundation

/// Drafts a curated recipe from a classic `.wsz` (curated skins spec §5): measures the skin's palette, LCD, digits,
/// buttons, sliders and surfaces, and writes them as a `Theme` with a `style`. The draft is a starting point for
/// hand-tuning; `notes` says what each value was measured from.
public enum SkinRecipeMaker {
    public struct Draft: Sendable {
        public var theme: Theme
        public var notes: [String]
        /// A reference sheet (PNG) of the skin's art with the sampled areas boxed, for the tuner; never bundled.
        public var contactSheet: Data?
    }

    typealias Rect = SkinControlPalette.Rect
    /// `main.bmp`'s display: the time area and the scrolling title.
    static let timeBox = Rect(x: 24, y: 26, w: 76, h: 16)
    static let titleBox = Rect(x: 111, y: 24, w: 153, h: 12)
    /// A large plain area of `main.bmp` (between the title bar and the controls) for the surface material.
    static let surfaceBox = Rect(x: 0, y: 44, w: 275, h: 44)

    public static func recipe(fromArchive data: Data, name: String, fileName: String) throws -> Draft {
        let zip: ZipReader
        do { zip = try ZipReader(data: data) } catch { throw ThemeImportError.unreadable }
        func read(_ file: String) -> Data? { zip.entry(named: file).flatMap { try? zip.contents(of: $0) } }
        func bitmap(_ file: String) -> SkinBitmap? { read(file).flatMap(SkinBitmap.init(data:)) }

        let skin = try WinampSkin(archive: data)
        var theme = SkinThemeMapper.theme(from: skin, fileName: fileName, installedFonts: [])
        theme.name = name
        theme.images = Theme.Images(pixelFont: theme.images.pixelFont)      // no bitmaps besides the letterforms
        theme.controls = nil
        let palette = skin.controls
        var notes: [String] = []
        var style = Style()

        let main = bitmap("main.bmp"), cbuttons = bitmap("cbuttons.bmp"), posbar = bitmap("posbar.bmp")
        let volume = bitmap("volume.bmp"), numbers = bitmap("nums_ex.bmp") ?? bitmap("numbers.bmp")
        let c = theme.colors

        // Surfaces
        let surface = main.map(surfaceMaterial(main:)) ?? .solid(c.surface)
        style.materials = [.window: .solid(skin.playlist?.normalBG ?? c.background), .sidebar: surface, .bar: surface,
                           .header: .solid(c.surface), .popover: surface, .lyrics: .solid(skin.playlist?.normalBG ?? c.background)]
        notes.append("materials.bar/sidebar/popover: main.bmp \(surfaceBox) → \(describe(surface))")
        let light = palette?.highlight ?? c.text.withAlpha(0.5), dark = palette?.shadow ?? .black
        style.bevels = [.panel: Style.Bevel(kind: .sunken, light: light, dark: dark, width: 1),
                        .bar: Style.Bevel(kind: .raised, light: light, dark: dark, width: 1)]
        style.divider = c.divider
        notes.append("bevels: the play button's edges (cbuttons.bmp)")

        // Playlist rows
        var rows = Style.RowStyles()
        rows.normal = Style.RowStyle(fill: .solid(skin.playlist?.normalBG ?? c.background), text: skin.playlist?.normal ?? c.text, secondary: c.textSecondary)
        rows.selected = Style.RowStyle(fill: .solid(skin.playlist?.selectedBG ?? c.selection), text: skin.playlist?.current ?? c.text)
        rows.playing = Style.RowStyle(text: skin.playlist?.current ?? c.accent)
        rows.hover = Style.RowStyle(fill: .solid((skin.playlist?.normalBG ?? c.background).blended(toward: c.text, 0.06)))
        style.rows = rows
        notes.append("rows: pledit.txt Normal / NormalBG / Current / SelectedBG")

        // LCD
        var lcd = Style.LCDSpec()
        lcd.material = main.map(lcdMaterial(main:)) ?? .solid(.black)
        lcd.bevel = Style.Bevel(kind: .sunken, light: light, dark: dark, width: 1)
        lcd.digits = digits(numbers: numbers)
        let ink = numbers.flatMap(digitInk(numbers:)) ?? skin.playlist?.normal ?? c.text
        lcd.text = ink
        lcd.info = ink.blended(toward: lcd.material?.base ?? .black, 0.35)
        lcd.glow = 1
        style.lcd = lcd
        notes.append("lcd.material: main.bmp \(timeBox) → \(describe(lcd.material!)); lcd.digits: digit 8 of nums_ex/numbers → \(lcd.digits!.rawValue); lcd.text: the digits' ink")

        // Buttons
        var button = Style.ButtonSpec()
        button.shape = cbuttons.map(buttonShape(cbuttons:)) ?? .rect
        button.radius = button.shape == .rounded ? 3 : nil
        if let top = palette?.faceTop, let bottom = palette?.faceBottom {
            button.face = .gradient(angle: 90, stops: [.init(color: top, at: 0), .init(color: bottom, at: 1)])
        }
        button.bevel = Style.Bevel(kind: .raised, light: light, dark: dark, width: 1)
        button.glyph = palette?.glyph ?? c.text
        button.glyphWeight = .bold
        var pressed = Style.PressedSpec()
        if let top = palette?.pressedFaceTop, let bottom = palette?.pressedFaceBottom {
            pressed.face = .gradient(angle: 90, stops: [.init(color: top, at: 0), .init(color: bottom, at: 1)])
        }
        pressed.glyph = palette?.pressedGlyph
        button.pressed = pressed
        button.active = palette?.on ?? c.accent
        style.button = button
        notes.append("button: cbuttons.bmp play sprite → shape \(button.shape!.rawValue), face gradient at 25 %/75 %; active: shufrep.bmp lit pixel")

        // Sliders
        var slider = Style.SliderSpec()
        var groove = Style.GrooveSpec()
        groove.material = .solid(posbar.flatMap { $0.dominantColor(in: [(0..<248, 0..<10)]) } ?? c.divider)
        groove.bevel = Style.Bevel(kind: .sunken, light: light, dark: dark, width: 1)
        groove.height = 6
        slider.groove = groove
        var thumb = Style.ThumbSpec()
        thumb.shape = .rounded; thumb.width = 29; thumb.height = 10
        thumb.face = .solid(posbar.flatMap { $0.dominantColor(in: [(248..<277, 0..<10)]) } ?? c.text)
        thumb.bevel = Style.Bevel(kind: .raised, light: light, dark: dark, width: 1)
        slider.thumb = thumb
        slider.fill = Style.FillSpec(kind: .none, colors: [])
        style.slider = slider
        var volumeSpec = slider
        let ramp = volume.map(volumeRamp(volume:)) ?? []
        volumeSpec.fill = ramp.count == 3 ? Style.FillSpec(kind: .ramp, colors: ramp) : Style.FillSpec(kind: .solid, colors: [c.accent])
        volumeSpec.thumb?.width = 14; volumeSpec.thumb?.height = 11
        style.volume = volumeSpec
        notes.append("slider: posbar.bmp groove and handle; volume.fill: volume.bmp frames 0/14/27")

        // Text and bar
        let hasPixelFont = theme.images.pixelFont != nil
        style.text = [.title: Style.TextSpec(font: hasPixelFont ? .pixel : .system, size: 13, weight: .bold, color: ink, glow: 1),
                      .body: Style.TextSpec(color: skin.playlist?.normal ?? c.text),
                      .secondary: Style.TextSpec(color: c.textSecondary),
                      .header: Style.TextSpec(weight: .semibold, color: c.textSecondary)]
        style.bar = Style.BarSpec(layout: .winamp, height: 110, artwork: true)
        notes.append("text.title: \(hasPixelFont ? "text.bmp pixel font" : "system (no usable text.bmp)")")

        theme.style = style
        return Draft(theme: theme, notes: notes, contactSheet: contactSheet(main: read("main.bmp"), sprites: [
            read("cbuttons.bmp"), read("posbar.bmp"), read("volume.bmp"), read("nums_ex.bmp") ?? read("numbers.bmp"), read("text.bmp"),
        ]))
    }

    // MARK: Measurements

    /// A dot grid when the display repeats a 2–3 px pattern (the two most common colours), else its solid colour.
    static func lcdMaterial(main: SkinBitmap) -> Style.Material {
        let box = timeBox
        let base = main.dominantColor(in: [(box.x..<(box.x + box.w), box.y..<(box.y + box.h))]) ?? .black
        for pitch in 2...3 {
            var matches = 0, total = 0
            for y in box.y..<(box.y + box.h - pitch) {
                for x in box.x..<(box.x + box.w - pitch) {
                    total += 1
                    if main.color(x: x, y: y) == main.color(x: x + pitch, y: y), main.color(x: x, y: y) == main.color(x: x, y: y + pitch) { matches += 1 }
                }
            }
            let colors = main.colors(in: box)
            var counts: [ThemeColor: Int] = [:]
            for color in colors { counts[color, default: 0] += 1 }
            let ranked = counts.sorted { $0.value > $1.value }
            guard total > 0, Double(matches) / Double(total) >= 0.9, ranked.count >= 2,
                  Double(ranked[1].value) >= Double(colors.count) * 0.08 else { continue }
            // The dot is the less common of the two; the grid's origin cell holds it.
            return .dotGrid(base: ranked[0].key, dot: ranked[1].key, pitch: Double(pitch), size: 1)
        }
        return .solid(base)
    }

    /// Segment when digit 8's ink forms three bars and two sides with nothing else inside; pixel when it doesn't.
    static func digits(numbers: SkinBitmap?) -> Style.Digits {
        guard let numbers, numbers.width >= 99, numbers.height >= 13 else { return .mono }
        let paper = Set(numbers.colors(in: Rect(x: 90, y: 0, w: 9, h: 13)))
        func lit(_ x: Int, _ y: Int) -> Bool { numbers.color(x: 72 + x, y: y).map { !paper.contains($0) } ?? false }
        let rowsLit = (0..<13).map { y in (0..<9).filter { lit($0, y) }.count }
        guard rowsLit.reduce(0, +) > 0 else { return .pixel }
        let bars = rowsLit.enumerated().filter { $0.element >= 4 }.map(\.offset)
        let barBands = Set(bars.map { $0 * 3 / 13 })                        // top, middle, bottom thirds
        let interior = (0..<13).filter { !bars.contains($0) }.reduce(0) { sum, y in sum + (2...6).filter { lit($0, y) }.count }
        return barBands.count == 3 && interior == 0 ? .segment : .pixel
    }

    /// The colour of the digits' lit segments (digit 8's most common non-paper colour).
    static func digitInk(numbers: SkinBitmap) -> ThemeColor? {
        let paper = Set(numbers.colors(in: Rect(x: 90, y: 0, w: 9, h: 13)))
        var counts: [ThemeColor: Int] = [:]
        for color in numbers.colors(in: Rect(x: 72, y: 0, w: 9, h: 13)) where !paper.contains(color) { counts[color, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// From the play sprite's silhouette: a circle clears most of its corners, a rounded button only the corner pixels.
    static func buttonShape(cbuttons: SkinBitmap) -> Style.ButtonShape {
        guard cbuttons.width >= 46, cbuttons.height >= 18, let face = cbuttons.color(x: 23 + 11, y: 9) else { return .rect }
        let paper = cbuttons.color(x: 23, y: 0)
        func isBackground(_ x: Int, _ y: Int) -> Bool {
            guard let p = cbuttons.color(x: 23 + x, y: y) else { return false }
            return p != face && p == paper
        }
        let corners = [(0, 0), (22, 0), (0, 17), (22, 17)]
        let cornerCleared = corners.filter { isBackground($0.0, $0.1) }.count
        let nearCornerCleared = [(2, 0), (20, 0), (2, 17), (20, 17), (0, 2), (22, 2), (0, 15), (22, 15)].filter { isBackground($0.0, $0.1) }.count
        if cornerCleared == 4 && nearCornerCleared >= 6 { return .circle }
        if cornerCleared == 4 && paper != face { return .rounded }
        return .rect
    }

    /// The volume fill's colours at the bottom, middle and top of the range (frames 0, 14, 27): each frame's most
    /// colourful pixel.
    static func volumeRamp(volume: SkinBitmap) -> [ThemeColor] {
        guard volume.width >= 68, volume.height >= 418 else { return [] }
        return [0, 14, 27].compactMap { frame in
            volume.colors(in: Rect(x: 0, y: frame * 15, w: 68, h: 13)).max { chroma($0) < chroma($1) }
        }
    }

    /// Flat when the surface barely varies; brushed when rows differ far more than neighbours along a row; else noise.
    static func surfaceMaterial(main: SkinBitmap) -> Style.Material {
        let box = surfaceBox
        let base = main.dominantColor(in: [(box.x..<(box.x + box.w), box.y..<(box.y + box.h))]) ?? .black
        var sum = 0.0, sumSq = 0.0, n = 0.0, along = 0.0, across = 0.0
        for y in box.y..<(box.y + box.h) {
            for x in box.x..<(box.x + box.w) {
                guard let p = main.color(x: x, y: y) else { continue }
                let l = p.luminanceValue
                sum += l; sumSq += l * l; n += 1
                if let right = main.color(x: x + 1, y: y) { along += abs(l - right.luminanceValue) }
                if let below = main.color(x: x, y: y + 1) { across += abs(l - below.luminanceValue) }
            }
        }
        guard n > 0 else { return .solid(base) }
        let deviation = max(0, sumSq / n - (sum / n) * (sum / n)).squareRoot() // rounding can dip below 0 on a flat area
        if deviation < 0.02 { return .solid(base) }
        if across > along * 3 {
            return .brushed(base: base, streak: base.lifted(0.12, lighter: base.lightness < 0.5), density: 0.4, seed: 7)
        }
        return .noise(base: base, amount: min(0.2, (deviation * 100).rounded() / 100), seed: 3)
    }

    static func chroma(_ c: ThemeColor) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }

    static func describe(_ m: Style.Material) -> String {
        switch m {
        case .solid(let c): "solid \(c.hex)"
        case .gradient: "gradient"
        case .dotGrid(let base, let dot, let pitch, _): "dotGrid \(base.hex)/\(dot.hex) every \(Int(pitch)) px"
        case .brushed(let base, _, _, _): "brushed \(base.hex)"
        case .noise(let base, let amount, _): "noise \(base.hex) ±\(amount)"
        case .pattern: "pattern"
        case .radial: "glow"
        case .image(let name, _, _, _): "image \(name)"
        case .layers(let l): "\(l.count) layers"
        }
    }

    // MARK: Contact sheet

    /// `main.bmp` at 2× with the sampled boxes outlined, then each sprite sheet at 2× below it.
    static func contactSheet(main: Data?, sprites: [Data?]) -> Data? {
        let images = ([main] + sprites).map { $0.flatMap { ThemeImage.cgImage($0) }.flatMap(RGBAImage.init) }
        guard let first = images.first ?? nil else { return nil }
        let scaled = images.compactMap { $0.map { nearest($0, factor: 2) } }
        let width = scaled.map(\.width).max() ?? 0, height = scaled.reduce(0) { $0 + $1.height + 8 }
        guard width > 0, width * height <= ThemeImage.maxPixels else { return nil }
        var sheet = RGBAImage(width: width, height: height, fill: 0x202020FF)
        var y = 0
        for (i, image) in scaled.enumerated() {
            var copy = image
            if i == 0, first.width >= 275 {
                for box in [timeBox, titleBox, surfaceBox, Rect(x: 0, y: 88, w: 275, h: 28)] { outline(&copy, box, factor: 2) }
            }
            sheet.paste(copy, x: 0, y: y)
            y += image.height + 8
        }
        return sheet.cgImage().flatMap(ThemeImage.png)
    }

    static func nearest(_ image: RGBAImage, factor: Int) -> RGBAImage {
        var out = RGBAImage(width: image.width * factor, height: image.height * factor, fill: 0)
        for y in 0..<out.height { for x in 0..<out.width { out.pixels[y * out.width + x] = image[x / factor, y / factor] } }
        return out
    }

    static func outline(_ image: inout RGBAImage, _ box: Rect, factor: Int) {
        let magenta: UInt32 = 0xFF00FFFF
        let x0 = box.x * factor, y0 = box.y * factor, x1 = min(image.width - 1, (box.x + box.w) * factor), y1 = min(image.height - 1, (box.y + box.h) * factor)
        guard x0 < x1, y0 < y1 else { return }
        for x in x0...x1 { image.pixels[y0 * image.width + x] = magenta; image.pixels[y1 * image.width + x] = magenta }
        for y in y0...y1 { image.pixels[y * image.width + x0] = magenta; image.pixels[y * image.width + x1] = magenta }
    }
}

extension ThemeColor {
    /// Relative luminance (0…1), for measuring texture.
    var luminanceValue: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}
