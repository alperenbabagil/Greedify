import Foundation

/// A row of the menu-bar popover's search: the thing itself (to open its page) and how it shows and plays.
public enum QuickSearchResult: Identifiable, Hashable, Sendable {
    case song(Track)
    case artist(Artist)
    case album(Album)
    case playlist(Playlist)

    public var id: String { item.uri }

    /// Name, kind line, cover and play request, as a quick-play item: a song plays alone, the rest as a context.
    public var item: QuickPlayItem {
        switch self {
        case .song(let t):
            QuickPlayItem(uri: t.uri, name: t.name, subtitle: t.artistLine, images: t.album?.images ?? [])
        case .artist(let a):
            QuickPlayItem(uri: a.uri, name: a.name, subtitle: "Artist", images: a.images ?? [])
        case .album(let a):
            QuickPlayItem(uri: a.uri, name: a.name, subtitle: "Album · \(a.artists.map(\.name).joined(separator: ", "))", images: a.images)
        case .playlist(let p):
            QuickPlayItem(uri: p.uri, name: p.name, subtitle: "Playlist" + (p.owner.displayName.map { " · \($0)" } ?? ""),
                          images: p.images)
        }
    }
}

extension SearchStore {
    /// The popover's search: songs, artists, albums and playlists only, five of each asked for (fewer bytes, and the
    /// popover shows little), separate from the main window's so typing there leaves the window's page alone.
    public static func quick(api: SpotifyAPI, debounce: Duration = .milliseconds(300)) -> SearchStore {
        SearchStore(api: api, debounce: debounce, types: [.track, .artist, .album, .playlist], limit: 5)
    }

    /// Five songs, then three each of artists, albums and playlists.
    public var quickResults: [QuickSearchResult] {
        tracks.prefix(5).map(QuickSearchResult.song) + artists.prefix(3).map(QuickSearchResult.artist)
            + albums.prefix(3).map(QuickSearchResult.album) + playlists.prefix(3).map(QuickSearchResult.playlist)
    }
}
