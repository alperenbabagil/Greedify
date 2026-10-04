import Foundation
import Testing
@testable import GreedifyKit

extension Fixture {
    static func api(_ transport: StubTransport, tokens: Tokens? = freshTokens) -> (LiveSpotifyAPI, InMemoryTokenStore) {
        let store = InMemoryTokenStore(tokens)
        let auth = AuthService(config: AuthConfig(clientID: "cid", redirectURI: URL(string: "greedify://callback")!), transport: transport)
        return (LiveSpotifyAPI(auth: auth, tokens: store, transport: transport), store)
    }
}

struct LiveSpotifyAPITests {
    @Test func sendsBearerAndDecodesPlaybackState() async throws {
        let stub = StubTransport { _ in (200, #"{"is_playing":true,"progress_ms":1000,"item":\#(Fixture.trackJSON)}"#, [:]) }
        let (api, _) = Fixture.api(stub)
        let state = try await api.playbackState()
        #expect(state?.item?.id == "t1")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer AT")
        #expect(stub.requests[0].url?.path == "/v1/me/player")
    }

    @Test func noContentMeansNothingPlaying() async throws {
        let (api, _) = Fixture.api(StubTransport { _ in (204, "", [:]) })
        #expect(try await api.playbackState() == nil)
    }

    @Test func refreshesExpiredTokenBeforeRequest() async throws {
        let stub = StubTransport { req in
            if req.url?.host == "accounts.spotify.com" { return (200, #"{"access_token":"NEW","expires_in":3600}"#, [:]) }
            return (200, #"{"id":"me","display_name":"Me"}"#, [:])
        }
        let (api, store) = Fixture.api(stub, tokens: Fixture.expiredTokens)
        _ = try await api.currentUser()
        #expect(stub.requests.map { $0.url!.host! } == ["accounts.spotify.com", "api.spotify.com"])
        #expect(stub.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer NEW")
        #expect(store.load()?.accessToken == "NEW")
    }

    @Test func retriesOnceAfter401() async throws {
        let stub = StubTransport { req in
            if req.url?.host == "accounts.spotify.com" { return (200, #"{"access_token":"NEW","expires_in":3600}"#, [:]) }
            let auth = req.value(forHTTPHeaderField: "Authorization")
            return auth == "Bearer NEW" ? (200, #"{"id":"me"}"#, [:]) : (401, "", [:])
        }
        let (api, _) = Fixture.api(stub)
        #expect(try await api.currentUser().id == "me")
        #expect(stub.requests.count == 3)
    }

    @Test func revokedRefreshTokenClearsStoreAndThrowsReauth() async {
        let stub = StubTransport { req in
            req.url?.host == "accounts.spotify.com" ? (400, #"{"error":"invalid_grant"}"#, [:]) : (200, "{}", [:])
        }
        let (api, store) = Fixture.api(stub, tokens: Fixture.expiredTokens)
        await #expect(throws: SpotifyError.reauthRequired) { try await api.currentUser() }
        #expect(store.load() == nil)
    }

    @Test func notLoggedIn() async {
        let (api, _) = Fixture.api(StubTransport { _ in (200, "{}", [:]) }, tokens: nil)
        await #expect(throws: SpotifyError.notAuthenticated) { try await api.pause() }
    }

    @Test func rateLimitSetsBackoffAndFailsFast() async {
        let stub = StubTransport { _ in (429, #"{"error":{"status":429,"reason":"QUOTA_EXCEEDED"}}"#, ["Retry-After": "30"]) }
        let (api, _) = Fixture.api(stub)
        await #expect(throws: SpotifyError.rateLimited(retryAfter: 30, quotaExceeded: true)) { try await api.next() }
        await #expect(throws: SpotifyError.self) { try await api.next() }
        #expect(stub.requests.count == 1) // second call never hit the network
        #expect(await api.isBackingOff())
    }

    /// Spotify's daily quota is per endpoint (`/me` spent while `/me/player` still answers): a quota back-off
    /// must not stop playback control for the rest of the day.
    @Test func quotaBackoffOnlyBlocksThatEndpoint() async throws {
        let stub = StubTransport { request in
            request.url!.path.hasSuffix("/v1/me")
                ? (429, #"{"error":{"status":429,"reason":"QUOTA_EXCEEDED"}}"#, ["Retry-After": "70000"])
                : (204, "", [:])
        }
        let (api, _) = Fixture.api(stub)
        await #expect(throws: SpotifyError.rateLimited(retryAfter: 70000, quotaExceeded: true)) { try await api.currentUser() }
        try await api.next()                                        // other endpoints still go out
        await #expect(throws: SpotifyError.self) { try await api.currentUser() }
        #expect(stub.requests.count == 2)                           // the blocked one never hit the network again
    }

    @Test func plainRateLimitBlocksEverything() async {
        let stub = StubTransport { _ in (429, #"{"error":{"status":429}}"#, ["Retry-After": "30"]) }
        let (api, _) = Fixture.api(stub)
        await #expect(throws: SpotifyError.rateLimited(retryAfter: 30, quotaExceeded: false)) { try await api.currentUser() }
        await #expect(throws: SpotifyError.self) { try await api.next() }
        #expect(stub.requests.count == 1)
    }

    @Test func noActiveDeviceMapped() async {
        let stub = StubTransport { _ in (404, #"{"error":{"status":404,"message":"x","reason":"NO_ACTIVE_DEVICE"}}"#, [:]) }
        let (api, _) = Fixture.api(stub)
        await #expect(throws: SpotifyError.noActiveDevice) { try await api.play(.resume, deviceID: nil) }
    }

    @Test func playSendsDeviceAndBody() async throws {
        let stub = StubTransport { _ in (204, "", [:]) }
        let (api, _) = Fixture.api(stub)
        try await api.play(.context("spotify:playlist:p"), deviceID: "dev1")
        let r = stub.requests[0]
        #expect(r.httpMethod == "PUT")
        #expect(r.query("device_id") == "dev1")
        #expect(r.bodyJSON["context_uri"] as? String == "spotify:playlist:p")
    }

    @Test func libraryEndpointsUseURIsQueryInChunksOf40() async throws {
        let stub = StubTransport { _ in (200, "", [:]) }
        let (api, _) = Fixture.api(stub)
        let uris = (0..<45).map { "spotify:track:\($0)" }
        try await api.saveToLibrary(uris: uris)
        #expect(stub.requests.count == 2)
        #expect(stub.requests[0].url?.path == "/v1/me/library")
        #expect(stub.requests[0].query("uris")?.split(separator: ",").count == 40)
        #expect(stub.requests[1].query("uris")?.split(separator: ",").count == 5)
    }

    @Test func removeFromPlaylistBody() async throws {
        let stub = StubTransport { _ in (200, #"{"snapshot_id":"s9"}"#, [:]) }
        let (api, _) = Fixture.api(stub)
        let snap = try await api.removeFromPlaylist(id: "p", uris: ["spotify:track:x"], snapshotID: "s1")
        #expect(snap == "s9")
        let body = stub.requests[0].bodyJSON
        #expect((body["items"] as? [[String: String]])?.first?["uri"] == "spotify:track:x")
        #expect(body["snapshot_id"] as? String == "s1")
        #expect(stub.requests[0].url?.path == "/v1/playlists/p/items")
    }

    @Test func createPlaylistUsesMePlaylists() async throws {
        let stub = StubTransport { _ in (201, Fixture.playlistJSON(id: "new"), [:]) }
        let (api, _) = Fixture.api(stub)
        let p = try await api.createPlaylist(name: "Fresh", isPublic: false)
        #expect(p.id == "new")
        #expect(stub.requests[0].url?.path == "/v1/me/playlists")
        #expect(stub.requests[0].bodyJSON["public"] as? Bool == false)
    }

    @Test func searchCapsLimitAt10() async throws {
        let stub = StubTransport { _ in (200, "{}", [:]) }
        let (api, _) = Fixture.api(stub)
        _ = try await api.search("neon", types: [.track, .album], offset: 10, limit: 50)
        let r = stub.requests[0]
        #expect(r.query("limit") == "10")
        #expect(r.query("type") == "track,album")
        #expect(r.query("offset") == "10")
    }
}

extension LiveSpotifyAPITests {
    @Test func artistByID() async throws {
        let stub = StubTransport { _ in
            (200, #"{"id":"ar1","name":"The Quiet Harbor","uri":"spotify:artist:ar1","images":[{"url":"https://i/a.jpg","width":640,"height":640}]}"#, [:])
        }
        let (api, _) = Fixture.api(stub)
        let artist = try await api.artist(id: "ar1")
        #expect(artist.images?.first?.url.absoluteString == "https://i/a.jpg")
        #expect(stub.requests[0].url?.path == "/v1/artists/ar1")
    }
}

extension LiveSpotifyAPITests {
    /// Development mode (2026): an artist's albums take at most 10 per page; more is a 400.
    @Test func artistAlbumsCapsLimitAt10() async throws {
        let stub = StubTransport { _ in (200, #"{"items":[],"offset":0,"limit":10,"total":0}"#, [:]) }
        let (api, _) = Fixture.api(stub)
        _ = try await api.artistAlbums(id: "ar1", offset: 20, limit: 50)
        #expect(stub.requests[0].query("limit") == "10")
        #expect(stub.requests[0].query("offset") == "20")
    }
}
