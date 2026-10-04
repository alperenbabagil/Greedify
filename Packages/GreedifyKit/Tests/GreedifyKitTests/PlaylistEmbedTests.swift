import Foundation
import Testing
@testable import GreedifyKit

@MainActor
struct PlaylistEmbedTests {
    static let html = #"""
    <html><head></head><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{
    "type":"playlist","trackList":[
    {"uri":"spotify:track:3E7ZwUMJFqpsDOJzEkBrQ7","title":"Can't Get You out of My Head","subtitle":"Kylie Minogue","duration":230640,"isPlayable":true,"entityType":"track"},
    {"uri":"spotify:track:abc","title":"One Kiss","subtitle":"Calvin Harris, Dua Lipa","duration":214000,"isPlayable":false,"entityType":"track"},
    {"uri":"spotify:episode:ep1","title":"An Episode","subtitle":"A Show","duration":60000,"isPlayable":true,"entityType":"episode"}
    ]}}}}}}</script></body></html>
    """#

    @Test func parsesTheEmbedTrackList() throws {
        let tracks = try PlaylistEmbed.tracks(fromHTML: Data(Self.html.utf8))
        #expect(tracks.map(\.id) == ["3E7ZwUMJFqpsDOJzEkBrQ7", "abc", "ep1"])
        #expect(tracks[0].name == "Can't Get You out of My Head")
        #expect(tracks[0].durationMs == 230640)
        #expect(tracks[1].artists.map(\.name) == ["Calvin Harris", "Dua Lipa"])
        #expect(tracks[1].isPlayable == false)
        #expect(tracks[2].isEpisode)
        #expect(tracks[0].album == nil)
    }

    @Test func pageWithoutDataThrows() {
        #expect(throws: SpotifyError.self) { try PlaylistEmbed.tracks(fromHTML: Data("<html></html>".utf8)) }
    }

    @Test func liveAPIReadsTheEmbedPageWithoutToken() async throws {
        let stub = StubTransport { _ in (200, Self.html, [:]) }
        let (api, _) = Fixture.api(stub)
        let tracks = try await api.publicPlaylistTracks(id: "0hs28dOG3Ng3egGYLFrP29")
        #expect(tracks.count == 3)
        #expect(stub.requests[0].url?.absoluteString == "https://open.spotify.com/embed/playlist/0hs28dOG3Ng3egGYLFrP29")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: LibraryStore

    func cache() -> DataCache {
        DataCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), limitBytes: 10_000_000)
    }
    func followed(_ id: String = "f", snapshot: String = "s1") -> Playlist {
        Playlist(id: id, name: id, uri: "spotify:playlist:\(id)", images: [], owner: PlaylistOwner(id: "someone", displayName: nil),
                 collaborative: false, snapshotId: snapshot, trackCount: 2)
    }
    func bare(_ id: String) -> Track {
        Track(id: id, name: id, uri: "spotify:track:\(id)", durationMs: 1000, artists: [ArtistRef(id: nil, name: "A", uri: "")], album: nil)
    }
    func loadedStore(_ api: FakeSpotifyAPI, cache c: DataCache? = nil) async -> LibraryStore {
        await api.set(playlistPages: [Paging(items: [followed()], next: nil, offset: 0, limit: 50, total: 1)])
        let store = LibraryStore(api: api, cache: c ?? cache())
        await store.load()
        return store
    }

    @Test func someoneElsesPlaylistIsReadFromTheEmbed() async {
        let api = FakeSpotifyAPI()
        await api.set(embed: [bare("a"), bare("b")], for: "f")
        let store = await loadedStore(api)
        let tracks = await store.tracks(for: followed())
        #expect(tracks.map(\.id) == ["a", "b"])
        #expect(await !api.calls.contains { $0.hasPrefix("items(") }) // Spotify would answer 403
        #expect(store.lastError == nil)
    }

    @Test func forbiddenItemsFallBackToTheEmbedWithoutABanner() async {
        let api = FakeSpotifyAPI()
        await api.fail("items(f", with: .forbidden("Forbidden"))
        await api.set(embed: [bare("a")], for: "f")
        let store = LibraryStore(api: api, cache: cache()) // user unknown: tries the API first
        #expect(await store.tracks(for: followed()).map(\.id) == ["a"])
        #expect(store.lastError == nil)
    }

    @Test func embedListIsCachedBySnapshot() async {
        let api = FakeSpotifyAPI()
        await api.set(embed: [bare("a")], for: "f")
        let c = cache()
        _ = await (await loadedStore(api, cache: c)).tracks(for: followed())
        _ = await (await loadedStore(api, cache: c)).tracks(for: followed())
        #expect(await api.calls.filter { $0.hasPrefix("embed(") }.count == 1)
    }

    @Test func queueSongsFillAnUnreadablePlaylist() async {
        let api = FakeSpotifyAPI()
        let c = cache()
        let store = await loadedStore(api, cache: c)
        #expect(await store.tracks(for: followed()).isEmpty)          // embed failed too
        #expect(store.lastError == nil)
        #expect(store.wantsQueueSongs(contextURI: "spotify:playlist:f"))
        await store.recordQueueSongs(contextURI: "spotify:playlist:f", tracks: [Fixture.track("x"), Fixture.track("y")])
        #expect(store.playlistTracks["f"]?.map(\.id) == ["x", "y"])
        // Kept across launches.
        let again = await loadedStore(api, cache: c)
        #expect(await again.tracks(for: followed()).map(\.id) == ["x", "y"])
    }

    @Test func queueSongsAddArtToEmbedSongs() async {
        let api = FakeSpotifyAPI()
        await api.set(embed: [bare("a"), bare("b")], for: "f")
        let store = await loadedStore(api)
        _ = await store.tracks(for: followed())
        await store.recordQueueSongs(contextURI: "spotify:playlist:f", tracks: [Fixture.track("b"), Fixture.track("c")])
        let tracks = store.playlistTracks["f"] ?? []
        #expect(tracks.map(\.id) == ["a", "b", "c"])
        #expect(tracks[1].album != nil) // the queue's copy, with album art
    }

    @Test func readablePlaylistsIgnoreTheQueue() async {
        let api = FakeSpotifyAPI()
        await api.set(items: [PlaylistItem(addedAt: nil, track: Fixture.track("t"))], for: "mine")
        let store = LibraryStore(api: api, cache: cache())
        let mine = Playlist(id: "mine", name: "m", uri: "spotify:playlist:mine", images: [], owner: PlaylistOwner(id: "me", displayName: nil),
                            collaborative: false, snapshotId: "s", trackCount: 1)
        _ = await store.tracks(for: mine)
        #expect(!store.wantsQueueSongs(contextURI: mine.uri))
        await store.recordQueueSongs(contextURI: mine.uri, tracks: [Fixture.track("z")])
        #expect(store.playlistTracks["mine"]?.map(\.id) == ["t"])
    }
}
