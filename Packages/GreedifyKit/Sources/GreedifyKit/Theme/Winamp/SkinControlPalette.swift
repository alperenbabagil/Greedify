import Foundation

/// A skin's button colours, sampled from its sprites (skinned controls spec §3.2).
enum SkinControlPalette {
    struct Rect { let x, y, w, h: Int }
    static let play = Rect(x: 23, y: 0, w: 23, h: 18)
    static let playPressed = Rect(x: 23, y: 18, w: 23, h: 18)
    static let shuffleOn = Rect(x: 28, y: 30, w: 47, h: 15)
    static let controlArea = Rect(x: 0, y: 88, w: 275, h: 28)
    static let minGlyphContrast = 3.0

    static func make(cbuttons: SkinBitmap?, shufrep: SkinBitmap?, main: SkinBitmap?) -> Theme.Controls? {
        var c = Theme.Controls()
        if let cb = cbuttons, cb.width >= 136, cb.height >= 36 {
            if let n = button(cb, play) {
                c.faceTop = n.faceTop; c.faceBottom = n.faceBottom; c.highlight = n.highlight; c.shadow = n.shadow; c.glyph = n.glyph
            }
            if let p = button(cb, playPressed) {
                c.pressedFaceTop = p.faceTop; c.pressedFaceBottom = p.faceBottom; c.pressedGlyph = p.glyph
            }
        }
        if let s = shufrep, s.width >= 92, s.height >= 85 {
            c.on = s.colors(in: shuffleOn).max { chroma($0) < chroma($1) }
        }
        if let m = main, m.width >= 275, m.height >= 116 {
            let a = controlArea
            c.panel = m.dominantColor(in: [(a.x..<(a.x + a.w), a.y..<(a.y + a.h))])
        }
        return c.isUsable ? c : nil
    }

    struct ButtonColors { let faceTop, faceBottom, highlight, shadow: ThemeColor; let glyph: ThemeColor? }
    /// Squared RGB distance from its row's face beyond which a pixel counts as glyph (about 0.08 per channel).
    static let glyphDistance = 0.02

    /// Face from the medians of the rows at 25 % and 75 % (inset 2 px: the glyph is a minority of any row), bevel
    /// from the edges (corners left out), glyph from the pixels clearly unlike their own row's face.
    static func button(_ b: SkinBitmap, _ r: Rect) -> ButtonColors? {
        let inner = Rect(x: r.x + 2, y: r.y + 2, w: r.w - 4, h: r.h - 4)
        guard inner.w > 0, inner.h > 0 else { return nil }
        func row(_ y: Int) -> [ThemeColor] { b.colors(in: Rect(x: inner.x, y: y, w: inner.w, h: 1)) }
        guard let top = median(row(r.y + Int(Double(r.h) * 0.25))),
              let bottom = median(row(r.y + Int(Double(r.h) * 0.75))) else { return nil }
        let highlight = median(b.colors(in: Rect(x: r.x + 1, y: r.y, w: r.w - 2, h: 1))
                               + b.colors(in: Rect(x: r.x, y: r.y + 1, w: 1, h: r.h - 2))) ?? top
        let shadow = median(b.colors(in: Rect(x: r.x + 1, y: r.y + r.h - 1, w: r.w - 2, h: 1))
                            + b.colors(in: Rect(x: r.x + r.w - 1, y: r.y + 1, w: 1, h: r.h - 2))) ?? bottom
        var ink: [ThemeColor] = []
        for y in inner.y..<(inner.y + inner.h) {
            let pixels = row(y)
            guard let face = median(pixels) else { continue }
            ink += pixels.filter { distance($0, face) > glyphDistance }
        }
        var glyph = median(ink)
        if let g = glyph, g.contrast(with: top.blended(toward: bottom, 0.5)) < minGlyphContrast { glyph = nil }
        return ButtonColors(faceTop: top, faceBottom: bottom, highlight: highlight, shadow: shadow, glyph: glyph)
    }

    static func distance(_ p: ThemeColor, _ q: ThemeColor) -> Double {
        (p.r - q.r) * (p.r - q.r) + (p.g - q.g) * (p.g - q.g) + (p.b - q.b) * (p.b - q.b)
    }

    /// Per-channel median: a stray pixel can't tint it the way it would a mean.
    static func median(_ colors: [ThemeColor]) -> ThemeColor? {
        guard !colors.isEmpty else { return nil }
        func mid(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        return ThemeColor(r: mid(colors.map(\.r)), g: mid(colors.map(\.g)), b: mid(colors.map(\.b)))
    }

    /// Saturation × brightness in HSV terms: the lit indicator stands out on either.
    static func chroma(_ c: ThemeColor) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
}
