import Foundation

/// An sRGB color with alpha, components 0...1. Themes store colors as `#RRGGBB` or `#RRGGBBAA`.
public struct ThemeColor: Hashable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public static let white = ThemeColor(r: 1, g: 1, b: 1)
    public static let black = ThemeColor(r: 0, g: 0, b: 0)

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        func unit(_ v: Double) -> Double { min(max(v, 0), 1) }
        self.r = unit(r); self.g = unit(g); self.b = unit(b); self.a = unit(a)
    }

    public init(r8: Int, g8: Int, b8: Int) {
        self.init(r: Double(r8) / 255, g: Double(g8) / 255, b: Double(b8) / 255)
    }

    /// `#RRGGBB` or `#RRGGBBAA`, `#` optional, any case, surrounding spaces ignored.
    public init?(hex: String) {
        var s = Substring(hex.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6 || s.count == 8, s.allSatisfy(\.isHexDigit), let v = UInt64(s, radix: 16) else { return nil }
        func byte(_ shift: UInt64) -> Double { Double((v >> shift) & 0xFF) / 255 }
        if s.count == 6 { self.init(r: byte(16), g: byte(8), b: byte(0)) }
        else { self.init(r: byte(24), g: byte(16), b: byte(8), a: byte(0)) }
    }

    public var hex: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        return byte(a) == 255 ? rgb : rgb + String(format: "%02X", byte(a))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio, 1...21.
    public func contrast(with other: ThemeColor) -> Double {
        let (hi, lo) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Moves `amount` (0...1) of the way toward `other`; alpha is kept.
    public func blended(toward other: ThemeColor, _ amount: Double) -> ThemeColor {
        ThemeColor(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount, a: a)
    }

    public func withAlpha(_ alpha: Double) -> ThemeColor { ThemeColor(r: r, g: g, b: b, a: alpha) }

    /// HSL lightness, 0...1.
    public var lightness: Double { (max(r, g, b) + min(r, g, b)) / 2 }

    /// HSL saturation, 0...1.
    public var saturation: Double {
        let hi = max(r, g, b), lo = min(r, g, b)
        guard hi != lo else { return 0 }
        return (hi - lo) / (1 - abs(2 * lightness - 1))
    }

    /// HSL hue in degrees, 0..<360 (0 for greys).
    public var hue: Double {
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        guard d > 0 else { return 0 }
        let h: Double = if hi == r { ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if hi == g { (b - r) / d + 2 }
            else { (r - g) / d + 4 }
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    public init(hue: Double, saturation s: Double, lightness l: Double, a: Double = 1) {
        let c = (1 - abs(2 * l - 1)) * s
        let h = hue / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) = switch h {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        self.init(r: r1 + m, g: g1 + m, b: b1 + m, a: a)
    }

    /// Moves `amount` (0...1) of the remaining HSL lightness toward white (`lighter`) or black, keeping hue
    /// and saturation (theme images spec §5). 0 returns the color unchanged.
    public func lifted(_ amount: Double, lighter: Bool) -> ThemeColor {
        guard amount > 0 else { return self }
        let l = lightness
        return ThemeColor(hue: hue, saturation: saturation, lightness: lighter ? l + amount * (1 - l) : l - amount * l, a: a)
    }
}

extension ThemeColor {
    /// This colour pushed toward white or black until it reaches `ratio` on every one of `backgrounds`
    /// (unchanged when it already does). Used for text over a skin's flat panel.
    public func ensuringContrast(on backgrounds: [ThemeColor], _ ratio: Double) -> ThemeColor {
        SkinThemeMapper.ensureContrast(self, on: backgrounds, ratio)
    }
}
