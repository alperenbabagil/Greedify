import Foundation
import Testing
@testable import GreedifyKit

struct PixelScalerTests {
    let K: UInt32 = 0xFF0000FF, P: UInt32 = 0x00FF00FF, Q: UInt32 = 0x0000FFFF, Z: UInt32 = 0x777777FF

    @Test func flatStaysFlatAtTwiceTheSize() {
        let out = PixelScaler.scale2x(RGBAImage(width: 3, height: 2, fill: P))
        #expect(out.width == 6 && out.height == 4)
        #expect(out.pixels.allSatisfy { $0 == P })
    }

    /// Scale2x: E0 = A when C == A, C != D, A != B (A above, B right, C left, D below); E3 likewise toward D.
    @Test func cornersFollowMatchingNeighbours() {
        let image = RGBAImage(width: 3, height: 3, pixels: [Z, K, Z,
                                                           K, P, Q,
                                                           Z, Q, Z])
        let out = PixelScaler.scale2x(image)
        #expect(out[2, 2] == K)   // top-left of the centre: up and left agree
        #expect(out[3, 2] == P)
        #expect(out[2, 3] == P)
        #expect(out[3, 3] == Q)   // bottom-right: right and down agree
    }

    @Test func aLonePixelStaysABlock() {
        let image = RGBAImage(width: 3, height: 3, pixels: [Z, Z, Z, Z, P, Z, Z, Z, Z])
        let out = PixelScaler.scale2x(image)
        #expect([out[2, 2], out[3, 2], out[2, 3], out[3, 3]] == [P, P, P, P])
    }

    @Test func scale4xIsScale2xTwice() {
        let image = RGBAImage(width: 3, height: 3, pixels: [Z, K, Z, K, P, Q, Z, Q, Z])
        let out = PixelScaler.scale4x(image)
        #expect(out == PixelScaler.scale2x(PixelScaler.scale2x(image)))
        #expect(out.width == 12 && out.height == 12)
    }

    @Test func cropPasteAndCGImageRoundTrip() throws {
        var canvas = RGBAImage(width: 4, height: 3, fill: Z)
        canvas.paste(RGBAImage(width: 2, height: 1, fill: K), x: 1, y: 2)
        #expect(canvas[1, 2] == K && canvas[3, 2] == Z && canvas[1, 1] == Z)
        #expect(canvas.crop(x: 1, y: 2, width: 2, height: 1) == RGBAImage(width: 2, height: 1, fill: K))
        #expect(canvas.crop(x: 3, y: 0, width: 2, height: 1) == nil)      // runs off the right edge
        let back = try #require(canvas.cgImage().flatMap(RGBAImage.init))
        #expect(back == canvas)
    }
}
