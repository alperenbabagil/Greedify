import Foundation
import Testing
@testable import GreedifyKit

/// The menu-bar popover's search: a few songs, artists, albums and playlists, each playable with one click.
@MainActor
struct QuickSearchTests {
    func song(_ n: Int) -> Track {
        Track(id: "t\(n)", name: "Song \(n)", uri: "spotify:track:t\(n)", durationMs: 1000,
              artists: [ArtistRef(id: "a", name: "Accept", uri: "spotify:artist:a")], album: nil)
    }
    func artist(_ n: Int) -> Artist { Artist(id: "ar\(n)", name: "Artist \(n)", uri: "spotify:artist:ar\(n)", images: nil) }
    func album(_ n: Int) -> Album {
        Album(id: "al\(n)", name: "Album \(n)", uri: "spotify:album:al\(n)", images: [],
              artists: [ArtistRef(id: "a", name: "Accept", uri: "spotify:artist:a")], totalTracks: nil)
    }
    func playlist(_ n: Int) -> Playlist {
        Playlist(id: "p\(n)", name: "List \(n)", uri: "spotify:playlist:p\(n)", images: [],
                 owner: PlaylistOwner(id: "o", displayName: "Ada"), collaborative: false, snapshotId: "s", trackCount: 3)
    }
    func page<T>(_ items: [T]) -> Paging<T> { Paging(items: items, next: nil, offset: 0, limit: 10, total: items.count) }

    func store() async -> (SearchStore, FakeSpotifyAPI) {
        let api = FakeSpotifyAPI()
        await api.set(search: SearchResults(tracks: page((1...7).map(song)), albums: page((1...5).map(album)),
                                            artists: page((1...5).map(artist)), playlists: page((1...5).map(playlist))))
        return (SearchStore.quick(api: api, debounce: .milliseconds(1)), api)
    }

    @Test func searchesOnlySongsArtistsAlbumsAndPlaylists() async {
        let (store, api) = await store()
        store.query = "accept"
        await store.settle()
        #expect(await api.calls.filter { $0.hasPrefix("search") } == ["search(accept,track+artist+album+playlist,0)"])
    }

    @Test func keepsFiveSongsThenThreeOfEachKind() async {
        let (store, _) = await store()
        store.query = "accept"
        await store.settle()
        let ids = store.quickResults.map(\.id)
        #expect(ids == ["spotify:track:t1", "spotify:track:t2", "spotify:track:t3", "spotify:track:t4", "spotify:track:t5",
                        "spotify:artist:ar1", "spotify:artist:ar2", "spotify:artist:ar3",
                        "spotify:album:al1", "spotify:album:al2", "spotify:album:al3",
                        "spotify:playlist:p1", "spotify:playlist:p2", "spotify:playlist:p3"])
    }

    @Test func aSongPlaysAloneEverythingElseAsAContext() {
        #expect(QuickSearchResult.song(song(1)).item.playRequest == .tracks(["spotify:track:t1"]))
        #expect(QuickSearchResult.album(album(1)).item.playRequest == .context("spotify:album:al1"))
        #expect(QuickSearchResult.artist(artist(1)).item.playRequest == .context("spotify:artist:ar1"))
        #expect(QuickSearchResult.playlist(playlist(1)).item.playRequest == .context("spotify:playlist:p1"))
    }

    @Test func eachRowSaysWhatItIs() {
        #expect(QuickSearchResult.song(song(1)).item.subtitle == "Accept")
        #expect(QuickSearchResult.artist(artist(1)).item.subtitle == "Artist")
        #expect(QuickSearchResult.album(album(1)).item.subtitle == "Album · Accept")
        #expect(QuickSearchResult.playlist(playlist(1)).item.subtitle == "Playlist · Ada")
    }

    @Test func clearingTheQueryDropsTheResults() async {
        let (store, _) = await store()
        store.query = "accept"
        await store.settle()
        store.query = ""
        #expect(store.quickResults.isEmpty)
    }
}
