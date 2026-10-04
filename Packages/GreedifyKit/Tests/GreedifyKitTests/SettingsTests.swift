import Foundation
import Testing
@testable import GreedifyKit

struct LibrespotConfigTests {
    let sys = URL(fileURLWithPath: "/tmp/Greedify/librespot")
    let audio = URL(fileURLWithPath: "/tmp/Greedify Cache/audio")

    @Test func defaultArgumentsDisableAudioCache() {
        let c = LibrespotConfig(deviceName: "Studio Mac", bitrate: 320, normalisation: true, audioCacheLimitBytes: nil,
                                systemCacheDir: sys, audioCacheDir: audio)
        #expect(c.arguments == ["--name", "Studio Mac", "--device-type", "computer", "--bitrate", "320", "--autoplay", "on",
                                "--system-cache", "/tmp/Greedify/librespot", "--cache", "/tmp/Greedify Cache/audio",
                                "--volume-ctrl", "linear", "--enable-volume-normalisation", "--disable-audio-cache"])
        #expect(c.argsFileContents.split(separator: "\n").count == c.arguments.count)
        #expect(c.loginArguments.last == "--enable-oauth")
    }

    @Test func audioCacheLimit() {
        let c = LibrespotConfig(deviceName: "Mac", bitrate: 160, normalisation: false, audioCacheLimitBytes: 2 * 1_073_741_824,
                                systemCacheDir: sys, audioCacheDir: audio)
        #expect(c.arguments.suffix(2) == ["--cache-size-limit", "2048M"])
        #expect(!c.arguments.contains("--enable-volume-normalisation"))
    }

    @Test func findsLoginURLInOutput() {
        let out = "[INFO] Open this URL in a browser: https://accounts.spotify.com/authorize?client_id=65b7&redirect_uri=http%3A%2F%2F127.0.0.1%3A5588%2Flogin\n"
        #expect(LibrespotService.loginURL(in: out)?.host == "accounts.spotify.com")
        #expect(LibrespotService.loginURL(in: "nothing here") == nil)
    }
}

@MainActor
struct AppSettingsTests {
    func defaults() -> UserDefaults {
        let name = "greedify-test-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultsAndPersistence() {
        let d = defaults()
        let s = AppSettings(defaults: d, hostName: "Studio Mac")
        #expect(s.deviceName == "Studio Mac")
        #expect(s.blockAppleMusic)
        #expect(s.lyricsInMenuBar)
        #expect(s.bitrate == 320)
        #expect(s.appCacheMB == 300)
        #expect(s.audioCacheGB == 0)
        #expect(s.librespotConfig.audioCacheLimitBytes == nil)
        s.audioCacheGB = 1
        s.appearance = .dark
        let reloaded = AppSettings(defaults: d, hostName: "x")
        #expect(reloaded.audioCacheGB == 1)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.librespotConfig.audioCacheLimitBytes == 1_073_741_824)
    }

    @Test func mixes() {
        let s = AppSettings(defaults: defaults(), hostName: "Mac")
        #expect(s.addMix(link: "https://open.spotify.com/playlist/37i9dQZF1E39vTG3GurFPW?si=1", name: "Daily Mix 1"))
        #expect(!s.addMix(link: "spotify:playlist:37i9dQZF1E39vTG3GurFPW", name: "dup"))
        #expect(!s.addMix(link: "not a link", name: "x"))
        #expect(s.mixes.map(\.name) == ["Daily Mix 1"])
        s.removeMix(s.mixes[0])
        #expect(s.mixes.isEmpty)
    }

    func track(_ id: String, cover: String? = nil) -> Track {
        let images = cover.map { [SpotifyImage(url: URL(string: "https://i.scdn.co/image/\($0)")!, width: 300, height: 300)] } ?? []
        return Track(id: id, name: id, uri: "spotify:track:\(id)", durationMs: 1000, artists: [],
                     album: AlbumRef(id: "a", name: "A", uri: "spotify:album:a", images: images))
    }

    @Test func mixTracksComeFromTheQueue() {
        let d = defaults()
        let s = AppSettings(defaults: d, hostName: "Mac")
        _ = s.addMix(link: "spotify:playlist:37i9dQZF1E39vTG3GurFPW", name: "Daily Mix 1")
        let uri = s.mixes[0].uri
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        s.recordMixTracks(uri: uri, tracks: [track("1", cover: "c1"), track("2"), track("3")], at: t0)
        #expect(s.mixTracks(uri).map(\.id) == ["1", "2", "3"])
        #expect(s.mixCover(uri).first?.url.lastPathComponent == "c1")
        // Later in the same mix: new songs are appended, known ones keep their place.
        s.recordMixTracks(uri: uri, tracks: [track("3"), track("4"), track("3")], at: t0.addingTimeInterval(600))
        #expect(s.mixTracks(uri).map(\.id) == ["1", "2", "3", "4"])
        // Persisted.
        #expect(AppSettings(defaults: d, hostName: "Mac").mixTracks(uri).map(\.id) == ["1", "2", "3", "4"])
        // Played again within 8 hours of the last recording: still the same mix.
        let t1 = t0.addingTimeInterval(600 + 7 * 3600)
        s.recordMixTracks(uri: uri, tracks: [track("5")], at: t1)
        #expect(s.mixTracks(uri).count == 5)
        #expect(s.mixSongs[uri]?.isOutdated(at: t1.addingTimeInterval(3600), name: "Daily Mix 1") == false)
        // Unplayed for 8 hours, so Spotify has refreshed the mix: start over.
        #expect(s.mixSongs[uri]?.isOutdated(at: t1.addingTimeInterval(8 * 3600), name: "Daily Mix 1") == true)
        s.recordMixTracks(uri: uri, tracks: [track("9", cover: "c9")], at: t1.addingTimeInterval(8 * 3600))
        #expect(s.mixTracks(uri).map(\.id) == ["9"])
        #expect(s.mixCover(uri).first?.url.lastPathComponent == "c9")
        // Not a saved mix: ignored. Removing a mix drops its songs.
        s.recordMixTracks(uri: "spotify:playlist:other", tracks: [track("1")], at: t0)
        #expect(s.mixTracks("spotify:playlist:other").isEmpty)
        s.removeMix(s.mixes[0])
        #expect(s.mixTracks(uri).isEmpty)
    }

    @Test func listeningAllDayKeepsExtendingTheMix() {
        let s = AppSettings(defaults: defaults(), hostName: "Mac")
        _ = s.addMix(link: "spotify:playlist:37i9dQZF1E39vTG3GurFPW", name: "Daily Mix 1")
        let uri = s.mixes[0].uri
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for hour in 0..<14 { s.recordMixTracks(uri: uri, tracks: [track("\(hour)")], at: t0.addingTimeInterval(Double(hour) * 3600)) }
        #expect(s.mixTracks(uri).count == 14)                     // never an 8-hour gap
        #expect(s.mixSongs[uri]?.capturedAt == t0.addingTimeInterval(13 * 3600))
    }

    @Test func weeklyMixesAreOutdatedAfterTheirRefreshDay() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        // 2026-09-27 is a Sunday; Discover Weekly refreshes on Monday, Release Radar on Friday.
        let sunday = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 23)))
        let monday = sunday.addingTimeInterval(2 * 3600)
        let mix = MixTracks(tracks: [track("1")], startedAt: sunday)
        #expect(mix.isOutdated(at: monday, name: "Discover Weekly", calendar: utc))
        #expect(!mix.isOutdated(at: monday, name: "Release Radar", calendar: utc))
        #expect(!mix.isOutdated(at: monday, name: "Daily Mix 2", calendar: utc))
        let friday = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9)))
        let thursday = friday.addingTimeInterval(-10 * 3600)
        #expect(MixTracks(tracks: [], startedAt: thursday).isOutdated(at: friday, name: "My release radar", calendar: utc))
    }

    @Test func mixesSavedBeforeLastCaptureStillDecode() throws {
        let old = #"{"tracks":[],"startedAt":100}"#
        let mix = try JSONDecoder().decode(MixTracks.self, from: Data(old.utf8))
        #expect(mix.capturedAt == Date(timeIntervalSinceReferenceDate: 100))
    }
}

@MainActor
struct LibrespotLoginTests {
    final class URLBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: URL?
        var url: URL? { lock.withLock { stored } }
        func set(_ u: URL) { lock.withLock { stored = u } }
    }

    /// A stand-in librespot: prints a login URL, then writes credentials.json into --system-cache.
    func fakeLibrespot(in dir: URL) throws -> URL {
        let script = dir.appendingPathComponent("fake-librespot")
        try """
        #!/bin/sh
        echo "Open this URL in a browser: https://accounts.spotify.com/authorize?client_id=x&redirect_uri=http%3A%2F%2F127.0.0.1%3A5588%2Flogin"
        prev=""
        for a in "$@"; do
          if [ "$prev" = "--system-cache" ]; then sleep 1; mkdir -p "$a"; echo '{}' > "$a/credentials.json"; fi
          prev="$a"
        done
        sleep 30
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @Test func interactiveLoginReportsTheLoginURL() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("greedify-login-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = LibrespotConfig(deviceName: "Test", bitrate: 160, normalisation: false, audioCacheLimitBytes: nil,
                                     systemCacheDir: dir.appendingPathComponent("sys"), audioCacheDir: dir.appendingPathComponent("audio"))
        let box = URLBox()
        let ok = await LibrespotService().interactiveLogin(config, librespotURL: try fakeLibrespot(in: dir), timeout: .seconds(10)) { box.set($0) }
        #expect(ok)
        #expect(box.url?.host == "accounts.spotify.com")
    }

}
