import Foundation
import Testing
@testable import GreedifyKit

struct MediaKeyDecoderTests {
    func data1(key: Int, down: Bool) -> Int { (key << 16) | ((down ? 0x0A : 0x0B) << 8) }

    @Test func decodesKeys() {
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(key: 16, down: true))! == (.playPause, true))
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(key: 16, down: false))! == (.playPause, false))
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(key: 17, down: true))!.action == .next)
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(key: 19, down: true))!.action == .next)
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(key: 18, down: true))!.action == .previous)
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(key: 20, down: true))!.action == .previous)
    }

    @Test func ignoresOtherEvents() {
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(key: 0, down: true)) == nil)   // volume up
        #expect(MediaKeyDecoder.decode(subtype: 7, data1: data1(key: 16, down: true)) == nil)  // not media subtype
    }

    @Test func musicBlockerPredicate() {
        #expect(MusicBlocker.shouldBlock(bundleID: "com.apple.Music", enabled: true))
        #expect(!MusicBlocker.shouldBlock(bundleID: "com.apple.Music", enabled: false))
        #expect(!MusicBlocker.shouldBlock(bundleID: "com.apple.Safari", enabled: true))
        #expect(!MusicBlocker.shouldBlock(bundleID: nil, enabled: true))
    }
}

struct TitleBarDoubleClickTests {
    @Test func followsTheSystemSetting() {
        #expect(TitleBarDoubleClick.action(for: nil) == .zoom)          // unset = macOS default (zoom/fill)
        #expect(TitleBarDoubleClick.action(for: "Maximize") == .zoom)
        #expect(TitleBarDoubleClick.action(for: "Fill") == .zoom)
        #expect(TitleBarDoubleClick.action(for: "Minimize") == .minimize)
        #expect(TitleBarDoubleClick.action(for: "None") == .none)
    }
}
