import Foundation

/// Edge-aware pixel-art upscaling for skin sprites (skinned controls spec §4). Scale2x (EPX / AdvMAME2x) follows
/// matching neighbours into each corner, so diagonals and curves come out stepped-smooth and nothing is blurred.
public enum PixelScaler {
    public static func scale2x(_ src: RGBAImage) -> RGBAImage {
        let w = src.width, h = src.height
        var out = [UInt32](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p = src[x, y]
                let a = y > 0 ? src[x, y - 1] : p       // above
                let b = x < w - 1 ? src[x + 1, y] : p   // right
                let c = x > 0 ? src[x - 1, y] : p       // left
                let d = y < h - 1 ? src[x, y + 1] : p   // below
                let o = 2 * y * 2 * w + 2 * x
                out[o] = c == a && c != d && a != b ? a : p
                out[o + 1] = a == b && a != c && b != d ? b : p
                out[o + 2 * w] = d == c && d != b && c != a ? c : p
                out[o + 2 * w + 1] = b == d && b != a && d != c ? d : p
            }
        }
        return RGBAImage(width: 2 * w, height: 2 * h, pixels: out)
    }

    public static func scale4x(_ src: RGBAImage) -> RGBAImage { scale2x(scale2x(src)) }
}
