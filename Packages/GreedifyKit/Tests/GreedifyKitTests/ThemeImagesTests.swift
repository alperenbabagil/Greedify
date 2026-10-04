import CoreGraphics
import Foundation
import Testing
@testable import GreedifyKit

struct ThemeImagesTests {
    let red = PNGFixture.make(width: 4, height: 3) { _, _ in (255, 0, 0) }
    let blue = PNGFixture.make(width: 2, height: 2) { _, _ in (0, 0, 255) }

    func decode(_ json: String) throws -> Theme { try Theme.decode(from: Data(json.utf8)) }

    @Test func pngHelpersRoundTrip() throws {
        #expect(ThemeImage.isPNG(red))
        let image = try #require(ThemeImage.cgImage(red))
        #expect(image.width == 4 && image.height == 3)
        #expect(!ThemeImage.isPNG(Data("hello".utf8)))
    }

    @Test func imagesRoundTrip() throws {
        var t = Theme.defaults(for: .dark)
        t.images = Theme.Images(backdrop: red, pixelFont: blue)
        let back = try Theme.decode(from: t.encoded())
        #expect(back.images == t.images)
        #expect(back == t)
    }

    @Test func badBase64DropsOnlyThatImage() throws {
        let t = try decode(#"{"images":{"backdrop":"!!!not base64!!!","pixelFont":"\#(blue.base64EncodedString())"}}"#)
        #expect(t.images.backdrop == nil)
        #expect(t.images.pixelFont == blue)
    }

    @Test func nonPNGIsDropped() throws {
        let t = try decode(#"{"images":{"backdrop":"\#(Data("hello".utf8).base64EncodedString())"}}"#)
        #expect(t.images.isEmpty)
    }

    @Test func oversizedImageIsDropped() throws {
        var big = Data(ThemeImage.pngSignature)
        big.append(Data(count: Theme.Images.maxBytes)) // one signature over the limit
        let t = try decode(#"{"name":"Big","images":{"backdrop":"\#(big.base64EncodedString())","pixelFont":"\#(blue.base64EncodedString())"}}"#)
        #expect(t.name == "Big")
        #expect(t.images.backdrop == nil)
        #expect(t.images.pixelFont == blue)
    }

    @Test func themesWithoutImagesAreUnchanged() throws {
        #expect(try decode("{}").images.isEmpty)
        let json = try #require(String(data: Theme.defaults(for: .light).encoded(), encoding: .utf8))
        #expect(!json.contains("\"images\""))
    }

    /// A flat PNG compresses to a few KB however large it is, so the byte limit alone can't stop it.
    static func flatPNG(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ThemeImage.png(context.makeImage()!)!
    }

    @Test func refusesImagesOverThePixelLimitBeforeDecoding() throws {
        let huge = Self.flatPNG(width: 2049, height: 2048)
        #expect(huge.count < Theme.Images.maxBytes)
        #expect(ThemeImage.maxPixels == 2048 * 2048)
        #expect(ThemeImage.cgImage(huge, maxPixels: ThemeImage.maxPixels) == nil)
        #expect(ThemeImage.cgImage(red, maxPixels: ThemeImage.maxPixels)?.width == 4)
        #expect(ThemeImage.cgImage(red, maxPixels: 11) == nil)
        #expect(ThemeImage.cgImage(Data("nope".utf8), maxPixels: ThemeImage.maxPixels) == nil)
        #expect(BackdropPlan.make(backdrop: huge, colors: Theme.defaults(for: .dark).colors, base: .dark) == nil)
        #expect(PixelFont(png: huge) == nil)
    }
}
