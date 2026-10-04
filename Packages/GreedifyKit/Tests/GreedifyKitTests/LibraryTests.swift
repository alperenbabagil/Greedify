import Foundation
import Testing
@testable import GreedifyKit

@MainActor
struct LibraryStoreTests {
    func cache() -> DataCache {
        DataCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), limitBytes: 10_000_000)
    }
    func playlist(_ id: String, owner: String = "me", snapshot: String = "s1") -> Playlist {
        Playlist(id: id, name: id, uri: "spotify:playlist:\(id)", images: [], owner: PlaylistOwner(id: owner, displayName: nil),
                 collaborative: false, snapshotId: snapshot, trackCount: 2)
    }

    @Test func loadsAllPlaylistPages() async {
        let api = FakeSpotifyAPI()
        await api.set(playlistPages: [
            Paging(items: [playlist("a")], next: URL(string: "https://n"), offset: 0, limit: 50, total: 2),
            Paging(items: [playlist("b", owner: "other")], next: nil, offset: 1, limit: 50, total: 2),
        ])
        let store = LibraryStore(api: api, cache: cache())
        await store.load()
        #expect(store.playlists.map(\.id) == ["a", "b"])
        #expect(store.editablePlaylists().map(\.id) == ["a"])
    }

    /// A request cancelled with its task (e.g. a superseded load) isn't a network failure: no banner.
    @Test func cancelledRequestIsNotAnError() async {
        let api = FakeSpotifyAPI()
        await api.fail("playlists(", throwing: CancellationError())
        let store = LibraryStore(api: api, cache: cache())
        await store.load()
        #expect(store.lastError == nil)
    }

    // MARK: Refresh

    /// A playlist edited elsewhere: its new snapshot comes with the list, so its songs are fetched again.
    @Test func refreshPicksUpAnEditedPlaylist() async {
        let api = FakeSpotifyAPI()
        await api.set(playlistPages: [Paging(items: [playlist("a")], next: nil, offset: 0, limit: 50, total: 1)])
        await api.set(items: [PlaylistItem(addedAt: nil, track: Fixture.track("t1"))], for: "a")
        let store = LibraryStore(api: api, cache: cache())
        await store.load()
        _ = await store.tracks(for: store.playlists[0])
        await api.set(playlistPages: [Paging(items: [playlist("a", snapshot: "s2")], next: nil, offset: 0, limit: 50, total: 1)])
        await api.set(items: [PlaylistItem(addedAt: nil, track: Fixture.track("t1")), PlaylistItem(addedAt: nil, track: Fixture.track("t2"))], for: "a")
        await store.refresh()
        #expect(store.playlists[0].snapshotId == "s2")
        #expect(await store.tracks(for: store.playlists[0]).map(\.id) == ["t1", "t2"])
    }

    /// Lists already shown start over from their first page; lists never opened cost nothing.
    @Test func refreshReloadsOnlyLoadedLists() async {
        let api = FakeSpotifyAPI()
        await api.set(saved: [SavedTrack(addedAt: nil, track: Fixture.track("t1"))])
        let store = LibraryStore(api: api, cache: cache())
        await store.loadMoreLiked()
        await api.set(saved: [SavedTrack(addedAt: nil, track: Fixture.track("t2")), SavedTrack(addedAt: nil, track: Fixture.track("t1"))])
        await store.refresh()
        #expect(store.likedTracks.map(\.id) == ["t2", "t1"])
        #expect(store.likedTotal == 2)
        let calls = await api.calls
        #expect(!calls.contains { $0.hasPrefix("albums") || $0 == "artists" || $0.hasPrefix("shows") || $0.hasPrefix("savedEpisodes") })
    }

    /// The podcast lists' hour-long cache doesn't hide a show followed elsewhere.
    @Test func refreshSkipsThePodcastCache() async {
        let api = FakeSpotifyAPI()
        let show = { (id: String) in Show(id: id, name: id, uri: "spotify:show:\(id)", images: [], totalEpisodes: nil, description: nil) }
        await api.set(showPages: [Paging(items: [SavedShow(show: show("a"))], next: nil, offset: 0, limit: 50, total: 1)])
        let store = LibraryStore(api: api, cache: cache())
        await store.loadMoreShows()
        await api.set(showPages: [Paging(items: [SavedShow(show: show("b")), SavedShow(show: show("a"))], next: nil, offset: 0, limit: 50, total: 2)])
        await store.refresh()
        #expect(store.shows.map(\.id) == ["b", "a"])
    }

    /// A failed refresh keeps what was shown.
    @Test func failedRefreshKeepsTheLists() async {
        let api = FakeSpotifyAPI()
        await api.set(saved: [SavedTrack(addedAt: nil, track: Fixture.track("t1"))])
        let store = LibraryStore(api: api, cache: cache())
        await store.loadMoreLiked()
        await api.fail("liked(", with: .transport("offline"))
        await store.refresh()
        #expect(store.likedTracks.map(\.id) == ["t1"])
    }

    // MARK: Quota savers

    @Test func userIsCachedForAWeek() async {
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let api = FakeSpotifyAPI()
        let c = cache()
        await LibraryStore(api: api, cache: c, now: { clock.date }).load()
        let second = LibraryStore(api: api, cache: c, now: { clock.date })
        await second.load()
        #expect(second.user?.id == "me")
        #expect(await api.calls.filter { $0 == "me" }.count == 1)          // second launch used the cache
        clock.date = clock.date.addingTimeInterval(LibraryStore.userTTL + 1)
        await LibraryStore(api: api, cache: c, now: { clock.date }).load()
        #expect(await api.calls.filter { $0 == "me" }.count == 2)          // stale: fetched again
    }

    @Test func playlistsStillLoadWhenUserFetchFails() async {
        let api = FakeSpotifyAPI()
        await api.set(playlistPages: [Paging(items: [playlist("a")], next: nil, offset: 0, limit: 50, total: 1)])
        await api.fail("me", with: .rateLimited(retryAfter: 70_000, quotaExceeded: true))
        let store = LibraryStore(api: api, cache: cache())
        await store.load()
        #expect(store.playlists.map(\.id) == ["a"])
    }

    @Test func likeChecksAreRememberedAcrossLaunches() async {
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let api = FakeSpotifyAPI()
        await api.set(contains: [true])
        let c = cache()
        let first = LibraryStore(api: api, cache: c, now: { clock.date })
        await first.refreshLikes(for: [Fixture.track("t1")])
        #expect(first.isLiked(Fixture.track("t1")))
        await first.refreshLikes(for: [Fixture.track("t1")])               // just checked: no request
        let second = LibraryStore(api: api, cache: c, now: { clock.date })
        await second.refreshLikes(for: [Fixture.track("t1")])              // next launch: from disk
        #expect(second.isLiked(Fixture.track("t1")))
        #expect(await api.calls.filter { $0.hasPrefix("contains") }.count == 1)
        clock.date = clock.date.addingTimeInterval(LibraryStore.likesTTL + 1)
        await second.refreshLikes(for: [Fixture.track("t1")])              // stale: asked again
        #expect(await api.calls.filter { $0.hasPrefix("contains") }.count == 2)
    }

    @Test func firstToggleAfterLaunchUsesTheSavedFlag() async {
        let api = FakeSpotifyAPI()
        await api.set(contains: [true])
        let c = cache()
        await LibraryStore(api: api, cache: c).refreshLikes(for: [Fixture.track("t1")])   // saved as liked
        let store = LibraryStore(api: api, cache: c)
        await store.toggleLike(Fixture.track("t1"))         // restores "liked" first, so this unlikes
        await store.refreshLikes(for: [Fixture.track("t1")])
        #expect(!store.isLiked(Fixture.track("t1")))
    }

    @Test func likedSongsPageAndTogglesCountAsChecks() async {
        let api = FakeSpotifyAPI()
        await api.set(saved: [SavedTrack(addedAt: nil, track: Fixture.track("t1"))])
        let store = LibraryStore(api: api, cache: cache())
        await store.loadMoreLiked()
        await store.toggleLike(Fixture.track("t2"))                        // now liked, and we know it
        await store.refreshLikes(for: [Fixture.track("t1"), Fixture.track("t2")])
        #expect(store.isLiked(Fixture.track("t1")) && store.isLiked(Fixture.track("t2")))
        #expect(await api.calls.filter { $0.hasPrefix("contains") }.isEmpty)
    }

    @Test func playlistTracksReusedWhenSnapshotUnchanged() async {
        let api = FakeSpotifyAPI()
        let items = (0..<60).map { PlaylistItem(addedAt: nil, track: Fixture.track("t\($0)")) } + [PlaylistItem(addedAt: nil, track: nil)]
        await api.set(items: items, for: "a")
        let c = cache()
        let first = LibraryStore(api: api, cache: c)
        #expect(await first.tracks(for: playlist("a")).count == 60)       // 2 pages, nil item dropped
        let second = LibraryStore(api: api, cache: c)
        #expect(await second.tracks(for: playlist("a")).count == 60)
        #expect(await api.calls.filter { $0.hasPrefix("items(a") }.count == 2) // not refetched
        _ = await second.tracks(for: playlist("a", snapshot: "s2"))
        #expect(await api.calls.filter { $0.hasPrefix("items(a") }.count == 4) // snapshot changed → refetch
    }

    @Test func toggleLikeOptimisticAndRollback() async {
        let api = FakeSpotifyAPI()
        let store = LibraryStore(api: api, cache: cache())
        let t = Fixture.track("x")
        await store.toggleLike(t)
        #expect(store.isLiked(t))
        #expect(await api.calls.contains("save(spotify:track:x)"))
        await api.enqueue(.transport("offline"))
        await store.toggleLike(t)
        #expect(store.isLiked(t)) // failed unlike rolled back
        #expect(store.lastError == .transport("offline"))
    }

    @Test func refreshLikesMapsContains() async {
        let api = FakeSpotifyAPI()
        await api.set(contains: [true])
        let store = LibraryStore(api: api, cache: cache())
        await store.refreshLikes(for: [Fixture.track("y")])
        #expect(store.isLiked(Fixture.track("y")))
    }

    @Test func addRemoveUpdateSnapshot() async {
        let api = FakeSpotifyAPI()
        await api.set(playlistPages: [Paging(items: [playlist("a")], next: nil, offset: 0, limit: 50, total: 1)])
        let store = LibraryStore(api: api, cache: cache())
        await store.load()
        let t = Fixture.track("z")
        await store.add(t, to: store.playlists[0])
        #expect(store.playlists[0].snapshotId == "s2")
        #expect(store.playlists[0].trackCount == 3)
        await api.set(contains: [])
        await store.remove(t, from: store.playlists[0])
        #expect(await api.calls.contains("remove(a,spotify:track:z,s2)"))
        #expect(store.playlists[0].trackCount == 2)
    }

    @Test func addingToUnloadedPlaylistKeepsItsFullTrackList() async {
        let api = FakeSpotifyAPI()
        await api.set(items: (0..<3).map { PlaylistItem(addedAt: nil, track: Fixture.track("t\($0)")) }, for: "a")
        await api.set(playlistPages: [Paging(items: [playlist("a")], next: nil, offset: 0, limit: 50, total: 1)])
        let store = LibraryStore(api: api, cache: cache())
        await store.load()
        await store.add(Fixture.track("new"), to: store.playlists[0])
        let tracks = await store.tracks(for: store.playlists[0])
        #expect(tracks.count == 3) // refetched from Spotify, not a cached one-song list
    }

    @Test func partialPlaylistLoadIsNotCached() async {
        let api = FakeSpotifyAPI()
        await api.set(items: (0..<60).map { PlaylistItem(addedAt: nil, track: Fixture.track("t\($0)")) }, for: "a")
        await api.set(failItemsAtOffset: 50)
        let c = cache()
        _ = await LibraryStore(api: api, cache: c).tracks(for: playlist("a"))
        await api.set(failItemsAtOffset: nil)
        let tracks = await LibraryStore(api: api, cache: c).tracks(for: playlist("a"))
        #expect(tracks.count == 60)
    }

    @Test func likingBeforeLoadingDoesNotCapLikedSongs() async {
        let api = FakeSpotifyAPI()
        await api.set(saved: (0..<5).map { SavedTrack(addedAt: nil, track: Fixture.track("s\($0)")) })
        let store = LibraryStore(api: api, cache: cache())
        await store.toggleLike(Fixture.track("x"))
        await store.loadMoreLiked()
        #expect(store.likedTracks.count == 5)
        #expect(store.likedTotal == 5)
    }

    @Test func forbiddenEditRecordsError() async {
        let api = FakeSpotifyAPI()
        await api.enqueue(.forbidden("not owner"))
        let store = LibraryStore(api: api, cache: cache())
        await store.add(Fixture.track("q"), to: playlist("theirs", owner: "other"))
        #expect(store.lastError == .forbidden("not owner"))
    }

    @Test func createPlaylistAddsTrack() async {
        let api = FakeSpotifyAPI()
        let store = LibraryStore(api: api, cache: cache())
        let created = await store.createPlaylist(named: "Fresh", adding: Fixture.track("n"))
        #expect(created?.id == "new")
        #expect(store.playlists.first?.id == "new")
        let calls = await api.calls
        #expect(calls.contains("create(Fresh,false)"))
        #expect(calls.contains("add(new,spotify:track:n)"))
    }
}

struct MixLinkTests {
    @Test func parsesLinks() {
        let id = "37i9dQZF1E39vTG3GurFPW"
        #expect(MixLink.uri(fromLink: "https://open.spotify.com/playlist/\(id)?si=abc") == "spotify:playlist:\(id)")
        #expect(MixLink.uri(fromLink: "  https://open.spotify.com/intl-tr/playlist/\(id)  ") == "spotify:playlist:\(id)")
        #expect(MixLink.uri(fromLink: "spotify:playlist:\(id)") == "spotify:playlist:\(id)")
        #expect(MixLink.uri(fromLink: "https://open.spotify.com/album/\(id)") == nil)
        #expect(MixLink.uri(fromLink: "https://evil.com/playlist/\(id)") == nil)
        #expect(MixLink.uri(fromLink: "hello") == nil)
    }
}

@MainActor
struct SearchStoreTests {
    @Test func debouncesAndKeepsLatestQuery() async {
        let api = FakeSpotifyAPI()
        await api.set(search: SearchResults(tracks: Paging(items: [Fixture.track], next: URL(string: "https://n"), offset: 0, limit: 10, total: 30),
                                            albums: nil, artists: nil, playlists: nil))
        let store = SearchStore(api: api, debounce: .milliseconds(50))
        store.query = "p"
        store.query = "pa"
        store.query = "paper"
        await store.settle()
        let searches = await api.calls.filter { $0.hasPrefix("search") }
        #expect(searches == ["search(paper,track+album+artist+playlist+show+episode,0)"])
        #expect(store.tracks.count == 1)
        #expect(store.hasMore[.track] == true)
    }

    @Test func showMoreUsesOffset() async {
        let api = FakeSpotifyAPI()
        await api.set(search: SearchResults(tracks: Paging(items: [Fixture.track], next: nil, offset: 0, limit: 10, total: 1),
                                            albums: nil, artists: nil, playlists: nil))
        let store = SearchStore(api: api, debounce: .milliseconds(1))
        store.query = "paper"
        await store.settle()
        await store.showMore(.track)
        #expect(await api.calls.last == "search(paper,track,1)")
        #expect(store.tracks.count == 2)
        #expect(store.hasMore[.track] == false)
    }

    @Test func emptyQueryClearsResults() async {
        let api = FakeSpotifyAPI()
        await api.set(search: SearchResults(tracks: Paging(items: [Fixture.track], next: nil, offset: 0, limit: 10, total: 1),
                                            albums: nil, artists: nil, playlists: nil))
        let store = SearchStore(api: api, debounce: .milliseconds(1))
        store.query = "x"
        await store.settle()
        store.query = "   "
        #expect(store.tracks.isEmpty)
    }
}

/// An artist's popular songs: top-tracks is gone in development mode (2026), so they come from search.
@MainActor
struct PopularTracksTests {
    let artist = Artist(id: "ar1", name: "Accept", uri: "spotify:artist:ar1", images: nil)

    func song(_ id: String, _ name: String, by artists: [String]) -> Track {
        Track(id: id, name: name, uri: "spotify:track:\(id)", durationMs: 1000,
              artists: artists.map { ArtistRef(id: $0, name: $0, uri: "spotify:artist:\($0)") }, album: nil)
    }

    func store(_ api: FakeSpotifyAPI, clock: TestNow) -> LibraryStore {
        LibraryStore(api: api, cache: LibraryStoreTests().cache(), now: { clock.date })
    }

    @Test func searchesTheArtistsSongsAndDropsOtherArtists() async {
        let api = FakeSpotifyAPI()
        await api.set(search: SearchResults(tracks: Paging(items: [
            song("1", "Balls to the Wall", by: ["ar1"]),
            song("2", "Guest Spot", by: ["other", "ar1"]),          // a feature: still theirs
            song("3", "Balls To The Wall", by: ["ar1"]),            // the same song on another release
            song("4", "Fast as a Shark", by: ["ar1", "other"]),
            song("5", "Accepted", by: ["acceptable"]),              // the name filter is fuzzy: another artist
        ], next: nil, offset: 0, limit: 10, total: 5), albums: nil, artists: nil, playlists: nil))
        let library = store(api, clock: TestNow(Date(timeIntervalSince1970: 0)))
        let tracks = await library.popularTracks(for: artist)
        #expect(tracks.map(\.id) == ["1", "2", "4"])
        #expect(await api.calls == [#"search(artist:"Accept",track,0)"#])
    }

    @Test func cachedForADay() async {
        let api = FakeSpotifyAPI()
        await api.set(search: SearchResults(tracks: Paging(items: [song("1", "A", by: ["ar1"])], next: nil, offset: 0, limit: 10, total: 1),
                                            albums: nil, artists: nil, playlists: nil))
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let library = store(api, clock: clock)
        _ = await library.popularTracks(for: artist)
        clock.date = clock.date.addingTimeInterval(23 * 3600)
        #expect(await library.popularTracks(for: artist).map(\.id) == ["1"])
        #expect(await api.calls.count == 1)
        clock.date = clock.date.addingTimeInterval(2 * 3600)
        _ = await library.popularTracks(for: artist)
        #expect(await api.calls.count == 2)
    }

    @Test func quotesInTheNameDontBreakTheQuery() async {
        let api = FakeSpotifyAPI()
        let library = store(api, clock: TestNow(Date(timeIntervalSince1970: 0)))
        _ = await library.popularTracks(for: Artist(id: "x", name: #"The "Band""#, uri: "spotify:artist:x", images: nil))
        #expect(await api.calls == [#"search(artist:"The Band",track,0)"#])
    }
}
