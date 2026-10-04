import Foundation
@testable import GreedifyKit

/// PNG test images, built from BMPBuilder and re-encoded through the package's own ImageIO path.
enum PNGFixture {
    static func make(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        ThemeImage.png(fromImageData: BMPBuilder.make(width: width, height: height, pixel: pixel))!
    }
}
