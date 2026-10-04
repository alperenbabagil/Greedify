import Foundation

/// A curated skin's recipe: the skin's look described in native drawing primitives (curated skins spec §2).
/// Every key is optional and read leniently: a bad value drops that element only. Tests decode built-in recipes
/// with `Style.$strict` set, which turns every drop (and every unknown key) into an error.
public struct Style: Equatable, Sendable {
    @TaskLocal public static var strict = false

    public enum Region: String, CaseIterable, Sendable { case window, sidebar, header, bar, popover, lyrics }
    public enum BevelRegion: String, CaseIterable, Sendable { case panel, bar }
    public enum TextRegion: String, CaseIterable, Sendable { case title, body, secondary, header, lyrics }

    public var materials: [Region: Material] = [:]
    public var bevels: [BevelRegion: Bevel] = [:]
    public var divider: ThemeColor?
    public var rows = RowStyles()
    public var lcd: LCDSpec?
    public var button: ButtonSpec?
    public var slider: SliderSpec?
    /// The volume slider; nil means it looks like `slider`.
    public var volume: SliderSpec?
    public var text: [TextRegion: TextSpec] = [:]
    public var bar: BarSpec?
    /// The song lists: today's cards or Winamp's playlist editor (winamp window spec).
    public var list: ListSpec?
    /// The page header: today's big cover or a slim strip.
    public var pageHeader: PageHeaderSpec?
    /// Winamp's panel frame around the sidebar, the page and the lyrics.
    public var frame: FrameSpec?

    public init() {}

    // MARK: Primitives

    public struct GradientStop: Codable, Equatable, Sendable {
        public var color: ThemeColor
        public var at: Double
        public init(color: ThemeColor, at: Double) { self.color = color; self.at = at }
    }

    /// What a surface is made of. `pitch`, `size` and `scale` are points; `angle` is degrees (90 = top to bottom).
    public enum Material: Equatable, Sendable {
        case solid(ThemeColor)
        case gradient(angle: Double, stops: [GradientStop])
        case dotGrid(base: ThemeColor, dot: ThemeColor, pitch: Double, size: Double)
        case brushed(base: ThemeColor, streak: ThemeColor, density: Double, seed: UInt64)
        case noise(base: ThemeColor, amount: Double, seed: UInt64)
        case pattern(width: Int, height: Int, scale: Double, colors: [ThemeColor])
        /// A glow from a point: `x`, `y` are fractions of the surface (may lie outside it), `radius` a fraction of its
        /// larger side. Colours may be translucent, so a glow can sit on another layer.
        case radial(x: Double, y: Double, radius: Double, stops: [GradientStop])
        /// A picture shipped with the recipe (a file next to it), filling the surface: cropped around the focus point
        /// (fractions of the picture), at `opacity`.
        case image(name: String, focusX: Double, focusY: Double, opacity: Double)
        /// Materials stacked bottom to top (a gradient, a glow, a translucent grain…); one level deep.
        indirect case layers([Material])

        /// The one colour that stands for this material when it can't be drawn (e.g. a tile fails).
        public var base: ThemeColor {
            switch self {
            case .solid(let c): c
            case .gradient(_, let stops): stops.first?.color ?? .black
            case .dotGrid(let base, _, _, _), .brushed(let base, _, _, _), .noise(let base, _, _): base
            case .pattern(_, _, _, let colors): colors.first ?? .black
            case .radial(_, _, _, let stops): stops.first?.color ?? .black
            case .layers(let layers): layers.first?.base ?? .black
            case .image: .black
            }
        }
    }

    public enum BevelKind: String, Codable, Sendable { case raised, sunken, double }

    public struct Bevel: Equatable, Sendable {
        public var kind: BevelKind
        public var light: ThemeColor
        public var dark: ThemeColor
        public var width: Double
        public init(kind: BevelKind, light: ThemeColor, dark: ThemeColor, width: Double) {
            self.kind = kind; self.light = light; self.dark = dark; self.width = width
        }
    }

    public enum FontChoice: Equatable, Sendable {
        /// The skin's `text.bmp` letterforms (`Theme.images.pixelFont`).
        case pixel
        case system
        case family(String)
    }

    public struct TextSpec: Equatable, Sendable {
        public var font: FontChoice?
        public var size: Double?
        public var weight: ThemeFontWeight?
        public var color: ThemeColor?
        /// Blur radius in points, drawn in the text colour.
        public var glow: Double?
        public init(font: FontChoice? = nil, size: Double? = nil, weight: ThemeFontWeight? = nil, color: ThemeColor? = nil, glow: Double? = nil) {
            self.font = font; self.size = size; self.weight = weight; self.color = color; self.glow = glow
        }
    }

    // MARK: Regions

    public struct RowStyle: Equatable, Sendable {
        public var fill: Material?
        public var text: ThemeColor?
        public var secondary: ThemeColor?
        public init(fill: Material? = nil, text: ThemeColor? = nil, secondary: ThemeColor? = nil) {
            self.fill = fill; self.text = text; self.secondary = secondary
        }
    }

    public struct RowStyles: Equatable, Sendable {
        public var normal, alternate, hover, selected, playing: RowStyle?
        public init() {}
    }

    public enum Digits: String, Codable, Sendable { case segment, pixel, mono }

    public struct LCDSpec: Equatable, Sendable {
        public var material: Material?
        public var bevel: Bevel?
        public var digits: Digits?
        public var text: ThemeColor?
        public var info: ThemeColor?
        public var glow: Double?
        /// Corner radius of every LCD panel (Classified's displays are rounded).
        public var radius: Double?
        public init() {}
    }

    public enum ButtonShape: String, Codable, Sendable { case rect, rounded, circle, pill }

    public struct PressedSpec: Equatable, Sendable {
        public var face: Material?
        public var glyph: ThemeColor?
        public init() {}
    }

    public struct ButtonSpec: Equatable, Sendable {
        public var shape: ButtonShape?
        public var radius: Double?
        public var face: Material?
        public var bevel: Bevel?
        public var glyph: ThemeColor?
        public var glyphWeight: ThemeFontWeight?
        public var pressed: PressedSpec?
        /// Glyph colour of a toggle that's on (shuffle, repeat, lyrics).
        public var active: ThemeColor?
        /// Buttons with a text label (Play, Shuffle, the sidebar button); nil uses `shape` (a circle becomes rounded).
        public var labelShape: ButtonShape?
        /// A dark line round the button and a light ring outside it (Classified's), in place of the bevel's edges.
        public var outline: ThemeColor?
        public var halo: ThemeColor?
        /// The gap between the transport's buttons; 0 is flush.
        public var spacing: Double?
        public init() {}
    }

    public struct GrooveSpec: Equatable, Sendable {
        public var material: Material?
        public var bevel: Bevel?
        public var height: Double?
        public init() {}
    }

    public enum FillKind: String, Codable, Sendable { case none, solid, ramp }

    public struct FillSpec: Equatable, Sendable {
        public var kind: FillKind
        public var colors: [ThemeColor]
        public init(kind: FillKind, colors: [ThemeColor]) { self.kind = kind; self.colors = colors }
    }

    public enum ThumbShape: String, Codable, Sendable { case rect, rounded, circle }

    public struct ThumbSpec: Equatable, Sendable {
        public var shape: ThumbShape?
        public var width: Double?
        public var height: Double?
        public var face: Material?
        public var bevel: Bevel?
        public init() {}
    }

    public struct SliderSpec: Equatable, Sendable {
        public var groove: GrooveSpec?
        public var fill: FillSpec?
        public var thumb: ThumbSpec?
        public init() {}
    }

    public enum BarLayout: String, Codable, Sendable { case winamp, classic }

    public enum TransportLayout: String, Codable, Sendable { case plain, winamp }

    public struct BarSpec: Equatable, Sendable {
        public var layout: BarLayout
        public var height: Double?
        public var artwork: Bool?
        /// The analyser's colours, top to bottom; nil means no analyser.
        public var analyser: [ThemeColor]?
        /// kbps / kHz / stereo in the LCD.
        public var readouts: Bool?
        /// `winamp`: the flush previous, play, pause, stop, next, eject row.
        public var transport: TransportLayout?
        /// The recessed channel the transport, the shuffle / repeat tab and the shelf sit in.
        public var transportWell: Material?
        public init(layout: BarLayout, height: Double? = nil, artwork: Bool? = nil, analyser: [ThemeColor]? = nil,
                    readouts: Bool? = nil, transport: TransportLayout? = nil, transportWell: Material? = nil) {
            self.layout = layout; self.height = height; self.artwork = artwork
            self.analyser = analyser; self.readouts = readouts; self.transport = transport
            self.transportWell = transportWell
        }
    }

    public enum ListLayout: String, Codable, Sendable { case cards, playlist }

    public struct ListSpec: Equatable, Sendable {
        public var layout: ListLayout
        public var rowHeight: Double?
        public var font: FontChoice?
        public var size: Double?
        public var scroller: ScrollerSpec?
        public init(layout: ListLayout = .cards, rowHeight: Double? = nil, font: FontChoice? = nil, size: Double? = nil,
                    scroller: ScrollerSpec? = nil) {
            self.layout = layout; self.rowHeight = rowHeight; self.font = font; self.size = size
            self.scroller = scroller
        }
    }

    public enum PageHeaderLayout: String, Codable, Sendable { case hero, strip }

    public struct PageHeaderSpec: Equatable, Sendable {
        public var layout: PageHeaderLayout
        /// The cover's size in a strip.
        public var artwork: Double?
        public init(layout: PageHeaderLayout = .hero, artwork: Double? = nil) { self.layout = layout; self.artwork = artwork }
    }

    /// The striped band at the top of a frame, with the panel's name (the app supplies it) after `prefix`.
    public struct TitleStripSpec: Equatable, Sendable {
        /// The stripes either side of the name.
        public var material: Material?
        public var height: Double?
        public var text: ThemeColor?
        public var prefix: String?
        /// The strip's own band behind stripes and name (Classified's dark steel); nil shows the frame's face.
        public var background: Material?
        /// One stripe this tall (a groove) instead of filling the band; `rounded` gives it round ends.
        public var stripeHeight: Double?
        public var rounded: Bool?
        /// The name's lettering; nil is the skin's pixel font.
        public var font: FontChoice?
        public var size: Double?
        public var weight: ThemeFontWeight?
        public init(material: Material? = nil, height: Double? = nil, text: ThemeColor? = nil, prefix: String? = nil,
                    background: Material? = nil, stripeHeight: Double? = nil, rounded: Bool? = nil,
                    font: FontChoice? = nil, size: Double? = nil, weight: ThemeFontWeight? = nil) {
            self.material = material; self.height = height; self.text = text; self.prefix = prefix
            self.background = background; self.stripeHeight = stripeHeight; self.rounded = rounded
            self.font = font; self.size = size; self.weight = weight
        }
    }

    public struct FrameSpec: Equatable, Sendable {
        public var face: Material?
        public var bevel: Bevel?
        public var thickness: Double?
        public var title: TitleStripSpec?
        /// The content's corner radius: set into the frame like a screen (Classified).
        public var radius: Double?
        /// A dark line round the content.
        public var outline: ThemeColor?
        public init(face: Material? = nil, bevel: Bevel? = nil, thickness: Double? = nil, title: TitleStripSpec? = nil,
                    radius: Double? = nil, outline: ThemeColor? = nil) {
            self.face = face; self.bevel = bevel; self.thickness = thickness; self.title = title
            self.radius = radius; self.outline = outline
        }
    }

    /// A skinned scroller for the song lists: track and thumb materials, the thumb's bevel, the width.
    public struct ScrollerSpec: Equatable, Sendable {
        public var track: Material?
        public var thumb: Material?
        public var bevel: Bevel?
        public var width: Double?
        public init(track: Material? = nil, thumb: Material? = nil, bevel: Bevel? = nil, width: Double? = nil) {
            self.track = track; self.thumb = thumb; self.bevel = bevel; self.width = width
        }
    }
}

// MARK: - Coding

extension ThemeColor: Codable {
    public init(from decoder: Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let color = ThemeColor(hex: hex) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a colour: \(hex)"))
        }
        self = color
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

/// Lenient keyed reading shared by the recipe types; strict mode rethrows instead of dropping.
struct RecipeReader {
    let c: KeyedDecodingContainer<AnyKey>
    let path: [CodingKey]

    init(_ decoder: Decoder, known: [String]) throws {
        c = try decoder.container(keyedBy: AnyKey.self)
        path = decoder.codingPath
        if Style.strict {
            let unknown = c.allKeys.map(\.stringValue).filter { !known.contains($0) }
            if !unknown.isEmpty { throw Self.error(path, "unknown keys \(unknown.sorted())") }
        }
    }

    static func error(_ path: [CodingKey], _ message: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: path, debugDescription: message))
    }

    /// The value at `key`, or nil when it's absent or (lenient mode) invalid.
    func optional<T: Decodable>(_ key: String, _ type: T.Type = T.self) throws -> T? {
        guard c.contains(AnyKey(key)) else { return nil }
        do { return try c.decode(T.self, forKey: AnyKey(key)) } catch {
            if Style.strict { throw error }
            return nil
        }
    }

    /// A value the enclosing element can't do without: its absence or invalidity drops the whole element.
    func required<T: Decodable>(_ key: String, _ type: T.Type = T.self) throws -> T {
        try c.decode(T.self, forKey: AnyKey(key))
    }

    /// A keyed group like `materials` or `text`: unknown names and bad entries drop alone.
    func group<K: RawRepresentable & Hashable, V: Decodable>(_ key: String, _ keys: K.Type, _ value: V.Type) throws -> [K: V]
        where K.RawValue == String {
        guard c.contains(AnyKey(key)) else { return [:] }
        let nested = try c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key))
        var out: [K: V] = [:]
        for name in nested.allKeys {
            guard let k = K(rawValue: name.stringValue) else {
                if Style.strict { throw Self.error(path, "unknown \(key) entry \(name.stringValue)") }
                continue
            }
            do { out[k] = try nested.decode(V.self, forKey: name) } catch { if Style.strict { throw error } }
        }
        return out
    }
}

struct RecipeWriter {
    var c: KeyedEncodingContainer<AnyKey>
    init(_ encoder: Encoder) { c = encoder.container(keyedBy: AnyKey.self) }
    mutating func put<T: Encodable>(_ key: String, _ value: T?) throws {
        if let value { try c.encode(value, forKey: AnyKey(key)) }
    }
    mutating func group<K: RawRepresentable, V: Encodable>(_ key: String, _ values: [K: V]) throws where K.RawValue == String {
        guard !values.isEmpty else { return }
        var nested = c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key))
        for (k, v) in values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) { try nested.encode(v, forKey: AnyKey(k.rawValue)) }
    }
}

extension Style: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["materials", "bevels", "divider", "rows", "lcd", "button", "slider", "volume", "text", "bar", "list", "pageHeader", "frame"])
        materials = try r.group("materials", Region.self, Material.self)
        bevels = try r.group("bevels", BevelRegion.self, Bevel.self)
        divider = try r.optional("divider")
        rows = try r.optional("rows") ?? RowStyles()
        lcd = try r.optional("lcd")
        button = try r.optional("button")
        slider = try r.optional("slider")
        volume = try r.optional("volume")
        text = try r.group("text", TextRegion.self, TextSpec.self)
        bar = try r.optional("bar")
        list = try r.optional("list")
        pageHeader = try r.optional("pageHeader")
        frame = try r.optional("frame")
    }

    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.group("materials", materials); try w.group("bevels", bevels); try w.put("divider", divider)
        if rows != RowStyles() { try w.put("rows", rows) }
        try w.put("lcd", lcd); try w.put("button", button); try w.put("slider", slider); try w.put("volume", volume)
        try w.group("text", text); try w.put("bar", bar)
        try w.put("list", list); try w.put("pageHeader", pageHeader); try w.put("frame", frame)
    }
}

extension Style.Material: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let kind = try c.decode(String.self, forKey: AnyKey("kind"))
        let known: [String]
        switch kind {
        case "solid": known = ["kind", "color"]
        case "gradient": known = ["kind", "angle", "stops"]
        case "dotGrid": known = ["kind", "base", "dot", "pitch", "size"]
        case "brushed": known = ["kind", "base", "streak", "density", "seed"]
        case "noise": known = ["kind", "base", "amount", "seed"]
        case "pattern": known = ["kind", "width", "height", "scale", "colors"]
        case "radial": known = ["kind", "x", "y", "radius", "stops"]
        case "layers": known = ["kind", "layers"]
        case "image": known = ["kind", "name", "focusX", "focusY", "opacity"]
        default: throw RecipeReader.error(decoder.codingPath, "unknown material kind \(kind)")
        }
        let r = try RecipeReader(decoder, known: known)
        switch kind {
        case "solid": self = .solid(try r.required("color"))
        case "gradient":
            let stops: [Style.GradientStop] = try r.required("stops")
            guard !stops.isEmpty else { throw RecipeReader.error(decoder.codingPath, "a gradient needs stops") }
            self = .gradient(angle: try r.optional("angle") ?? 90, stops: stops)
        case "dotGrid":
            self = .dotGrid(base: try r.required("base"), dot: try r.required("dot"),
                            pitch: max(1, try r.optional("pitch") ?? 2), size: max(0.5, try r.optional("size") ?? 1))
        case "brushed":
            self = .brushed(base: try r.required("base"), streak: try r.required("streak"),
                            density: min(max(try r.optional("density") ?? 0.3, 0), 1), seed: try r.optional("seed") ?? 1)
        case "noise":
            self = .noise(base: try r.required("base"), amount: min(max(try r.optional("amount") ?? 0.05, 0), 1), seed: try r.optional("seed") ?? 1)
        case "radial":
            let stops: [Style.GradientStop] = try r.required("stops")
            guard !stops.isEmpty else { throw RecipeReader.error(decoder.codingPath, "a glow needs stops") }
            self = .radial(x: try r.optional("x") ?? 0.5, y: try r.optional("y") ?? 0.5,
                           radius: max(0.05, try r.optional("radius") ?? 0.7), stops: stops)
        case "image":
            let name: String = try r.required("name")
            guard Theme.isSafeImageName(name) else { throw RecipeReader.error(decoder.codingPath, "an image is a plain file name: \(name)") }
            self = .image(name: name, focusX: min(max(try r.optional("focusX") ?? 0.5, 0), 1), focusY: min(max(try r.optional("focusY") ?? 0.5, 0), 1),
                          opacity: min(max(try r.optional("opacity") ?? 1, 0), 1))
        case "layers":
            let layers: [Style.Material] = try r.required("layers")
            guard !layers.isEmpty, !layers.contains(where: { if case .layers = $0 { true } else { false } }) else {
                throw RecipeReader.error(decoder.codingPath, "layers need at least one material, and don't nest")
            }
            self = .layers(layers)
        default:
            let width: Int = try r.required("width"), height: Int = try r.required("height")
            let colors: [ThemeColor] = try r.required("colors")
            guard (1...16).contains(width), (1...16).contains(height), colors.count == width * height else {
                throw RecipeReader.error(decoder.codingPath, "a pattern needs width × height colours (1…16 each side)")
            }
            self = .pattern(width: width, height: height, scale: max(0.5, try r.optional("scale") ?? 1), colors: colors)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        switch self {
        case .solid(let color): try w.put("kind", "solid"); try w.put("color", color)
        case .gradient(let angle, let stops): try w.put("kind", "gradient"); try w.put("angle", angle); try w.put("stops", stops)
        case .dotGrid(let base, let dot, let pitch, let size):
            try w.put("kind", "dotGrid"); try w.put("base", base); try w.put("dot", dot); try w.put("pitch", pitch); try w.put("size", size)
        case .brushed(let base, let streak, let density, let seed):
            try w.put("kind", "brushed"); try w.put("base", base); try w.put("streak", streak); try w.put("density", density); try w.put("seed", seed)
        case .noise(let base, let amount, let seed):
            try w.put("kind", "noise"); try w.put("base", base); try w.put("amount", amount); try w.put("seed", seed)
        case .pattern(let width, let height, let scale, let colors):
            try w.put("kind", "pattern"); try w.put("width", width); try w.put("height", height); try w.put("scale", scale); try w.put("colors", colors)
        case .radial(let x, let y, let radius, let stops):
            try w.put("kind", "radial"); try w.put("x", x); try w.put("y", y); try w.put("radius", radius); try w.put("stops", stops)
        case .layers(let layers):
            try w.put("kind", "layers"); try w.put("layers", layers)
        case .image(let name, let focusX, let focusY, let opacity):
            try w.put("kind", "image"); try w.put("name", name); try w.put("focusX", focusX); try w.put("focusY", focusY); try w.put("opacity", opacity)
        }
    }
}

extension Style.Bevel: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["style", "light", "dark", "width"])
        self.init(kind: try r.optional("style") ?? .raised, light: try r.required("light"), dark: try r.required("dark"),
                  width: min(max(try r.optional("width") ?? 1, 0.5), 4))
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("style", kind); try w.put("light", light); try w.put("dark", dark); try w.put("width", width)
    }
}

extension Style.FontChoice: Codable {
    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self).trimmingCharacters(in: .whitespaces)
        switch name {
        case "pixel": self = .pixel
        case "system": self = .system
        case "": throw RecipeReader.error(decoder.codingPath, "empty font name")
        default: self = .family(name)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .pixel: try c.encode("pixel")
        case .system: try c.encode("system")
        case .family(let name): try c.encode(name)
        }
    }
}

extension Style.TextSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["font", "size", "weight", "color", "glow"])
        self.init(font: try r.optional("font"), size: try r.optional("size"), weight: try r.optional("weight"),
                  color: try r.optional("color"), glow: try r.optional("glow"))
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("font", font); try w.put("size", size); try w.put("weight", weight); try w.put("color", color); try w.put("glow", glow)
    }
}

extension Style.RowStyle: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["fill", "text", "secondary"])
        self.init(fill: try r.optional("fill"), text: try r.optional("text"), secondary: try r.optional("secondary"))
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("fill", fill); try w.put("text", text); try w.put("secondary", secondary)
    }
}

extension Style.RowStyles: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["normal", "alternate", "hover", "selected", "playing"])
        normal = try r.optional("normal"); alternate = try r.optional("alternate"); hover = try r.optional("hover")
        selected = try r.optional("selected"); playing = try r.optional("playing")
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("normal", normal); try w.put("alternate", alternate); try w.put("hover", hover)
        try w.put("selected", selected); try w.put("playing", playing)
    }
}

extension Style.LCDSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["material", "bevel", "digits", "text", "info", "glow", "radius"])
        material = try r.optional("material"); bevel = try r.optional("bevel"); digits = try r.optional("digits")
        text = try r.optional("text"); info = try r.optional("info"); glow = try r.optional("glow")
        radius = try r.optional("radius").map { min(max($0, 0), 20) }
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("material", material); try w.put("bevel", bevel); try w.put("digits", digits)
        try w.put("text", text); try w.put("info", info); try w.put("glow", glow); try w.put("radius", radius)
    }
}

extension Style.PressedSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["face", "glyph"])
        face = try r.optional("face"); glyph = try r.optional("glyph")
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("face", face); try w.put("glyph", glyph)
    }
}

extension Style.ButtonSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["shape", "radius", "face", "bevel", "glyph", "glyphWeight", "pressed", "active", "labelShape", "outline", "halo", "spacing"])
        shape = try r.optional("shape"); radius = try r.optional("radius"); face = try r.optional("face"); bevel = try r.optional("bevel")
        glyph = try r.optional("glyph"); glyphWeight = try r.optional("glyphWeight"); pressed = try r.optional("pressed"); active = try r.optional("active")
        labelShape = try r.optional("labelShape")
        outline = try r.optional("outline"); halo = try r.optional("halo"); spacing = try r.optional("spacing").map { min(max($0, 0), 20) }
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("shape", shape); try w.put("radius", radius); try w.put("face", face); try w.put("bevel", bevel)
        try w.put("glyph", glyph); try w.put("glyphWeight", glyphWeight); try w.put("pressed", pressed); try w.put("active", active)
        try w.put("labelShape", labelShape); try w.put("outline", outline); try w.put("halo", halo); try w.put("spacing", spacing)
    }
}

extension Style.GrooveSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["material", "bevel", "height"])
        material = try r.optional("material"); bevel = try r.optional("bevel"); height = try r.optional("height")
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("material", material); try w.put("bevel", bevel); try w.put("height", height)
    }
}

extension Style.FillSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["kind", "colors"])
        self.init(kind: try r.required("kind"), colors: try r.optional("colors") ?? [])
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("kind", kind); try w.put("colors", colors)
    }
}

extension Style.ThumbSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["shape", "width", "height", "face", "bevel"])
        shape = try r.optional("shape"); width = try r.optional("width"); height = try r.optional("height")
        face = try r.optional("face"); bevel = try r.optional("bevel")
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("shape", shape); try w.put("width", width); try w.put("height", height); try w.put("face", face); try w.put("bevel", bevel)
    }
}

extension Style.SliderSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["groove", "fill", "thumb"])
        groove = try r.optional("groove"); fill = try r.optional("fill"); thumb = try r.optional("thumb")
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("groove", groove); try w.put("fill", fill); try w.put("thumb", thumb)
    }
}

extension Style.BarSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["layout", "height", "artwork", "analyser", "readouts", "transport", "transportWell"])
        self.init(layout: try r.optional("layout") ?? .classic, height: try r.optional("height"), artwork: try r.optional("artwork"),
                  analyser: try r.optional("analyser"), readouts: try r.optional("readouts"), transport: try r.optional("transport"),
                  transportWell: try r.optional("transportWell"))
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("layout", layout); try w.put("height", height); try w.put("artwork", artwork)
        try w.put("analyser", analyser); try w.put("readouts", readouts); try w.put("transport", transport)
        try w.put("transportWell", transportWell)
    }
}

extension Style.ListSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["layout", "rowHeight", "font", "size", "scroller"])
        self.init(layout: try r.optional("layout") ?? .cards, rowHeight: try r.optional("rowHeight").map { min(max($0, 14), 60) },
                  font: try r.optional("font"), size: try r.optional("size"), scroller: try r.optional("scroller"))
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("layout", layout); try w.put("rowHeight", rowHeight); try w.put("font", font); try w.put("size", size)
        try w.put("scroller", scroller)
    }
}

extension Style.PageHeaderSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["layout", "artwork"])
        self.init(layout: try r.optional("layout") ?? .hero, artwork: try r.optional("artwork").map { min(max($0, 0), 200) })
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("layout", layout); try w.put("artwork", artwork)
    }
}

extension Style.TitleStripSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["material", "height", "text", "prefix", "background", "stripeHeight", "rounded",
                                                  "font", "size", "weight"])
        self.init(material: try r.optional("material"), height: try r.optional("height").map { min(max($0, 8), 30) },
                  text: try r.optional("text"), prefix: try r.optional("prefix"), background: try r.optional("background"),
                  stripeHeight: try r.optional("stripeHeight").map { min(max($0, 1), 30) }, rounded: try r.optional("rounded"),
                  font: try r.optional("font"), size: try r.optional("size").map { min(max($0, 6), 30) }, weight: try r.optional("weight"))
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("material", material); try w.put("height", height); try w.put("text", text); try w.put("prefix", prefix)
        try w.put("background", background); try w.put("stripeHeight", stripeHeight); try w.put("rounded", rounded)
        try w.put("font", font); try w.put("size", size); try w.put("weight", weight)
    }
}

extension Style.FrameSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["face", "bevel", "thickness", "title", "radius", "outline"])
        self.init(face: try r.optional("face"), bevel: try r.optional("bevel"), thickness: try r.optional("thickness").map { min(max($0, 0), 12) },
                  title: try r.optional("title"), radius: try r.optional("radius").map { min(max($0, 0), 20) },
                  outline: try r.optional("outline"))
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("face", face); try w.put("bevel", bevel); try w.put("thickness", thickness); try w.put("title", title)
        try w.put("radius", radius); try w.put("outline", outline)
    }
}

extension Style.ScrollerSpec: Codable {
    public init(from decoder: Decoder) throws {
        let r = try RecipeReader(decoder, known: ["track", "thumb", "bevel", "width"])
        self.init(track: try r.optional("track"), thumb: try r.optional("thumb"), bevel: try r.optional("bevel"),
                  width: try r.optional("width").map { min(max($0, 6), 24) })
    }
    public func encode(to encoder: Encoder) throws {
        var w = RecipeWriter(encoder)
        try w.put("track", track); try w.put("thumb", thumb); try w.put("bevel", bevel); try w.put("width", width)
    }
}

extension Theme {
    /// A recipe image's file name: no folders, no hidden files, a picture extension.
    static func isSafeImageName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".") && name.count <= 128
            && ["jpg", "jpeg", "png", "heic", "webp"].contains(ext)
    }

    /// Where a recipe's image lives: next to the built-in recipes, else (dev recipes, Debug) in the Recipes folder.
    public static func recipeImageURL(_ name: String) -> URL? {
        guard isSafeImageName(name) else { return nil }
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        if let url = Bundle.module.url(forResource: stem, withExtension: ext) { return url }
        let dev = GreedifyPaths.recipes.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}
