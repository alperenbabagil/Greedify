import GreedifyKit
import SwiftUI

/// Big artwork, title, meta line and Play / Shuffle buttons (mockup header).
struct DetailHeader: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let images: [SpotifyImage]
    let kind: String
    let title: String
    let meta: String
    let playURI: String?
    var note: String?
    /// The list's songs, so Shuffle can start on a random one rather than always the first.
    var trackURIs: [String] = []

    var body: some View {
        AdaptiveHeader { size in
            ArtworkView(images: images, size: size, corner: theme.artworkRadius * 2)
                .shadow(color: .black.opacity(theme.isStripHeader ? 0 : 0.25), radius: 15, y: 10)
        } info: {
            Text(kind).themedFont(.caption).themed(.secondary)
            HeaderTitle(text: title)
            Text(meta).themed(.secondary)
            if let note { Text(note).themedFont(.callout).themed(.secondary) }
            if let playURI {
                HStack(spacing: 10) {
                    Button { Task { await model.player.play(.context(playURI)) } } label: { Label("Play", systemImage: "play.fill") }
                        .themedButton(.primary)
                    Button {
                        Task { await model.player.play(.context(playURI, startingAt: trackURIs.randomElement()), shuffled: true) }
                    } label: { Label("Shuffle", systemImage: "shuffle") }
                        .themedButton(.secondary)
                }
                .padding(.top, theme.isStripHeader ? 4 : 10)
            }
        }
    }
}

/// A page's title: big display text, or in a strip header the skin's title style (pixel letters with their glow
/// when the skin has them), like the text in a Winamp title bar.
struct HeaderTitle: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        let spec = theme.style?.text[.title]
        if theme.isStripHeader {
            if spec?.font == .pixel, let font = theme.pixelFont {
                PixelText(text: text, font: font, scale: 3, ink: spec?.color.map { Color($0) }, halo: CGFloat(spec?.glow ?? 0))
            } else {
                Text(text).font(LCDTitle.font(spec, theme: theme)).foregroundStyle(spec?.color.map { Color($0) } ?? theme.text).lineLimit(1)
            }
        } else {
            Text(text).themedFont(.display).lineLimit(2)
        }
    }
}

/// A page header: the cover beside the title, or above it (and smaller) when the page is narrow.
struct AdaptiveHeader<Artwork: View, Info: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let artwork: (CGFloat) -> Artwork
    @ViewBuilder let info: () -> Info
    @State private var stacked = false
    /// The cover and the text glide between the two arrangements.
    @Namespace private var space

    var body: some View {
        if theme.isStripHeader { strip } else { hero }
    }

    /// A slim strip: a small cover beside the text, the same at every width (winamp window spec).
    private var strip: some View {
        HStack(alignment: .center, spacing: 14) {
            artwork(CGFloat(theme.style?.pageHeader?.artwork ?? 48))
            VStack(alignment: .leading, spacing: 3) { info() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 10)
    }

    private var hero: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 16) {
                    artwork(120).matchedGeometryEffect(id: "artwork", in: space)
                    VStack(alignment: .leading, spacing: 6) { info() }.matchedGeometryEffect(id: "info", in: space)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .bottom, spacing: 22) {
                    artwork(168).matchedGeometryEffect(id: "artwork", in: space)
                    VStack(alignment: .leading, spacing: 6) { info() }.matchedGeometryEffect(id: "info", in: space)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, stacked ? 24 : 34).padding(.bottom, 20)
        // Only the width decides, and the layout changes only the height: no feedback into the measurement.
        .onGeometryChange(for: Bool.self) { [stacked] in AdaptiveLayout.stacksHeader(width: $0.size.width, wasStacked: stacked) } action: { v in withAnimation(.layoutChange) { stacked = v } }
    }
}

struct PlaylistView: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist
    @State private var loading = true

    var body: some View {
        let current = model.library.playlists.first { $0.id == playlist.id } ?? playlist
        let tracks = model.library.playlistTracks[playlist.id] ?? []
        let editable = model.library.user.map { current.isEditable(by: $0.id) } ?? false
        PageScrollView {
            DetailHeader(images: current.images, kind: editable ? "Your playlist" : "Playlist", title: current.name,
                         meta: "\(current.trackCount) songs, \(formatDuration(tracks.reduce(0) { $0 + $1.durationMs }))",
                         playURI: current.uri, note: editable || loading ? nil : note(shown: tracks.count, total: current.trackCount),
                         trackURIs: tracks.map(\.uri))
            if loading && tracks.isEmpty { ProgressView().padding() }
            TrackTable(tracks: tracks, context: TrackListContext(contextURI: current.uri, editablePlaylist: editable ? current : nil,
                                                                fallbackImages: current.images))
                .padding(.horizontal, 20)
        }
        .task(id: current.snapshotId) {
            loading = true; _ = await model.library.tracks(for: current); loading = false
            await model.captureMixSongs() // playing now: fill in what the list lacks
        }
    }

    /// Spotify doesn't list the songs of someone else's playlist: they come from its public page (the first 100) and
    /// from the queue while it plays.
    private func note(shown: Int, total: Int) -> String? {
        if shown == 0 { return "Spotify doesn't let apps list playlists you don't own. Play it and its songs will show up here." }
        if shown < total { return "Showing \(shown) of \(total) songs. Play the playlist to see more." }
        return nil
    }
}

struct LikedSongsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let library = model.library
        let collection = library.user.map { "spotify:user:\($0.id):collection" }
        PageScrollView {
            DetailHeader(images: [], kind: "Library", title: "Liked Songs", meta: "\(library.likedTotal) songs",
                         playURI: collection, trackURIs: library.likedTracks.map(\.uri))
            // The whole collection, not the loaded rows: shuffle then covers every liked song.
            TrackTable(tracks: library.likedTracks, context: TrackListContext(contextURI: collection)) {
                Task { await library.loadMoreLiked() }
            }
            .padding(.horizontal, 20)
        }
        .task { if library.likedTracks.isEmpty { await library.loadMoreLiked() } }
    }
}

struct MixView: View {
    @Environment(AppModel.self) private var model
    let mix: MixLink
    /// The queue couldn't be read (e.g. a quota limit): show the old list, dimmed, rather than wait forever.
    @State private var refreshFailed = false

    var body: some View {
        let tracks = model.settings.mixTracks(mix.uri)
        let outdated = model.settings.mixFreshness(mix.uri)?.outdated ?? false
        let playing = model.player.state?.context?.uri == mix.uri
        PageScrollView {
            DetailHeader(images: model.settings.mixCover(mix.uri), kind: "Mix", title: mix.name,
                         meta: tracks.isEmpty ? "Made for you by Spotify"
                             : "\(tracks.count) songs, \(formatDuration(tracks.reduce(0) { $0 + $1.durationMs }))",
                         playURI: mix.uri,
                         note: tracks.isEmpty ? "Spotify doesn't let apps list a mix's songs. Play it once and they'll show up here."
                             : freshness,
                         trackURIs: tracks.map(\.uri))
            if outdated && playing && !refreshFailed {
                // The saved songs are about to be replaced from the queue: rows swapping under the pointer made
                // a click play a different song. Wait for the fresh list instead.
                ProgressView().padding()
            } else {
                TrackTable(tracks: tracks, context: TrackListContext(contextURI: mix.uri, startsFromTop: outdated))
                    .padding(.horizontal, 20)
            }
        }
        .task(id: "\(mix.uri) \(playing)") {
            await model.captureMixSongs()
            refreshFailed = playing && model.settings.mixFreshness(mix.uri)?.outdated == true
        }
    }

    /// "Updated 2 days ago · Play to refresh": the songs are only learnt while the mix plays.
    private var freshness: String? {
        guard let (capturedAt, outdated) = model.settings.mixFreshness(mix.uri) else { return nil }
        let updated = "Updated \(capturedAt.formatted(.relative(presentation: .named)))"
        return outdated ? "\(updated) · Play to refresh" : updated
    }
}

struct AlbumView: View {
    @Environment(AppModel.self) private var model
    let album: Album
    @State private var tracks: [Track] = []

    var body: some View {
        PageScrollView {
            DetailHeader(images: album.images, kind: "Album", title: album.name,
                         meta: album.artists.map(\.name).joined(separator: ", "), playURI: album.uri,
                         trackURIs: tracks.map(\.uri))
            TrackTable(tracks: tracks, context: TrackListContext(contextURI: album.uri, fallbackImages: album.images))
                .padding(.horizontal, 20)
        }
        .task(id: album.id) {
            tracks = (try? await model.api.albumTracks(id: album.id, offset: 0, limit: 50).items) ?? []
        }
    }
}

struct CoverGrid<Item: Identifiable>: View {
    @Environment(\.theme) private var theme
    let items: [Item]
    let images: (Item) -> [SpotifyImage]
    let title: (Item) -> String
    let subtitle: (Item) -> String
    let circle: Bool
    let onOpen: (Item) -> Void
    var onReachEnd: (() -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.isSystem ? 150 : 166), spacing: 20)], spacing: 20) {
            ForEach(items) { item in
                Button { onOpen(item) } label: {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkView(images: images(item), size: 150, corner: circle ? 75 : theme.artworkRadius + 2)
                            Text(title(item)).fontWeight(.medium).lineLimit(1)
                            Text(subtitle(item)).themedFont(.caption).themed(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onAppear { if item.id == items.last?.id { onReachEnd?() } }
            }
        }
        .padding(24)
    }
}

struct AlbumsGrid: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let library = model.library
        PageScrollView {
            CoverGrid(items: library.albums, images: \.images, title: \.name, subtitle: { $0.artists.map(\.name).joined(separator: ", ") },
                      circle: false, onOpen: { model.route = .album($0) }, onReachEnd: { Task { await library.loadMoreAlbums() } })
        }
        .navigationTitle("Albums")
        .task { if library.albums.isEmpty { await library.loadMoreAlbums() } }
    }
}

struct ArtistsGrid: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let library = model.library
        PageScrollView {
            CoverGrid(items: library.artists, images: { $0.images ?? [] }, title: \.name, subtitle: { _ in "Artist" },
                      circle: true, onOpen: { model.route = .artist($0) }, onReachEnd: { Task { await library.loadMoreArtists() } })
        }
        .navigationTitle("Artists")
        .task { if library.artists.isEmpty { await library.loadMoreArtists() } }
    }
}

struct ArtistView: View {
    @Environment(AppModel.self) private var model
    let artist: Artist
    @State private var albums: [Album] = []
    @State private var total: Int?
    @State private var loadingMore = false
    @State private var popular: [Track] = []
    /// Opened from a track's artist, which has no photo: fetched once.
    @State private var photo: [SpotifyImage]?

    var body: some View {
        PageScrollView {
            DetailHeader(images: artist.images ?? photo ?? [], kind: "Artist", title: artist.name,
                         meta: "\(total ?? albums.count) releases", playURI: artist.uri,
                         trackURIs: popular.map(\.uri))
            if !popular.isEmpty {
                Text("Popular").themedFont(.title).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28)
                TrackTable(tracks: popular, context: TrackListContext(contextURI: nil)).padding(.horizontal, 20)
            }
            if !albums.isEmpty {
                Text("Releases").themedFont(.title).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.top, 20)
            }
            CoverGrid(items: albums, images: \.images, title: \.name, subtitle: { _ in "Album" }, circle: false,
                      onOpen: { model.route = .album($0) }, onReachEnd: { Task { await loadMore() } })
        }
        .task(id: artist.id) {
            albums = []; total = nil; photo = nil; popular = []
            async let songs = model.library.popularTracks(for: artist)
            if artist.images == nil { photo = try? await model.api.artist(id: artist.id).images }
            await loadMore()
            popular = await songs
        }
    }

    /// Spotify hands out an artist's releases 10 at a time: load the next page as the grid reaches its end.
    private func loadMore() async {
        guard !loadingMore, total.map({ albums.count < $0 }) ?? true else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await model.api.artistAlbums(id: artist.id, offset: albums.count, limit: 10) else { return }
        albums += page.items
        total = page.items.isEmpty ? albums.count : page.total
    }
}

struct SearchResultsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let search = model.search
        PageScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if search.query.isEmpty {
                    ContentUnavailableView("Search Spotify", systemImage: "magnifyingglass", description: Text("Find songs, albums, artists and playlists."))
                } else if !search.isSearching && search.tracks.isEmpty && search.albums.isEmpty && search.artists.isEmpty && search.playlists.isEmpty
                            && search.shows.isEmpty && search.episodes.isEmpty {
                    ContentUnavailableView.search(text: search.query)
                }
                if !search.tracks.isEmpty {
                    section("Songs", .track) { TrackTable(tracks: search.tracks, context: TrackListContext(contextURI: nil)) }
                }
                if !search.artists.isEmpty {
                    section("Artists", .artist) {
                        CoverGrid(items: search.artists, images: { $0.images ?? [] }, title: \.name, subtitle: { _ in "Artist" },
                                  circle: true, onOpen: { model.route = .artist($0) })
                    }
                }
                if !search.albums.isEmpty {
                    section("Albums", .album) {
                        CoverGrid(items: search.albums, images: \.images, title: \.name, subtitle: { $0.artists.map(\.name).joined(separator: ", ") },
                                  circle: false, onOpen: { model.route = .album($0) })
                    }
                }
                if !search.playlists.isEmpty {
                    section("Playlists", .playlist) {
                        CoverGrid(items: search.playlists, images: \.images, title: \.name, subtitle: { $0.owner.displayName ?? "" },
                                  circle: false, onOpen: { model.route = .playlist($0) })
                    }
                }
                if !search.shows.isEmpty {
                    section("Podcasts", .show) {
                        CoverGrid(items: search.shows, images: \.images, title: \.name, subtitle: { _ in "Podcast" },
                                  circle: false, onOpen: { model.route = .show($0) })
                    }
                }
                if !search.episodes.isEmpty {
                    section("Episodes", .episode) { EpisodeTable(episodes: search.episodes, showShowName: true) }
                }
            }
            .padding(20)
        }
    }

    func section<Content: View>(_ title: String, _ type: SearchType, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).themedFont(.title)
            content()
            if model.search.hasMore[type] == true {
                let more = Button("Show more") { Task { await model.search.showMore(type) } }
                if theme.isSystem { more.buttonStyle(.link) } else { more.buttonStyle(.plain).themed(.accent) }
            }
        }
    }
}
