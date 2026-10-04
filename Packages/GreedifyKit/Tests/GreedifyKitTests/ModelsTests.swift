import Foundation
import Testing
@testable import GreedifyKit

struct ModelsTests {
    @Test func decodesTrack() throws {
        let t = Fixture.track
        #expect(t.id == "t1")
        #expect(t.durationMs == 245_000)
        #expect(t.artistLine == "The Quiet Harbor")
        #expect(t.album?.images.best()?.url.absoluteString == "https://i.scdn.co/300")
    }

    @Test func playlistCountFromItemsOrTracksKey() throws {
        let newShape = try SpotifyJSON.decoder.decode(Playlist.self, from: Data(Fixture.playlistJSON(total: 7).utf8))
        #expect(newShape.trackCount == 7)
        let old = Fixture.playlistJSON(total: 3).replacingOccurrences(of: "\"items\"", with: "\"tracks\"")
        #expect(try SpotifyJSON.decoder.decode(Playlist.self, from: Data(old.utf8)).trackCount == 3)
    }

    @Test func playlistItemReadsItemThenLegacyTrackKey() throws {
        let a = try SpotifyJSON.decoder.decode(PlaylistItem.self, from: Data(#"{"added_at":"x","item":\#(Fixture.trackJSON)}"#.utf8))
        let b = try SpotifyJSON.decoder.decode(PlaylistItem.self, from: Data(#"{"added_at":"x","track":\#(Fixture.trackJSON)}"#.utf8))
        let episode = try SpotifyJSON.decoder.decode(PlaylistItem.self, from: Data(#"{"added_at":"x","item":{"type":"episode","id":"e"}}"#.utf8))
        #expect(a.track?.id == "t1")
        #expect(b.track?.id == "t1")
        #expect(episode.track == nil)
    }

    @Test func pagingDropsNullItems() throws {
        let json = Fixture.page([Fixture.playlistJSON(id: "p1"), "null", Fixture.playlistJSON(id: "p2")], next: "https://next")
        let page = try SpotifyJSON.decoder.decode(Paging<Playlist>.self, from: Data(json.utf8))
        #expect(page.items.map(\.id) == ["p1", "p2"])
        #expect(page.hasMore)
    }

    @Test func playbackStateWithEpisodeHasNilItem() throws {
        let json = #"{"is_playing":true,"progress_ms":5,"item":{"type":"episode","id":"e1","name":"Pod"},"device":{"id":"d","name":"Mac","type":"Computer","is_active":true,"volume_percent":50}}"#
        let s = try SpotifyJSON.decoder.decode(PlaybackState.self, from: Data(json.utf8))
        #expect(s.isPlaying)
        #expect(s.item == nil)
        #expect(s.device?.name == "Mac")
    }

    @Test func queueDropsEpisodes() throws {
        let json = #"{"currently_playing":\#(Fixture.trackJSON),"queue":[\#(Fixture.trackJSON),{"type":"episode","id":"e"}]}"#
        let q = try SpotifyJSON.decoder.decode(QueueResponse.self, from: Data(json.utf8))
        #expect(q.currentlyPlaying?.id == "t1")
        #expect(q.queue.map(\.id) == ["t1"])
    }

    @Test func playRequestBodies() {
        #expect(PlayRequest.resume.jsonBody == nil)
        let ctx = PlayRequest.context("spotify:playlist:p", startingAt: "spotify:track:t").jsonBody!
        #expect(ctx["context_uri"] as? String == "spotify:playlist:p")
        #expect((ctx["offset"] as? [String: String])?["uri"] == "spotify:track:t")
        #expect(PlayRequest.tracks(["u"]).jsonBody?["uris"] as? [String] == ["u"])
        #expect(PlayRequest.tracks(["u"]).jsonBody?["offset"] == nil)
        // With shuffle on and no offset, Spotify starts a list of songs at a random one: name the clicked song.
        let list = PlayRequest.tracks(["a", "b", "c"], startingAt: "b").jsonBody!
        #expect(list["uris"] as? [String] == ["a", "b", "c"])
        #expect((list["offset"] as? [String: String])?["uri"] == "b")
    }

    @Test func songListWindowKeepsTheClickedSong() {
        let uris = (0..<250).map { "u\($0)" }
        #expect(PlayRequest.songs(uris, clicked: "u3") == .tracks(Array(uris[3..<103]), startingAt: "u3"))
        #expect(PlayRequest.songs(uris, clicked: "u120") == .tracks(Array(uris[120..<220]), startingAt: "u120"))
        #expect(PlayRequest.songs(uris, clicked: "u240") == .tracks(Array(uris[150..<250]), startingAt: "u240"))
        #expect(PlayRequest.songs(["a", "b"], clicked: "b") == .tracks(["a", "b"], startingAt: "b"))
    }

    @Test func editablePlaylist() throws {
        let p = try SpotifyJSON.decoder.decode(Playlist.self, from: Data(Fixture.playlistJSON(owner: "me").utf8))
        #expect(p.isEditable(by: "me"))
        #expect(!p.isEditable(by: "someone"))
    }

    @Test func errorMapping() {
        let body = Data(#"{"error":{"status":404,"message":"Player command failed: No active device found","reason":"NO_ACTIVE_DEVICE"}}"#.utf8)
        #expect(SpotifyError.from(status: 404, headers: [:], body: body) == .noActiveDevice)
        #expect(SpotifyError.from(status: 404, headers: [:], body: Data()) == .notFound)
        let quota = Data(#"{"error":{"status":429,"message":"x","reason":"QUOTA_EXCEEDED"}}"#.utf8)
        #expect(SpotifyError.from(status: 429, headers: ["Retry-After": "12"], body: quota) == .rateLimited(retryAfter: 12, quotaExceeded: true))
        #expect(SpotifyError.from(status: 429, headers: [:], body: Data()) == .rateLimited(retryAfter: 5, quotaExceeded: false))
        #expect(SpotifyError.from(status: 403, headers: [:], body: Data()) == .forbidden(""))
        #expect(SpotifyError.forbidden("Player command failed: Restriction violated").bannerText == "Spotify didn't accept that command. Try again.")
        #expect(SpotifyError.forbidden("Forbidden").bannerText == "You can only change playlists you own")
    }
}

@MainActor
struct NowPlayingLinkTests {
    @Test func albumPageComesFromTheTrackWithoutAFetch() {
        let album = Album(of: Fixture.track)
        #expect(album?.id == "al1")
        #expect(album?.name == Fixture.track.album?.name)
        #expect(album?.images == Fixture.track.album?.images)
        #expect(album?.artists == Fixture.track.artists)
    }

    @Test func noLinksUntilTheIDsArrive() {
        #expect(Album(of: PlayerStoreTests.bare) == nil)                     // librespot reports no album id
        #expect(PlayerStoreTests.bare.artists.compactMap(Artist.init(ref:)).isEmpty)
    }

    @Test func artistPageFromARef() {
        let artist = Artist(ref: ArtistRef(id: "ar1", name: "The Quiet Harbor", uri: "spotify:artist:ar1"))
        #expect(artist?.id == "ar1" && artist?.uri == "spotify:artist:ar1" && artist?.images == nil)
    }
}
