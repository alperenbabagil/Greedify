import Foundation
import Testing
@testable import GreedifyKit

struct LibrespotEventTests {
    /// The bundled `--onevent` script: its output is the contract with `LibrespotEvent.parse`.
    static let script = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/greedify-event")

    /// Runs the script with librespot's environment for one event (as captured from librespot 0.8).
    func emit(_ env: [String: String]) throws -> String {
        let p = Process()
        p.executableURL = Self.script
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func event(_ env: [String: String]) throws -> LibrespotEvent? {
        LibrespotEvent.parse(try emit(env).trimmingCharacters(in: .newlines))
    }

    @Test func trackChanged() throws {
        let e = try event([
            "PLAYER_EVENT": "track_changed", "ITEM_TYPE": "Track", "TRACK_ID": "4E10qEzOmTIVmrg6Wz2RHj",
            "URI": "spotify:track:4E10qEzOmTIVmrg6Wz2RHj", "NAME": "Saygımdan", "DURATION_MS": "271210",
            "ARTISTS": "Bengü\nSıla", "ALBUM": "İkinci Hal",
            "COVERS": "https://i.scdn.co/image/ab67616d0000b27397ad\nhttps://i.scdn.co/image/ab67616d00001e0297ad\nhttps://i.scdn.co/image/ab67616d0000485197ad",
        ])
        guard case .trackChanged(let t) = e else { Issue.record("got \(String(describing: e))"); return }
        #expect(t.id == "4E10qEzOmTIVmrg6Wz2RHj")
        #expect(t.uri == "spotify:track:4E10qEzOmTIVmrg6Wz2RHj")
        #expect(t.name == "Saygımdan")
        #expect(t.durationMs == 271_210)
        #expect(t.artistLine == "Bengü, Sıla")
        #expect(t.album?.name == "İkinci Hal")
        #expect(t.album?.images.best(minSide: 300)?.url.absoluteString == "https://i.scdn.co/image/ab67616d00001e0297ad")
    }

    @Test func episodeChanged() throws {
        let e = try event([
            "PLAYER_EVENT": "track_changed", "ITEM_TYPE": "Episode", "TRACK_ID": "5Xt5DXGzch68nYYamXrNxZ",
            "URI": "spotify:episode:5Xt5DXGzch68nYYamXrNxZ", "NAME": "Episode 12", "SHOW_NAME": "The Show",
            "DURATION_MS": "3000000", "COVERS": "https://i.scdn.co/image/ab6765630000ba8a01",
        ])
        guard case .trackChanged(let t) = e else { Issue.record("got \(String(describing: e))"); return }
        #expect(t.isEpisode && t.id == "5Xt5DXGzch68nYYamXrNxZ" && t.name == "Episode 12" && t.durationMs == 3_000_000)
        #expect(t.artistLine == "The Show" && t.album?.name == "The Show" && t.show?.name == "The Show" && t.show?.id == nil)
        #expect(t.album?.images.first?.url.absoluteString == "https://i.scdn.co/image/ab6765630000ba8a01")
    }

    @Test func playbackEvents() throws {
        #expect(try event(["PLAYER_EVENT": "playing", "TRACK_ID": "t", "POSITION_MS": "65551"]) == .playing(trackID: "t", positionMs: 65_551))
        #expect(try event(["PLAYER_EVENT": "paused", "TRACK_ID": "t", "POSITION_MS": "1000"]) == .paused(trackID: "t", positionMs: 1000))
        #expect(try event(["PLAYER_EVENT": "seeked", "TRACK_ID": "t", "POSITION_MS": "5"]) == .seeked(trackID: "t", positionMs: 5))
        #expect(try event(["PLAYER_EVENT": "position_correction", "TRACK_ID": "t", "POSITION_MS": "7"]) == .seeked(trackID: "t", positionMs: 7))
        #expect(try event(["PLAYER_EVENT": "stopped", "TRACK_ID": "t"]) == .stopped)
        #expect(try event(["PLAYER_EVENT": "session_disconnected"]) == .sessionDisconnected)
    }

    @Test func settingsEvents() throws {
        #expect(try event(["PLAYER_EVENT": "volume_changed", "VOLUME": "65535"]) == .volume(percent: 100))
        #expect(try event(["PLAYER_EVENT": "volume_changed", "VOLUME": "32768"]) == .volume(percent: 50))
        #expect(try event(["PLAYER_EVENT": "shuffle_changed", "SHUFFLE": "true"]) == .shuffle(true))
        #expect(try event(["PLAYER_EVENT": "repeat_changed", "REPEAT": "true", "REPEAT_TRACK": "false"]) == .repeatMode(.context))
        #expect(try event(["PLAYER_EVENT": "repeat_changed", "REPEAT": "false", "REPEAT_TRACK": "true"]) == .repeatMode(.track))
    }

    @Test func ignoresOtherOutput() {
        #expect(LibrespotEvent.parse("[2026-09-30T00:09:15Z INFO  librespot] Using CoreAudio sink") == nil)
        #expect(LibrespotEvent.parse("GREEDIFY-EVENT\tPLAYER_EVENT=preloading\tTRACK_ID=t") == .other("preloading"))
        #expect(LibrespotEvent.parse("GREEDIFY-EVENT\tPLAYER_EVENT=track_changed\tITEM_TYPE=Episode\tTRACK_ID=e") == .other("track_changed"))
    }
}
