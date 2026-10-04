import Foundation
import Observation

@MainActor @Observable
public final class LibraryStore {
    public private(set) var user: SpotifyUser?
    public private(set) var playlists: [Playlist] = []
    public private(set) var playlistTracks: [String: [Track]] = [:]
    public private(set) var likedTracks: [Track] = []
    public private(set) var likedTotal = 0
    /// True once the first page of Liked Songs has loaded; local edits to the list wait for it.
    public private(set) var likedLoaded = false
    public private(set) var albums: [Album] = []
    public private(set) var artists: [Artist] = []
    public private(set) var shows: [Show] = []
    public private(set) var savedEpisodes: [Track] = []
    /// A show's episodes, newest first, keyed by show id (podcasts spec §7).
    public private(set) var showEpisodes: [String: [Track]] = [:]
    private var showsTotal: Int?
    private var savedEpisodesTotal: Int?
    private var showEpisodesTotal: [String: Int] = [:]
    /// Day boundaries for the show-episode cache; a test sets UTC.
    var calendar = Calendar.current
    /// IDs of tracks known to be in Liked Songs (drives the heart icons).
    public private(set) var likedIDs: Set<String> = []
    public private(set) var lastError: SpotifyError?

    let api: SpotifyAPI
    let cache: DataCache
    let now: @Sendable () -> Date
    static let pageSize = 50
    private var artistsCursor: String?
    private var artistsDone = false

    // Spotify's development-mode quota is small and per endpoint (see CLAUDE.md), so answers that rarely
    // change are kept on disk: the user for a week, like flags for a day.
    public static let userTTL: TimeInterval = 7 * 86_400
    public static let likesTTL: TimeInterval = 86_400
    /// Your Shows and Your Episodes change rarely; a show's episodes are kept until midnight.
    public static let podcastListTTL: TimeInterval = 3600
    /// When each track's like flag was last learned (from Spotify or our own toggle).
    private var likeCheckedAt: [String: Date] = [:]
    private var likesRestored = false

    public init(api: SpotifyAPI, cache: DataCache, now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api; self.cache = cache; self.now = now
    }

    struct CachedPlaylist: Codable { let snapshotId: String; let tracks: [Track] }
    struct CachedUser: Codable { let user: SpotifyUser; let fetchedAt: Date }
    struct CachedLikes: Codable { let liked: Set<String>; let checkedAt: [String: Date] }
    struct CachedPage<T: Codable & Sendable>: Codable, Sendable { let items: [T]; let total: Int; let fetchedAt: Date }
    struct CachedPopular: Codable { let tracks: [Track]; let fetchedAt: Date }
    /// Popularity changes slowly, and search has its own small daily quota.
    public static let popularTTL: TimeInterval = 86_400

    public func editablePlaylists() -> [Playlist] {
        guard let id = user?.id else { return [] }
        return playlists.filter { $0.isEditable(by: id) }
    }

    func run<T>(_ body: () async throws -> T) async -> T? {
        do { return try await body() }
        catch let e as SpotifyError { lastError = e; return nil }
        catch is CancellationError { return nil } // cancelled with its task: nothing went wrong
        catch { lastError = .transport("\(error)"); return nil }
    }

    public func clearError() { lastError = nil }

    /// An artist's popular songs. Development mode (2026) has no top-tracks endpoint, so this searches the artist's
    /// songs (Spotify ranks them by popularity), drops other artists the fuzzy name filter matches, and drops the
    /// same song on another release. Features count: without them a single page often left only 5. At most 10.
    public func popularTracks(for artist: Artist) async -> [Track] {
        let key = "lib:popular2:\(artist.id)"
        let cached = await cache.value(CachedPopular.self, for: key)
        if let cached, now().timeIntervalSince(cached.fetchedAt) < Self.popularTTL { return cached.tracks }
        let name = artist.name.replacingOccurrences(of: "\"", with: "")
        guard let found = await run({ try await api.search("artist:\"\(name)\"", types: [.track], offset: 0, limit: 10) })
        else { return cached?.tracks ?? [] }
        var seen = Set<String>()
        let tracks = (found.tracks?.items ?? []).filter {
            $0.artists.contains { $0.id == artist.id } && seen.insert($0.name.lowercased()).inserted
        }
        await cache.store(CachedPopular(tracks: tracks, fetchedAt: now()), for: key)
        return tracks
    }

    /// Shows cached playlists instantly, then refreshes the full list from Spotify.
    public func load() async {
        if playlists.isEmpty, let cached = await cache.value([Playlist].self, for: "lib:playlists") { playlists = cached }
        user = await currentUser()
        var all: [Playlist] = []
        var offset = 0
        while true {
            guard let page = await run({ try await api.myPlaylists(offset: offset, limit: Self.pageSize) }) else { return }
            all += page.items
            offset += page.items.count
            if !page.hasMore || page.items.isEmpty { break }
        }
        playlists = all
        await cache.store(all, for: "lib:playlists")
    }

    /// The cached user while fresh, else Spotify's; a stale copy beats none when the fetch fails.
    private func currentUser() async -> SpotifyUser? {
        let cached = await cache.value(CachedUser.self, for: "lib:user")
        if let cached, now().timeIntervalSince(cached.fetchedAt) < Self.userTTL { return cached.user }
        guard let me = await run({ try await api.currentUser() }) else { return cached?.user ?? user }
        await cache.store(CachedUser(user: me, fetchedAt: now()), for: "lib:user")
        return me
    }

    /// Loads a playlist's tracks, re-downloading only if its `snapshot_id` changed.
    public func tracks(for playlist: Playlist) async -> [Track] {
        let key = "lib:playlist:\(playlist.id)"
        let cached = await cache.value(CachedPlaylist.self, for: key)
        if let cached, cached.snapshotId == playlist.snapshotId {
            playlistTracks[playlist.id] = cached.tracks
            return cached.tracks
        }
        if !isReadable(playlist) { return await publicTracks(for: playlist, cached: cached) }
        var tracks: [Track] = []
        var offset = 0
        while true {
            // A failed page means the list is incomplete: show what we have, but don't keep or cache it.
            let page: Paging<PlaylistItem>
            do { page = try await api.playlistItems(id: playlist.id, offset: offset, limit: Self.pageSize) }
            catch SpotifyError.forbidden where offset == 0 {
                forbiddenPlaylists.insert(playlist.id)
                return await publicTracks(for: playlist, cached: cached)
            }
            catch let e as SpotifyError { lastError = e; return tracks }
            catch is CancellationError { return tracks }
            catch { lastError = .transport("\(error)"); return tracks }
            tracks += page.items.compactMap(\.track)
            offset += page.items.count
            if !page.hasMore || page.items.isEmpty { break }
        }
        playlistTracks[playlist.id] = tracks
        await cache.store(CachedPlaylist(snapshotId: playlist.snapshotId, tracks: tracks), for: key)
        return tracks
    }

    /// Development mode (2026) answers 403 for the items of a playlist the user neither owns nor collaborates on.
    private var forbiddenPlaylists: Set<String> = []

    private func isReadable(_ playlist: Playlist) -> Bool {
        guard !forbiddenPlaylists.contains(playlist.id) else { return false }
        guard let user else { return true } // unknown: ask, and learn from a 403
        return playlist.isEditable(by: user.id)
    }

    /// Someone else's playlist: its first 100 songs from Spotify's public embed page (unofficial, no album art or ids),
    /// else the songs seen in the queue while it played (`recordQueueSongs`). Neither failing shows a banner.
    private func publicTracks(for playlist: Playlist, cached: CachedPlaylist?) async -> [Track] {
        guard let tracks = try? await api.publicPlaylistTracks(id: playlist.id) else {
            let known = cached?.tracks ?? playlistTracks[playlist.id] ?? []
            playlistTracks[playlist.id] = known
            return known
        }
        playlistTracks[playlist.id] = tracks
        await cache.store(CachedPlaylist(snapshotId: playlist.snapshotId, tracks: tracks), for: "lib:playlist:\(playlist.id)")
        return tracks
    }

    /// Whether the queue should be read while `contextURI` plays: it's a playlist Spotify won't list for us.
    public func wantsQueueSongs(contextURI: String) -> Bool {
        guard let playlist = playlists.first(where: { $0.uri == contextURI }) else { return false }
        return !isReadable(playlist)
    }

    /// Songs seen in the queue while an unreadable playlist plays: they replace the embed's bare copies (adding album
    /// art and ids) and add songs the list lacks.
    public func recordQueueSongs(contextURI: String, tracks seen: [Track]) async {
        guard wantsQueueSongs(contextURI: contextURI), let playlist = playlists.first(where: { $0.uri == contextURI }) else { return }
        let known = playlistTracks[playlist.id] ?? []
        let byID = Dictionary(seen.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ids = Set(known.map(\.id))
        let merged = known.map { byID[$0.id] ?? $0 } + seen.filter { ids.insert($0.id).inserted }
        guard merged != known else { return }
        playlistTracks[playlist.id] = merged
        await cache.store(CachedPlaylist(snapshotId: playlist.snapshotId, tracks: merged), for: "lib:playlist:\(playlist.id)")
    }

    public func loadMoreLiked() async {
        if likedLoaded && likedTracks.count >= likedTotal { return }
        let offset = likedLoaded ? likedTracks.count : 0
        guard let page = await run({ try await api.savedTracks(offset: offset, limit: Self.pageSize) }) else { return }
        if likedLoaded { likedTracks += page.items.map(\.track) } else { likedTracks = page.items.map(\.track) }
        likedLoaded = true
        likedTotal = page.total
        await restoreLikes()
        likedIDs.formUnion(page.items.map(\.track.id))
        await noteChecked(page.items.map(\.track.id))
    }

    public func loadMoreAlbums() async {
        guard let page = await run({ try await api.savedAlbums(offset: albums.count, limit: Self.pageSize) }) else { return }
        albums += page.items.map(\.album)
    }

    public func loadMoreArtists() async {
        guard !artistsDone else { return }
        guard let page = await run({ try await api.followedArtists(after: artistsCursor, limit: Self.pageSize) }) else { return }
        artists += page.items
        artistsCursor = page.cursors?.after
        artistsDone = page.next == nil
    }

    // MARK: Refresh

    /// The toolbar's Refresh: the playlists again (an edited one's new snapshot refetches its songs when shown), and
    /// each list already opened from its first page, skipping the caches. A list never opened isn't fetched, and a
    /// failed fetch keeps what's shown.
    public func refresh() async {
        async let playlists: Void = load()
        async let liked: Void = refreshLiked()
        async let albums: Void = refreshAlbums()
        async let artists: Void = refreshArtists()
        async let shows: Void = refreshShows()
        async let episodes: Void = refreshSavedEpisodes()
        _ = await (playlists, liked, albums, artists, shows, episodes)
    }

    private func refreshLiked() async {
        guard likedLoaded, let page = await run({ try await api.savedTracks(offset: 0, limit: Self.pageSize) }) else { return }
        likedTracks = page.items.map(\.track)
        likedTotal = page.total
        likedIDs.formUnion(page.items.map(\.track.id))
        await noteChecked(page.items.map(\.track.id))
    }

    private func refreshAlbums() async {
        guard !albums.isEmpty, let page = await run({ try await api.savedAlbums(offset: 0, limit: Self.pageSize) }) else { return }
        albums = page.items.map(\.album)
    }

    private func refreshArtists() async {
        guard !artists.isEmpty, let page = await run({ try await api.followedArtists(after: nil, limit: Self.pageSize) }) else { return }
        artists = page.items
        artistsCursor = page.cursors?.after
        artistsDone = page.next == nil
    }

    private func refreshShows() async {
        guard !shows.isEmpty, let page = await run({ try await api.savedShows(offset: 0, limit: Self.pageSize) }) else { return }
        shows = page.items.map(\.show)
        showsTotal = page.total
        await cache.store(CachedPage(items: shows, total: page.total, fetchedAt: now()), for: "lib:shows")
    }

    private func refreshSavedEpisodes() async {
        guard !savedEpisodes.isEmpty, let page = await run({ try await api.savedEpisodes(offset: 0, limit: Self.pageSize) }) else { return }
        savedEpisodes = page.items.map(\.episode)
        savedEpisodesTotal = page.total
        likedIDs.formUnion(page.items.map(\.episode.id))
        await noteChecked(page.items.map(\.episode.id))
        await cache.store(CachedPage(items: savedEpisodes, total: page.total, fetchedAt: now()), for: "lib:episodes")
    }

    // MARK: Podcasts

    public func loadMoreShows() async {
        if let showsTotal, shows.count >= showsTotal { return }
        if shows.isEmpty, let cached = await cache.value(CachedPage<Show>.self, for: "lib:shows"),
           now().timeIntervalSince(cached.fetchedAt) < Self.podcastListTTL {
            shows = cached.items; showsTotal = cached.total
            return
        }
        guard let page = await run({ try await api.savedShows(offset: shows.count, limit: Self.pageSize) }) else { return }
        shows += page.items.map(\.show)
        showsTotal = page.total
        if page.offset == 0 { await cache.store(CachedPage(items: shows, total: page.total, fetchedAt: now()), for: "lib:shows") }
    }

    public func loadMoreSavedEpisodes() async {
        if let savedEpisodesTotal, savedEpisodes.count >= savedEpisodesTotal { return }
        if savedEpisodes.isEmpty, let cached = await cache.value(CachedPage<Track>.self, for: "lib:episodes"),
           now().timeIntervalSince(cached.fetchedAt) < Self.podcastListTTL {
            savedEpisodes = cached.items; savedEpisodesTotal = cached.total
            return
        }
        guard let page = await run({ try await api.savedEpisodes(offset: savedEpisodes.count, limit: Self.pageSize) }) else { return }
        savedEpisodes += page.items.map(\.episode)
        savedEpisodesTotal = page.total
        await restoreLikes()
        likedIDs.formUnion(page.items.map(\.episode.id))
        await noteChecked(page.items.map(\.episode.id))
        if page.offset == 0 { await cache.store(CachedPage(items: savedEpisodes, total: page.total, fetchedAt: now()), for: "lib:episodes") }
    }

    /// A show's first page of episodes, newest first: from memory, else the disk cache while it's the same day,
    /// else Spotify. The player's next-episode lookup reads it too.
    public func episodes(of show: ShowRef, containing episodeID: String? = nil) async -> [Track] {
        var list = await firstEpisodes(of: show)
        // The playing episode may be older than the first page (podcasts review 7): page on, a few pages at most.
        guard let episodeID, let id = show.id else { return list }
        while !list.contains(where: { $0.id == episodeID }), (episodePagesLoaded[id] ?? 1) < Self.maxEpisodePages,
              list.count < showEpisodesTotal[id] ?? 0 {
            await loadMoreEpisodes(of: show)
            let grown = showEpisodes[id] ?? list
            if grown.count == list.count { break }
            list = grown
        }
        return list
    }

    /// Pages looked through for a playing episode, and the most episodes that can mean.
    static let maxEpisodePages = 4
    static let maxEpisodesLookedThrough = maxEpisodePages * pageSize
    private var episodePagesLoaded: [String: Int] = [:]

    private func firstEpisodes(of show: ShowRef) async -> [Track] {
        guard let id = show.id else { return [] }
        if let loaded = showEpisodes[id] { return loaded }
        let key = "lib:show:\(id)"
        if let cached = await cache.value(CachedPage<Track>.self, for: key), calendar.isDate(cached.fetchedAt, inSameDayAs: now()) {
            showEpisodes[id] = cached.items; showEpisodesTotal[id] = cached.total
            return cached.items
        }
        guard let page = await run({ try await api.showEpisodes(id: id, offset: 0, limit: Self.pageSize) }) else { return [] }
        let items = page.items.map { $0.inShow(show) }
        showEpisodes[id] = items; showEpisodesTotal[id] = page.total
        await cache.store(CachedPage(items: items, total: page.total, fetchedAt: now()), for: key)
        return items
    }

    public func loadMoreEpisodes(of show: ShowRef) async {
        guard let id = show.id else { return }
        guard let loaded = showEpisodes[id] else { _ = await episodes(of: show); return }
        if let total = showEpisodesTotal[id], loaded.count >= total { return }
        guard let page = await run({ try await api.showEpisodes(id: id, offset: loaded.count, limit: Self.pageSize) }) else { return }
        showEpisodes[id] = loaded + page.items.map { $0.inShow(show) }
        episodePagesLoaded[id, default: 1] += 1
    }

    public func isFollowing(_ show: Show) -> Bool { likedIDs.contains(show.id) }
    public func refreshFollow(_ show: Show) async { await refreshSaved([(show.id, show.uri)]) }

    public func toggleFollow(_ show: Show) async {
        guard let nowFollowing = await toggleSaved(id: show.id, uri: show.uri) else { return }
        guard showsTotal != nil else { return } // the first load will include it
        if nowFollowing { shows.insert(show, at: 0); showsTotal? += 1 }
        else { shows.removeAll { $0.id == show.id }; showsTotal = max(0, (showsTotal ?? 1) - 1) }
    }

    /// Updates `likedIDs` for tracks on screen (40 per request), asking only about tracks not checked lately.
    public func refreshLikes(for tracks: [Track]) async { await refreshSaved(tracks.map { ($0.id, $0.uri) }) }

    /// Saved / followed flags for any library items (songs, episodes, shows), keyed by id.
    private func refreshSaved(_ items: [(id: String, uri: String)]) async {
        await restoreLikes()
        let unknown = items.filter { likeCheckedAt[$0.id].map { now().timeIntervalSince($0) >= Self.likesTTL } ?? true }
        let unique = Array(Set(unknown.map(\.uri)))
        guard !unique.isEmpty, let flags = await run({ try await api.libraryContains(uris: unique) }) else { return }
        var ids: [String] = []
        for (uri, liked) in zip(unique, flags) {
            guard let id = uri.split(separator: ":").last.map(String.init) else { continue }
            if liked { likedIDs.insert(id) } else { likedIDs.remove(id) }
            ids.append(id)
        }
        await noteChecked(ids)
    }

    /// Loads remembered like flags once per launch.
    private func restoreLikes() async {
        guard !likesRestored else { return }
        likesRestored = true
        guard let saved = await cache.value(CachedLikes.self, for: "lib:likes") else { return }
        // Flags learned this launch (e.g. a toggle before the restore) are newer than the saved ones.
        likedIDs.formUnion(saved.liked.filter { likeCheckedAt[$0] == nil })
        likeCheckedAt.merge(saved.checkedAt) { mine, _ in mine }
    }

    /// Records fresh like flags and saves them, dropping entries too old to trust.
    private func noteChecked(_ ids: [String]) async {
        let date = now()
        for id in ids { likeCheckedAt[id] = date }
        likeCheckedAt = likeCheckedAt.filter { date.timeIntervalSince($0.value) < Self.likesTTL }
        let liked = likedIDs.filter { likeCheckedAt[$0] != nil }
        await cache.store(CachedLikes(liked: liked, checkedAt: likeCheckedAt), for: "lib:likes")
    }

    public func isLiked(_ track: Track) -> Bool { likedIDs.contains(track.id) }

    public func toggleLike(_ track: Track) async {
        guard let nowLiked = await toggleSaved(id: track.id, uri: track.uri) else { return }
        if track.isEpisode { // Your Episodes, never Liked Songs
            guard savedEpisodesTotal != nil else { return }
            if nowLiked { savedEpisodes.insert(track, at: 0); savedEpisodesTotal? += 1 }
            else { savedEpisodes.removeAll { $0.id == track.id }; savedEpisodesTotal = max(0, (savedEpisodesTotal ?? 1) - 1) }
            return
        }
        guard likedLoaded else { return } // the first page load will include this change
        if nowLiked { likedTracks.insert(track, at: 0); likedTotal += 1 }
        else { likedTracks.removeAll { $0.id == track.id }; likedTotal = max(0, likedTotal - 1) }
    }

    /// Flips a library item's saved flag at once, then on Spotify; rolls back if that fails.
    /// Returns the new state, or nil when Spotify refused.
    private func toggleSaved(id: String, uri: String) async -> Bool? {
        await restoreLikes()
        let wasSaved = likedIDs.contains(id)
        if wasSaved { likedIDs.remove(id) } else { likedIDs.insert(id) }
        let ok = await run {
            if wasSaved { try await api.removeFromLibrary(uris: [uri]) } else { try await api.saveToLibrary(uris: [uri]) }
        } != nil
        guard ok else {
            if wasSaved { likedIDs.insert(id) } else { likedIDs.remove(id) }
            return nil
        }
        await noteChecked([id])
        return !wasSaved
    }

    public func add(_ track: Track, to playlist: Playlist) async {
        guard let snapshot = await run({ try await api.addToPlaylist(id: playlist.id, uris: [track.uri]) }) else { return }
        playlistTracks[playlist.id]?.append(track) // only if its tracks are loaded
        await replaceSnapshot(of: playlist.id, with: snapshot, countDelta: 1)
    }

    public func remove(_ track: Track, from playlist: Playlist) async {
        let current = playlists.first { $0.id == playlist.id }?.snapshotId
        guard let snapshot = await run({ try await api.removeFromPlaylist(id: playlist.id, uris: [track.uri], snapshotID: current) }) else { return }
        playlistTracks[playlist.id]?.removeAll { $0.uri == track.uri }
        await replaceSnapshot(of: playlist.id, with: snapshot, countDelta: -1)
    }

    /// Creates a private playlist, optionally adding `track` to it.
    @discardableResult
    public func createPlaylist(named name: String, adding track: Track? = nil) async -> Playlist? {
        guard let created = await run({ try await api.createPlaylist(name: name, isPublic: false) }) else { return nil }
        playlists.insert(created, at: 0)
        playlistTracks[created.id] = []
        if let track { await add(track, to: created) }
        await cache.store(playlists, for: "lib:playlists")
        return playlists.first { $0.id == created.id }
    }

    private func replaceSnapshot(of id: String, with snapshot: String, countDelta: Int) async {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let p = playlists[i]
        playlists[i] = Playlist(id: p.id, name: p.name, uri: p.uri, images: p.images, owner: p.owner,
                                collaborative: p.collaborative, snapshotId: snapshot, trackCount: max(0, p.trackCount + countDelta))
        if let tracks = playlistTracks[id] {
            await cache.store(CachedPlaylist(snapshotId: snapshot, tracks: tracks), for: "lib:playlist:\(id)")
        } else {
            await cache.remove("lib:playlist:\(id)") // not loaded: refetch next time instead of caching a partial list
        }
        await cache.store(playlists, for: "lib:playlists")
    }
}
