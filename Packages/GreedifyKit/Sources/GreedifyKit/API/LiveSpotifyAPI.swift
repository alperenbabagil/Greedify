import Foundation
import os

private let log = Logger(subsystem: "com.alperen.greedify", category: "api")

/// The real Web API client. An actor so token refresh happens at most once at a time.
public actor LiveSpotifyAPI: SpotifyAPI {
    static let base = URL(string: "https://api.spotify.com/v1")!

    let auth: AuthService
    let tokens: TokenStore
    let transport: HTTPTransport
    let now: @Sendable () -> Date
    /// Where failed requests are recorded (Settings → Diagnostics).
    let errors: ErrorLog
    private var refreshTask: Task<Tokens, Error>?
    /// While set and in the future, every request fails fast with `.rateLimited` (Spotify's rolling rate limit is app-wide).
    private(set) var backoffUntil: Date?
    /// Daily-quota back-offs, per path: the quota is per endpoint and lasts hours, so one spent endpoint
    /// (e.g. `/me`) mustn't stop playback control.
    private var quotaUntil: [String: Date] = [:]

    public init(auth: AuthService, tokens: TokenStore, transport: HTTPTransport,
                now: @escaping @Sendable () -> Date = Date.init, errors: ErrorLog = .shared) {
        self.auth = auth; self.tokens = tokens; self.transport = transport; self.now = now; self.errors = errors
    }

    // MARK: Request pipeline

    enum Method: String { case get = "GET", put = "PUT", post = "POST", delete = "DELETE" }

    func makeURL(_ path: String, _ query: [String: String?]) -> URL {
        var c = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }.sorted { $0.name < $1.name }
        c.queryItems = items.isEmpty ? nil : items
        // `+` would be read as a space by some servers; Spotify URIs use `:` which is fine.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    private func validAccessToken() async throws -> String {
        guard let current = tokens.load() else { throw SpotifyError.notAuthenticated }
        if !current.isExpired(now: now()) { return current.accessToken }
        return try await refreshed(current).accessToken
    }

    private func refreshed(_ current: Tokens) async throws -> Tokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { [auth] in try await auth.refresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            tokens.save(fresh)
            return fresh
        } catch SpotifyError.reauthRequired {
            errors.record("token refresh: the refresh token was rejected; log in again", category: "api")
            tokens.clear()
            throw SpotifyError.reauthRequired
        }
    }

    /// Sends a request; on 401 refreshes once and retries; maps errors to `SpotifyError`.
    func send(_ method: Method, _ path: String, query: [String: String?] = [:], json: Any? = nil) async throws -> Data? {
        if let until = backoffUntil, until > now() {
            throw SpotifyError.rateLimited(retryAfter: until.timeIntervalSince(now()), quotaExceeded: false)
        }
        if let until = quotaUntil[path], until > now() {
            throw SpotifyError.rateLimited(retryAfter: until.timeIntervalSince(now()), quotaExceeded: true)
        }
        var attempt = 0
        while true {
            var request = URLRequest(url: makeURL(path, query))
            request.httpMethod = method.rawValue
            request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
            if let json {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: json)
            } else if method != .get {
                request.setValue("0", forHTTPHeaderField: "Content-Length")
            }
            let data: Data, http: HTTPURLResponse
            do { (data, http) = try await transport.send(request) } catch {
                if error is CancellationError { throw error }
                errors.record("\(method.rawValue) \(path): \(error)", category: "api")
                throw error
            }
            log.info("\(method.rawValue, privacy: .public) \(path, privacy: .public) → \(http.statusCode)")
            switch http.statusCode {
            case 204: return nil
            case 200..<300: return data.isEmpty ? nil : data
            case 401 where attempt == 0:
                attempt += 1
                if let current = tokens.load() { _ = try await refreshed(current) } else { throw SpotifyError.notAuthenticated }
            case 401:
                errors.record("\(method.rawValue) \(path) → 401 after a token refresh", category: "api")
                throw SpotifyError.reauthRequired
            default:
                let error = SpotifyError.from(status: http.statusCode, headers: http.allHeaderFields, body: data)
                errors.record("\(method.rawValue) \(path) → \(http.statusCode): \(error)", category: "api")
                if case .rateLimited(let after, let quota) = error {
                    log.error("429 on \(path, privacy: .public): retry after \(after)s, quota \(quota), body \(String(decoding: data, as: UTF8.self), privacy: .public)")
                    if quota { quotaUntil[path] = now().addingTimeInterval(after) }
                    else { backoffUntil = now().addingTimeInterval(after) }
                }
                throw error
            }
        }
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String, query: [String: String?] = [:]) async throws -> T {
        guard let data = try await send(.get, path, query: query) else { throw SpotifyError.decoding("Empty body for \(path)") }
        return try decode(type, data, path)
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data, _ path: String) throws -> T {
        do { return try SpotifyJSON.decoder.decode(type, from: data) }
        catch {
            let error = SpotifyError.decoding("\(path): \(error)")
            errors.record("\(error)", category: "api")
            throw error
        }
    }

    /// Clears a rate-limit back-off after a successful poll by the caller.
    public func clearBackoff() { backoffUntil = nil; quotaUntil = [:] }
    public func isBackingOff() -> Bool { (backoffUntil ?? .distantPast) > now() || quotaUntil.values.contains { $0 > now() } }

    // MARK: Player

    public func playbackState() async throws -> PlaybackState? {
        // Without `additional_types` an episode comes back as `item: null`.
        guard let data = try await send(.get, "me/player", query: ["additional_types": "episode"]) else { return nil }
        return try decode(PlaybackState.self, data, "me/player")
    }

    public func devices() async throws -> [Device] {
        try await get(DevicesResponse.self, "me/player/devices").devices
    }

    public func play(_ request: PlayRequest, deviceID: String?) async throws {
        _ = try await send(.put, "me/player/play", query: ["device_id": deviceID], json: request.jsonBody)
    }
    public func pause() async throws { _ = try await send(.put, "me/player/pause") }
    public func next() async throws { _ = try await send(.post, "me/player/next") }
    public func previous() async throws { _ = try await send(.post, "me/player/previous") }
    public func seek(toMs: Int) async throws { _ = try await send(.put, "me/player/seek", query: ["position_ms": String(toMs)]) }
    public func setVolume(_ percent: Int) async throws {
        _ = try await send(.put, "me/player/volume", query: ["volume_percent": String(min(100, max(0, percent)))])
    }
    public func setShuffle(_ on: Bool) async throws { _ = try await send(.put, "me/player/shuffle", query: ["state": on ? "true" : "false"]) }
    public func setRepeat(_ mode: RepeatMode) async throws { _ = try await send(.put, "me/player/repeat", query: ["state": mode.rawValue]) }
    public func transferPlayback(to deviceID: String, play: Bool) async throws {
        _ = try await send(.put, "me/player", json: ["device_ids": [deviceID], "play": play])
    }
    public func addToQueue(uri: String) async throws { _ = try await send(.post, "me/player/queue", query: ["uri": uri]) }
    public func queue() async throws -> QueueResponse { try await get(QueueResponse.self, "me/player/queue") }

    // MARK: Library

    public func currentUser() async throws -> SpotifyUser { try await get(SpotifyUser.self, "me") }

    public func myPlaylists(offset: Int, limit: Int) async throws -> Paging<Playlist> {
        try await get(Paging<Playlist>.self, "me/playlists", query: ["offset": String(offset), "limit": String(limit)])
    }
    public func playlist(id: String) async throws -> Playlist {
        try await get(Playlist.self, "playlists/\(id)", query: ["fields": "id,name,uri,images,owner(id,display_name),collaborative,snapshot_id,items(total),tracks(total)"])
    }
    public func playlistItems(id: String, offset: Int, limit: Int) async throws -> Paging<PlaylistItem> {
        try await get(Paging<PlaylistItem>.self, "playlists/\(id)/items",
                      query: ["offset": String(offset), "limit": String(limit), "additional_types": "track,episode"])
    }
    public func publicPlaylistTracks(id: String) async throws -> [Track] {
        var request = URLRequest(url: URL(string: "https://open.spotify.com/embed/playlist/\(id)")!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let (data, http) = try await transport.send(request)
        log.info("GET embed/playlist/\(id, privacy: .public) → \(http.statusCode)")
        guard http.statusCode == 200 else { throw SpotifyError.http(status: http.statusCode, message: "embed") }
        return try PlaylistEmbed.tracks(fromHTML: data)
    }
    public func savedTracks(offset: Int, limit: Int) async throws -> Paging<SavedTrack> {
        try await get(Paging<SavedTrack>.self, "me/tracks", query: ["offset": String(offset), "limit": String(limit)])
    }
    public func savedAlbums(offset: Int, limit: Int) async throws -> Paging<SavedAlbum> {
        try await get(Paging<SavedAlbum>.self, "me/albums", query: ["offset": String(offset), "limit": String(limit)])
    }
    public func followedArtists(after: String?, limit: Int) async throws -> CursorPaging<Artist> {
        try await get(FollowedArtistsResponse.self, "me/following", query: ["type": "artist", "after": after, "limit": String(limit)]).artists
    }
    public func albumTracks(id: String, offset: Int, limit: Int) async throws -> Paging<Track> {
        try await get(Paging<Track>.self, "albums/\(id)/tracks", query: ["offset": String(offset), "limit": String(limit)])
    }
    public func artistAlbums(id: String, offset: Int, limit: Int) async throws -> Paging<Album> {
        try await get(Paging<Album>.self, "artists/\(id)/albums",
                      // Development mode (2026) allows at most 10 per page.
                      query: ["offset": String(offset), "limit": String(min(limit, 10)), "include_groups": "album,single"])
    }
    public func artist(id: String) async throws -> Artist { try await get(Artist.self, "artists/\(id)") }
    // Podcasts (development mode 2026: lists take at most 50 per page).
    public func savedShows(offset: Int, limit: Int) async throws -> Paging<SavedShow> {
        try await get(Paging<SavedShow>.self, "me/shows", query: ["offset": String(offset), "limit": String(min(limit, 50))])
    }
    public func showEpisodes(id: String, offset: Int, limit: Int) async throws -> Paging<Track> {
        try await get(Paging<Track>.self, "shows/\(id)/episodes", query: ["offset": String(offset), "limit": String(min(limit, 50))])
    }
    public func savedEpisodes(offset: Int, limit: Int) async throws -> Paging<SavedEpisode> {
        try await get(Paging<SavedEpisode>.self, "me/episodes", query: ["offset": String(offset), "limit": String(min(limit, 50))])
    }
    public func show(id: String) async throws -> Show { try await get(Show.self, "shows/\(id)") }
    public func saveToLibrary(uris: [String]) async throws {
        for chunk in uris.chunked(40) { _ = try await send(.put, "me/library", query: ["uris": chunk.joined(separator: ",")]) }
    }
    public func removeFromLibrary(uris: [String]) async throws {
        for chunk in uris.chunked(40) { _ = try await send(.delete, "me/library", query: ["uris": chunk.joined(separator: ",")]) }
    }
    public func libraryContains(uris: [String]) async throws -> [Bool] {
        var out: [Bool] = []
        for chunk in uris.chunked(40) {
            out += try await get([Bool].self, "me/library/contains", query: ["uris": chunk.joined(separator: ",")])
        }
        return out
    }
    public func addToPlaylist(id: String, uris: [String]) async throws -> String {
        var snapshot = ""
        for chunk in uris.chunked(100) {
            let data = try await send(.post, "playlists/\(id)/items", json: ["uris": chunk])
            snapshot = try decode(SnapshotResponse.self, data ?? Data(), "playlists/items").snapshotId
        }
        return snapshot
    }
    public func removeFromPlaylist(id: String, uris: [String], snapshotID: String?) async throws -> String {
        var body: [String: Any] = ["items": uris.map { ["uri": $0] }]
        if let snapshotID { body["snapshot_id"] = snapshotID }
        let data = try await send(.delete, "playlists/\(id)/items", json: body)
        return try decode(SnapshotResponse.self, data ?? Data(), "playlists/items").snapshotId
    }
    public func createPlaylist(name: String, isPublic: Bool) async throws -> Playlist {
        let data = try await send(.post, "me/playlists", json: ["name": name, "public": isPublic])
        return try decode(Playlist.self, data ?? Data(), "me/playlists")
    }

    // MARK: Search

    public func search(_ query: String, types: [SearchType], offset: Int, limit: Int) async throws -> SearchResults {
        try await get(SearchResults.self, "search", query: [
            "q": query, "type": types.map(\.rawValue).joined(separator: ","),
            "offset": String(offset), "limit": String(min(limit, 10)),
        ])
    }
}

extension Array {
    func chunked(_ size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
