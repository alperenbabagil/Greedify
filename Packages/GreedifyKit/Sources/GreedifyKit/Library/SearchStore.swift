import Foundation
import Observation

/// Search with a 300 ms debounce and per-group "Show more" (10 results per page, Spotify's cap).
@MainActor @Observable
public final class SearchStore {
    public var query = "" { didSet { if query != oldValue { schedule() } } }
    public private(set) var tracks: [Track] = []
    public private(set) var albums: [Album] = []
    public private(set) var artists: [Artist] = []
    public private(set) var playlists: [Playlist] = []
    public private(set) var shows: [Show] = []
    public private(set) var episodes: [Track] = []
    public private(set) var hasMore: [SearchType: Bool] = [:]
    public private(set) var isSearching = false
    public private(set) var lastError: SpotifyError?

    let api: SpotifyAPI
    let debounce: Duration
    /// What a search asks for, and how many of each.
    let types: [SearchType]
    let limit: Int
    static let pageSize = 10
    private var pending: Task<Void, Never>?

    public init(api: SpotifyAPI, debounce: Duration = .milliseconds(300), types: [SearchType] = SearchType.allCases,
                limit: Int = 10) { // Spotify's cap (pageSize)
        self.api = api; self.debounce = debounce; self.types = types; self.limit = limit
    }

    func schedule() {
        pending?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { reset(); return }
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self.search(q)
        }
    }

    func reset() { tracks = []; albums = []; artists = []; playlists = []; shows = []; episodes = []; hasMore = [:] }

    /// Waits for the in-flight debounced search (used by tests).
    public func settle() async { await pending?.value }

    func search(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let r = try await api.search(q, types: types, offset: 0, limit: limit)
            guard q == query.trimmingCharacters(in: .whitespaces) else { return } // a newer query won
            tracks = r.tracks?.items ?? []; albums = r.albums?.items ?? []
            artists = r.artists?.items ?? []; playlists = r.playlists?.items ?? []
            shows = r.shows?.items ?? []; episodes = r.episodes?.items ?? []
            hasMore = [.track: r.tracks?.hasMore ?? false, .album: r.albums?.hasMore ?? false,
                       .artist: r.artists?.hasMore ?? false, .playlist: r.playlists?.hasMore ?? false,
                       .show: r.shows?.hasMore ?? false, .episode: r.episodes?.hasMore ?? false]
            lastError = nil
        } catch let e as SpotifyError { lastError = e } catch {}
    }

    public func showMore(_ type: SearchType) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        let offset = switch type {
        case .track: tracks.count
        case .album: albums.count
        case .artist: artists.count
        case .playlist: playlists.count
        case .show: shows.count
        case .episode: episodes.count
        }
        do {
            let r = try await api.search(q, types: [type], offset: offset, limit: Self.pageSize)
            switch type {
            case .track: tracks += r.tracks?.items ?? []; hasMore[type] = r.tracks?.hasMore ?? false
            case .album: albums += r.albums?.items ?? []; hasMore[type] = r.albums?.hasMore ?? false
            case .artist: artists += r.artists?.items ?? []; hasMore[type] = r.artists?.hasMore ?? false
            case .playlist: playlists += r.playlists?.items ?? []; hasMore[type] = r.playlists?.hasMore ?? false
            case .show: shows += r.shows?.items ?? []; hasMore[type] = r.shows?.hasMore ?? false
            case .episode: episodes += r.episodes?.items ?? []; hasMore[type] = r.episodes?.hasMore ?? false
            }
        } catch let e as SpotifyError { lastError = e } catch {}
    }
}
