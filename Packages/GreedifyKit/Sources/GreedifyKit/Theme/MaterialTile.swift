import CoreGraphics
import Foundation

/// The repeating tile behind a textured material (curated skins spec §3): a dotted LCD, a pixel pattern, stone
/// noise or brushed metal, built in code at the display scale and at most 64 px a side. Flat materials (solid,
/// gradient) are drawn natively and have no tile.
public enum MaterialTile {
    public static let maxSide = 64
    /// Noise and brushed tiles: large enough that the repeat doesn't show at a glance.
    public static let textureSide = 64

    public static func make(_ material: Style.Material, scale: CGFloat) -> CGImage? {
        let s = max(1, Double(scale))
        switch material {
        case .solid, .gradient, .radial, .layers, .image:
            return nil
        case .dotGrid(let base, let dot, let pitch, let size):
            let side = max(1, Int((pitch * s).rounded())), dotSide = max(1, min(side, Int((size * s).rounded())))
            guard side <= maxSide else { return nil }
            var tile = RGBAImage(width: side, height: side, fill: pixel(base))
            tile.paste(RGBAImage(width: dotSide, height: dotSide, fill: pixel(dot)), x: 0, y: 0)
            return tile.cgImage()
        case .pattern(let width, let height, let cellScale, let colors):
            let cell = max(1, Int((cellScale * s).rounded()))
            guard width * cell <= maxSide, height * cell <= maxSide, colors.count == width * height else { return nil }
            var tile = RGBAImage(width: width * cell, height: height * cell, fill: 0)
            for y in 0..<height {
                for x in 0..<width { tile.paste(RGBAImage(width: cell, height: cell, fill: pixel(colors[y * width + x])), x: x * cell, y: y * cell) }
            }
            return tile.cgImage()
        case .noise(let base, let amount, let seed):
            var rng = SplitMix64(seed: seed)
            var tile = RGBAImage(width: textureSide, height: textureSide, fill: 0)
            for i in tile.pixels.indices { tile.pixels[i] = pixel(base, brightness: (rng.unit() * 2 - 1) * amount) }
            return tile.cgImage()
        case .brushed(let base, let streak, let density, let seed):
            // Horizontal streaks: some rows lean toward the streak colour, each pixel varies a little along the row.
            var rng = SplitMix64(seed: seed)
            var tile = RGBAImage(width: textureSide, height: textureSide, fill: 0)
            for y in 0..<textureSide {
                let rowColor = rng.unit() < density ? base.blended(toward: streak, 0.4 + 0.6 * rng.unit()) : base
                for x in 0..<textureSide { tile.pixels[y * textureSide + x] = pixel(rowColor, brightness: (rng.unit() * 2 - 1) * 0.02) }
            }
            return tile.cgImage()
        }
    }

    static func pixel(_ c: ThemeColor, brightness: Double = 0) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v + brightness, 0), 1) * 255).rounded()) }
        return byte(c.r) << 24 | byte(c.g) << 16 | byte(c.b) << 8 | UInt32((min(max(c.a, 0), 1) * 255).rounded())
    }
}

/// A small, seedable generator, so a noise or brushed tile is the same on every launch.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// 0 ..< 1
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
