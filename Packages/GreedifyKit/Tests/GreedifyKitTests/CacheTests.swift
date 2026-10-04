import AppKit
import Foundation
import Testing
@testable import GreedifyKit

struct DataCacheTests {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("greedify-test-\(UUID().uuidString)")
    }

    @Test func storeAndRead() async {
        let cache = DataCache(directory: tempDir(), limitBytes: 1_000)
        await cache.store(Data("hello".utf8), for: "k")
        #expect(await cache.data(for: "k") == Data("hello".utf8))
        #expect(await cache.data(for: "missing") == nil)
        #expect(await cache.sizeBytes() == 5)
    }

    @Test func evictsLeastRecentlyUsed() async throws {
        let dir = tempDir()
        let cache = DataCache(directory: dir, limitBytes: 250)
        await cache.store(Data(count: 100), for: "a")
        await cache.store(Data(count: 100), for: "b")
        // Make "a" older than "b", then read "a" so "b" becomes least recently used.
        let fm = FileManager.default
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: await cache.fileURL(for: "a").path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -50)], ofItemAtPath: await cache.fileURL(for: "b").path)
        _ = await cache.data(for: "a")
        await cache.store(Data(count: 100), for: "c") // 300 > 250 → evict "b"
        #expect(await cache.data(for: "a") != nil)
        #expect(await cache.data(for: "b") == nil)
        #expect(await cache.data(for: "c") != nil)
    }

    @Test func lowerLimitEvictsImmediately() async {
        let cache = DataCache(directory: tempDir(), limitBytes: 1_000)
        await cache.store(Data(count: 400), for: "a")
        await cache.store(Data(count: 400), for: "b")
        await cache.setLimit(500)
        #expect(await cache.sizeBytes() <= 500)
    }

    @Test func clearRemovesEverything() async {
        let cache = DataCache(directory: tempDir(), limitBytes: 1_000)
        await cache.store(Data(count: 10), for: "a")
        await cache.clear()
        #expect(await cache.sizeBytes() == 0)
    }

    @Test func codableRoundTrip() async {
        let cache = DataCache(directory: tempDir(), limitBytes: 10_000)
        await cache.store(["x", "y"], for: "list")
        #expect(await cache.value([String].self, for: "list") == ["x", "y"])
    }
}

struct ImageCacheTests {
    static func pngData(side: Int = 4) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill(); NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func fetchesOnceThenServesFromMemory() async {
        let png = Self.pngData()
        final class Box: HTTPTransport, @unchecked Sendable {
            let png: Data; var count = 0
            init(_ png: Data) { self.png = png }
            func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
                count += 1
                return (png, HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let box = Box(png)
        let disk = DataCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), limitBytes: 1_000_000)
        let cache = ImageCache(disk: disk, transport: box, memoryLimitBytes: 1_000_000)
        let url = URL(string: "https://i.scdn.co/image/x")!
        #expect(await cache.image(for: url) != nil)
        #expect(await cache.image(for: url) != nil)
        #expect(box.count == 1)
        cache.clearMemory()
        #expect(await cache.image(for: url) != nil) // from disk
        #expect(box.count == 1)
    }

    final class CountingTransport: HTTPTransport, @unchecked Sendable {
        let data: Data; var count = 0
        init(_ data: Data) { self.data = data }
        func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
            count += 1
            return (data, HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func decodesAtTheRequestedPixelSize() async throws {
        let transport = CountingTransport(Self.pngData(side: 64))
        let disk = DataCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), limitBytes: 1_000_000)
        let cache = ImageCache(disk: disk, transport: transport, memoryLimitBytes: 1_000_000)
        let url = URL(string: "https://i.scdn.co/image/big")!
        let small = try #require(await cache.image(for: url, maxPixelSize: 16))
        #expect(max(small.representations[0].pixelsWide, small.representations[0].pixelsHigh) <= 16)
        let full = try #require(await cache.image(for: url))
        #expect(full.representations[0].pixelsWide == 64)
        #expect(transport.count == 1)                                  // one download; sizes decoded from it
        #expect(cache.cached(url, maxPixelSize: 16) != nil)            // each size cached separately
        #expect(ImageCache.cost(of: small) <= 16 * 16 * 4)             // cost counts the decoded size
    }
}

