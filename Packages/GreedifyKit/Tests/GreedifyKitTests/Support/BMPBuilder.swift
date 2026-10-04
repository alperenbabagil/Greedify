import Foundation

/// Builds uncompressed 24-bit BMPs for tests. `pixel(x, y)` returns (r, g, b), with y = 0 at the top.
enum BMPBuilder {
    static func make(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        let rowSize = (width * 3 + 3) & ~3
        let imageSize = rowSize * height
        var d = Data([0x42, 0x4D])
        d.appendLE32(UInt32(54 + imageSize)); d.appendLE32(0); d.appendLE32(54)
        d.appendLE32(40); d.appendLE32(UInt32(width)); d.appendLE32(UInt32(height))
        d.appendLE16(1); d.appendLE16(24); d.appendLE32(0); d.appendLE32(UInt32(imageSize))
        d.appendLE32(2835); d.appendLE32(2835); d.appendLE32(0); d.appendLE32(0)
        for y in (0..<height).reversed() { // BMP rows are stored bottom-up
            for x in 0..<width {
                let (r, g, b) = pixel(x, y)
                d.append(contentsOf: [b, g, r])
            }
            d.append(Data(count: rowSize - width * 3))
        }
        return d
    }
}
