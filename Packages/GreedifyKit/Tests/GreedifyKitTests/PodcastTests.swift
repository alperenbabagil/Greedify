import Foundation
import Testing
@testable import GreedifyKit

enum PodcastFixture {
    static let showJSON = #"{"id":"s1","name":"The Show","uri":"spotify:show:s1","images":[{"url":"https://i/s.jpg","width":640,"height":640}],"total_episodes":120,"description":"About things"}"#
    static func episodeJSON(_ id: String = "e1", resumeMs: Int = 120_000, fullyPlayed: Bool = false, show: Bool = true) -> String {
        #"{"type":"episode","id":"\#(id)","name":"Episode \#(id)","uri":"spotify:episode:\#(id)","duration_ms":3000000,"release_date":"2026-09-28","is_playable":true,"images":[{"url":"https://i/\#(id).jpg","width":640,"height":640}],"resume_point":{"fully_played":\#(fullyPlayed),"resume_position_ms":\#(resumeMs)}"#
            + (show ? #","show":\#(showJSON)}"# : "}")
    }
    static func episode(_ id: String = "e1", resumeMs: Int = 120_000, fullyPlayed: Bool = false) -> Track {
        try! SpotifyJSON.decoder.decode(Track.self, from: Data(episodeJSON(id, resumeMs: resumeMs, fullyPlayed: fullyPlayed).utf8))
    }
    static let showRef = ShowRef(id: "s1", name: "The Show", uri: "spotify:show:s1", images: [])
}

struct EpisodeModelTests {
    @Test func anEpisodeDecodesAsATrackWithItsShow() throws {
        let json = #"{"is_playing":true,"progress_ms":5,"item":\#(PodcastFixture.episodeJSON())}"#
        let item = try #require(try SpotifyJSON.decoder.decode(PlaybackState.self, from: Data(json.utf8)).item)
        #expect(item.isEpisode && item.kind == .episode)
        #expect(item.artistLine == "The Show")
        #expect(item.album?.name == "The Show" && item.album?.images.first?.url.absoluteString == "https://i/e1.jpg")
        #expect(item.show?.id == "s1" && item.releaseDate == "2026-09-28" && item.isPlayable == true)
        #expect(item.resumePoint == ResumePoint(fullyPlayed: false, resumePositionMs: 120_000))
        #expect(item.startPositionMs == 120_000)
    }

    /// Review focus 2: a finished episode starts over.
    @Test func aFullyPlayedEpisodeStartsAtZero() {
        #expect(PodcastFixture.episode(fullyPlayed: true).startPositionMs == 0)
        #expect(Fixture.track.startPositionMs == nil)                   // no resume point: let Spotify decide
    }

    @Test func queueAndPlaylistsKeepEpisodes() throws {
        let queue = #"{"currently_playing":\#(PodcastFixture.episodeJSON()),"queue":[\#(Fixture.trackJSON),\#(PodcastFixture.episodeJSON("e2"))]}"#
        let q = try SpotifyJSON.decoder.decode(QueueResponse.self, from: Data(queue.utf8))
        #expect(q.currentlyPlaying?.isEpisode == true && q.queue.map(\.id) == ["t1", "e2"])
        let item = try SpotifyJSON.decoder.decode(PlaylistItem.self, from: Data(#"{"added_at":"x","item":\#(PodcastFixture.episodeJSON())}"#.utf8))
        #expect(item.track?.isEpisode == true)
    }

    @Test func aShowsOwnEpisodeListTakesTheShow() throws {
        let bare = try SpotifyJSON.decoder.decode(Track.self, from: Data(PodcastFixture.episodeJSON(show: false).utf8))
        let inShow = bare.inShow(PodcastFixture.showRef)
        #expect(inShow.show == PodcastFixture.showRef && inShow.artistLine == "The Show" && inShow.isEpisode)
        #expect(inShow.album?.images.first?.url.absoluteString == "https://i/e1.jpg")   // the episode's own cover wins
        #expect(inShow.resumePoint == bare.resumePoint)
    }

    @Test func episodesSurviveOurOwnEncoding() throws {
        let episode = PodcastFixture.episode()
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(episode))
        #expect(back == episode)
    }

    /// Review focus 4: last-played data saved before episodes existed restores as a song.
    @Test func oldSavedTracksHaveNoKind() throws {
        let old = #"{"id":"t","name":"n","uri":"spotify:track:t","durationMs":1,"artists":[{"name":"A","uri":""}]}"#
        let track = try JSONDecoder().decode(Track.self, from: Data(old.utf8))
        #expect(track.kind == .track && track.show == nil && track.album == nil)
    }

    @Test func withoutAResumePointNoPositionIsSent() {
        #expect(PlayRequest.episode("spotify:episode:e1", at: nil).positionMs == nil)
        #expect(PlayRequest.episode("spotify:episode:e1", at: nil).jsonBody?["position_ms"] == nil)
    }

    @Test func showsDecodeAndPlayRequestForAnEpisode() throws {
        let show = try SpotifyJSON.decoder.decode(Show.self, from: Data(PodcastFixture.showJSON.utf8))
        #expect(show.totalEpisodes == 120 && show.ref.id == "s1" && Show(ref: show.ref)?.id == "s1")
        #expect(Show(ref: ShowRef(id: nil, name: "x", uri: "", images: [])) == nil)
        let request = PlayRequest.episode("spotify:episode:e1", at: 120_000)
        #expect(request.uris == ["spotify:episode:e1"] && request.positionMs == 120_000 && request.contextURI == nil)
    }
}

struct PodcastAPITests {
    func api(_ body: String = #"{"items":[],"offset":0,"limit":50,"total":0}"#) -> (LiveSpotifyAPI, StubTransport) {
        let stub = StubTransport { _ in (200, body, [:]) }
        return (Fixture.api(stub).0, stub)
    }

    @Test func podcastListsUseTheirEndpointsAndCapAt50() async throws {
        let (api, stub) = api()
        _ = try await api.savedShows(offset: 50, limit: 80)
        _ = try await api.showEpisodes(id: "s1", offset: 0, limit: 50)
        _ = try await api.savedEpisodes(offset: 0, limit: 20)
        #expect(stub.requests.map { $0.url!.path } == ["/v1/me/shows", "/v1/shows/s1/episodes", "/v1/me/episodes"])
        #expect(stub.requests[0].query("limit") == "50" && stub.requests[0].query("offset") == "50")
        #expect(stub.requests[2].query("limit") == "20")
    }

    @Test func aShowByID() async throws {
        let (api, stub) = api(PodcastFixture.showJSON)
        let show = try await api.show(id: "s1")
        #expect(show.name == "The Show" && stub.requests[0].url?.path == "/v1/shows/s1")
    }

    @Test func thePlayerAndPlaylistsAskForEpisodes() async throws {
        let (api, stub) = api(#"{"is_playing":false}"#)
        _ = try await api.playbackState()
        #expect(stub.requests[0].query("additional_types") == "episode")
        let (api2, stub2) = self.api()
        _ = try await api2.playlistItems(id: "p", offset: 0, limit: 50)
        #expect(stub2.requests[0].query("additional_types") == "track,episode")
    }
}

@MainActor
struct PodcastScopeTests {
    @Test func theLoginAsksForPlaybackPositions() {
        #expect(AuthConfig.defaultScopes.contains(AuthConfig.playbackPositionScope))
        #expect(AuthConfig.playbackPositionScope == "user-read-playback-position")
    }

    @Test func tokensKnowTheirScopes() {
        let old = Tokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, scope: "user-library-read user-read-playback-state")
        #expect(!old.hasScope(AuthConfig.playbackPositionScope) && old.hasScope("user-library-read"))
        let new = Tokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture, scope: "user-read-playback-position user-library-read")
        #expect(new.hasScope(AuthConfig.playbackPositionScope))
    }

    @Test func theNoticeDismissalIsRemembered() {
        let d = UserDefaults(suiteName: "podcast-\(UUID().uuidString)")!
        let s = AppSettings(defaults: d, hostName: "Mac")
        #expect(!s.podcastNoticeDismissed)
        s.podcastNoticeDismissed = true
        #expect(AppSettings(defaults: d, hostName: "Mac").podcastNoticeDismissed)
    }
}

@MainActor
struct PodcastLibraryTests {
    func store(_ api: FakeSpotifyAPI, clock: TestNow) -> LibraryStore {
        let s = LibraryStore(api: api, cache: LibraryStoreTests().cache(), now: { clock.date })
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        s.calendar = utc
        return s
    }
    let show = try! SpotifyJSON.decoder.decode(Show.self, from: Data(PodcastFixture.showJSON.utf8))
    func page<T>(_ items: [T], total: Int) -> Paging<T> { Paging(items: items, next: nil, offset: 0, limit: 50, total: total) }

    @Test func showsPageAndCacheForAnHour() async {
        let api = FakeSpotifyAPI()
        await api.set(showPages: [page([SavedShow(show: show)], total: 1)])
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let cache = LibraryStoreTests().cache()
        let first = LibraryStore(api: api, cache: cache, now: { clock.date })
        await first.loadMoreShows()
        #expect(first.shows.map(\.id) == ["s1"])
        clock.date = clock.date.addingTimeInterval(30 * 60)
        let second = LibraryStore(api: api, cache: cache, now: { clock.date })
        await second.loadMoreShows()
        #expect(second.shows.map(\.id) == ["s1"])
        #expect(await api.calls.filter { $0.hasPrefix("shows(") }.count == 1)
        clock.date = clock.date.addingTimeInterval(31 * 60)
        let third = LibraryStore(api: api, cache: cache, now: { clock.date })
        await third.loadMoreShows()
        #expect(await api.calls.filter { $0.hasPrefix("shows(") }.count == 2)
    }

    @Test func aShowsEpisodesTakeTheShowAndLastUntilMidnight() async {
        let api = FakeSpotifyAPI()
        let bare = try! SpotifyJSON.decoder.decode(Track.self, from: Data(PodcastFixture.episodeJSON(show: false).utf8))
        await api.set(episodePages: [page([bare], total: 2), page([bare], total: 2)], for: "s1")
        let clock = TestNow(Date(timeIntervalSince1970: 3600))            // 01:00 UTC
        let library = store(api, clock: clock)
        let episodes = await library.episodes(of: show.ref)
        #expect(episodes.first?.show?.id == "s1" && episodes.first?.artistLine == "The Show")
        _ = await library.episodes(of: show.ref)                           // in memory: no request
        #expect(await api.calls.filter { $0.hasPrefix("episodes(") }.count == 1)
        await library.loadMoreEpisodes(of: show.ref)
        #expect(await api.calls.last == "episodes(s1,1)")
        #expect(library.showEpisodes["s1"]?.count == 2)
    }

    @Test func tomorrowFetchesTheShowAgain() async {
        let api = FakeSpotifyAPI()
        let cache = LibraryStoreTests().cache()
        let clock = TestNow(Date(timeIntervalSince1970: 3600))
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let today = LibraryStore(api: api, cache: cache, now: { clock.date }); today.calendar = utc
        _ = await today.episodes(of: show.ref)
        clock.date = clock.date.addingTimeInterval(10 * 3600)               // 11:00, same day: the disk cache
        let later = LibraryStore(api: api, cache: cache, now: { clock.date }); later.calendar = utc
        _ = await later.episodes(of: show.ref)
        #expect(await api.calls.filter { $0.hasPrefix("episodes(") }.count == 1)
        clock.date = clock.date.addingTimeInterval(14 * 3600)               // 01:00 the next day
        let tomorrow = LibraryStore(api: api, cache: cache, now: { clock.date }); tomorrow.calendar = utc
        _ = await tomorrow.episodes(of: show.ref)
        #expect(await api.calls.filter { $0.hasPrefix("episodes(") }.count == 2)
    }

    @Test func followingAShowGoesThroughTheLibrary() async {
        let api = FakeSpotifyAPI()
        let library = store(api, clock: TestNow(Date(timeIntervalSince1970: 0)))
        await library.loadMoreShows()                                       // loaded (empty)
        await library.toggleFollow(show)
        #expect(library.isFollowing(show) && library.shows.map(\.id) == ["s1"])
        #expect(await api.calls.contains("save(spotify:show:s1)"))
        await library.toggleFollow(show)
        #expect(!library.isFollowing(show) && library.shows.isEmpty)
    }

    /// Review focus 3: saving an episode never touches Liked Songs.
    @Test func savingAnEpisodeIsNotLikingASong() async {
        let api = FakeSpotifyAPI()
        let library = store(api, clock: TestNow(Date(timeIntervalSince1970: 0)))
        await library.loadMoreLiked()
        await library.loadMoreSavedEpisodes()
        let episode = PodcastFixture.episode()
        await library.toggleLike(episode)
        #expect(library.isLiked(episode))
        #expect(library.likedTracks.isEmpty && library.likedTotal == 0)
        #expect(library.savedEpisodes.map(\.id) == ["e1"])
        #expect(await api.calls.contains("save(spotify:episode:e1)"))
    }
}

@MainActor
struct PodcastSearchTests {
    @Test func searchReturnsShowsAndEpisodes() async throws {
        let api = FakeSpotifyAPI()
        let show = try SpotifyJSON.decoder.decode(Show.self, from: Data(PodcastFixture.showJSON.utf8))
        var results = SearchResults(tracks: nil, albums: nil, artists: nil, playlists: nil)
        results.shows = Paging(items: [show], next: URL(string: "https://n"), offset: 0, limit: 10, total: 30)
        results.episodes = Paging(items: [PodcastFixture.episode()], next: nil, offset: 0, limit: 10, total: 1)
        await api.set(search: results)
        let search = SearchStore(api: api, debounce: .zero)
        search.query = "things"
        await search.settle()
        #expect(search.shows.map(\.id) == ["s1"] && search.episodes.map(\.id) == ["e1"])
        #expect(search.hasMore[.show] == true && search.hasMore[.episode] == false)
        #expect(await api.calls.first == "search(things,track+album+artist+playlist+show+episode,0)")
        await search.showMore(.show)
        #expect(await api.calls.last == "search(things,show,1)")
    }
}

@MainActor
struct PodcastPagingTests {
    /// Final review 7: an old episode beyond the first page still gets its follower, within 4 pages.
    @Test func thePlayingEpisodeIsLookedForUpToFourPages() async {
        let api = FakeSpotifyAPI()
        func page(_ ids: [String], offset: Int) -> Paging<Track> {
            Paging(items: ids.map { PlayerStoreTests.episode($0) }, next: nil, offset: offset, limit: 50, total: 1000)
        }
        await api.set(episodePages: [page(["n1"], offset: 0), page(["n2"], offset: 1), page(["old"], offset: 2), page(["x"], offset: 3), page(["y"], offset: 4)], for: "s1")
        let library = LibraryStore(api: api, cache: LibraryStoreTests().cache())
        let ref = ShowRef(id: "s1", name: "S", uri: "spotify:show:s1", images: [])
        let list = await library.episodes(of: ref, containing: "old")
        #expect(list.map(\.id) == ["n1", "n2", "old"])
        let missing = await library.episodes(of: ref, containing: "never")
        #expect(missing.count <= LibraryStore.maxEpisodesLookedThrough)
        #expect(await api.calls.filter { $0.hasPrefix("episodes(") }.count <= 5)
    }
}
