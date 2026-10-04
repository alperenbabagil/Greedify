import Foundation
import Testing
@testable import GreedifyKit

struct LRCParserTests {
    let lrc = """
    [ar:The Quiet Harbor]
    [00:12.50] We folded our names into paper satellites
    [00:17.00] Threw them off the roof on a Tuesday night
    [00:21.30]
    [00:25.00][01:10.00] Watched them drift past the laundromat light
    not a timed line
    """

    @Test func parsesTimesTextAndRepeats() {
        let lines = LRCParser.parse(lrc)
        #expect(lines.map(\.timeMs) == [12_500, 17_000, 21_300, 25_000, 70_000])
        #expect(lines[0].text == "We folded our names into paper satellites")
        #expect(lines[2].isGap)
        #expect(lines[4].text == "Watched them drift past the laundromat light")
    }

    @Test func currentIndex() {
        let lines = LRCParser.parse(lrc)
        #expect(LRCParser.currentIndex(in: lines, at: 0) == nil)
        #expect(LRCParser.currentIndex(in: lines, at: 12_500) == 0)
        #expect(LRCParser.currentIndex(in: lines, at: 20_000) == 1)
        #expect(LRCParser.currentIndex(in: lines, at: 999_000) == 4)
        #expect(LRCParser.currentIndex(in: [], at: 5) == nil)
    }

    @Test func nextChange() {
        let lines = LRCParser.parse(lrc)
        #expect(LRCParser.nextChangeMs(in: lines, after: 13_000) == 17_000)
        #expect(LRCParser.nextChangeMs(in: lines, after: 80_000) == nil)
    }
}

struct MenuBarLabelTests {
    let lines = LRCParser.parse("[00:01.00] First line\n[00:05.00]\n[00:08.00] Third line")

    @Test func states() {
        func label(_ lyrics: Lyrics, enabled: Bool = true, playing: Bool = true, name: String? = "Song", at ms: Int = 2000) -> MenuBarLabel {
            MenuBarLabel.make(enabled: enabled, isPlaying: playing, trackName: name, lyrics: lyrics, positionMs: ms)
        }
        #expect(label(.synced(lines)) == .text("First line"))
        #expect(label(.synced(lines), at: 6000) == .text("♪"))       // empty LRC line
        #expect(label(.synced(lines), at: 500) == .text("♪"))        // before first line
        #expect(label(.plain("words")) == .text("Song"))
        #expect(label(.none) == .iconOnly)
        #expect(label(.synced(lines), enabled: false) == .iconOnly)
        #expect(label(.synced(lines), playing: false) == .iconOnly)
        #expect(label(.synced(lines), name: nil) == .iconOnly)
    }

    @Test func announcementWinsWhilePlaying() {
        func label(enabled: Bool = true, playing: Bool = true) -> MenuBarLabel {
            MenuBarLabel.make(enabled: enabled, isPlaying: playing, trackName: "Song", lyrics: .synced(lines),
                              positionMs: 2000, announcement: "Artist – Song")
        }
        #expect(label() == .text("Artist – Song"))
        #expect(label(enabled: false) == .text("Artist – Song")) // shown even with lyrics off in the menu bar
        #expect(label(playing: false) == .iconOnly)
    }

    @Test func announcementText() {
        let track = Track(id: "1", name: "Song", uri: "spotify:track:1", durationMs: 1,
                          artists: [ArtistRef(id: "a", name: "A", uri: "a"), ArtistRef(id: "b", name: "B", uri: "b")], album: nil)
        #expect(MenuBarLabel.announcement(for: track) == "A, B – Song")
    }

    @Test func truncatesLongLines() {
        let long = String(repeating: "a", count: 80)
        guard case .text(let s) = MenuBarLabel.make(enabled: true, isPlaying: true, trackName: "S",
                                                     lyrics: .synced([LyricLine(timeMs: 0, text: long)]), positionMs: 1) else {
            Issue.record("expected text"); return
        }
        #expect(s.count == MenuBarLabel.maxCharacters)
        #expect(s.hasSuffix("…"))
    }
}

struct LyricsServiceTests {
    func cache() -> DataCache {
        DataCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), limitBytes: 1_000_000)
    }

    @Test func syncedFromGetAndCached() async {
        let stub = StubTransport { _ in (200, #"{"syncedLyrics":"[00:01.00] Hi","plainLyrics":"Hi"}"#, [:]) }
        let service = LyricsService(transport: stub, cache: cache())
        #expect(await service.lyrics(for: Fixture.track) == .synced([LyricLine(timeMs: 1000, text: "Hi")]))
        #expect(await service.lyrics(for: Fixture.track) == .synced([LyricLine(timeMs: 1000, text: "Hi")]))
        #expect(stub.requests.count == 1)
        #expect(stub.requests[0].query("duration") == "245")
        #expect(stub.requests[0].url?.path == "/api/get")
    }

    @Test func fallsBackToSearch() async {
        let stub = StubTransport { req in
            req.url!.path.hasSuffix("/get") ? (404, "", [:]) : (200, #"[{"plainLyrics":"just words"}]"#, [:])
        }
        let service = LyricsService(transport: stub, cache: cache())
        #expect(await service.lyrics(for: Fixture.track) == .plain("just words"))
    }

    @Test func notFoundIsCachedButExpires() async {
        let stub = StubTransport { req in req.url!.path.hasSuffix("/get") ? (404, "", [:]) : (200, "[]", [:]) }
        let box = DateBox(Date(timeIntervalSince1970: 0))
        let service = LyricsService(transport: stub, cache: cache(), now: { box.value })
        #expect(await service.lyrics(for: Fixture.track) == .none)
        #expect(await service.lyrics(for: Fixture.track) == .none)
        #expect(stub.requests.count == 2)            // get + search, once
        box.value = Date(timeIntervalSince1970: 8 * 24 * 3600)
        _ = await service.lyrics(for: Fixture.track)
        #expect(stub.requests.count == 4)            // refetched after 7 days
    }

    @Test func networkErrorIsNotCached() async {
        let stub = StubTransport { _ in throw URLError(.notConnectedToInternet) }
        let service = LyricsService(transport: stub, cache: cache())
        #expect(await service.lyrics(for: Fixture.track) == .none)
        stub.setHandler { _ in (200, #"{"syncedLyrics":"[00:01.00] Back"}"#, [:]) }
        #expect(await service.lyrics(for: Fixture.track) == .synced([LyricLine(timeMs: 1000, text: "Back")]))
    }
}

final class DateBox: @unchecked Sendable {
    var value: Date
    init(_ v: Date) { value = v }
}
