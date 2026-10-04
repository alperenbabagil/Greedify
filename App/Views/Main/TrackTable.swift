import GreedifyKit
import SwiftUI

/// Where a track list came from; decides what "Play" means and whether "Remove" is offered.
struct TrackListContext {
    var contextURI: String?          // play inside this context (playlist/album), else play the list's URIs
    var editablePlaylist: Playlist?  // shows "Remove from This Playlist"
    var fallbackImages: [SpotifyImage] = []  // album tracks have no album field
    /// The rows may no longer be in the context (an outdated mix): they're dimmed and a click plays the context
    /// from its start, which also refreshes the list. Starting at a song Spotify dropped started the mix's first song.
    var startsFromTop = false
}

struct TrackTable: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let tracks: [Track]
    let context: TrackListContext
    var onReachEnd: (() -> Void)?
    /// The Album column, dropped when the table is narrow (AdaptiveLayout).
    @State private var showsAlbum = true
    /// A song that started playing before its row was loaded: scrolled to once a later page brings it.
    @State private var pendingScroll: String?
    /// The song a "New Playlist…" sheet will add. One sheet for the table: a sheet modifier on every row cost each
    /// row its own presentation machinery.
    @State private var newPlaylistFor: Track?

    var body: some View {
        ScrollViewReader { proxy in
            rows
                // Follow the playing song: when it changes (a shuffle can start one far down the list), the
                // page scrolls it to the middle. Only on a change, so it never fights the user's own scrolling.
                .onChange(of: model.player.track?.id) { _, id in pendingScroll = id; scrollToPlaying(proxy) }
                .onChange(of: tracks.count) { if pendingScroll != nil { scrollToPlaying(proxy) } }
                .sheet(item: $newPlaylistFor) { NewPlaylistSheet(track: $0) }
        }
    }

    private func scrollToPlaying(_ proxy: ScrollViewProxy) {
        guard pendingScroll != nil, let index = PlayingRow.index(of: model.player.track, in: tracks) else { return }
        pendingScroll = nil
        let anchor = TrackRowAnchor(index: index)
        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(anchor, anchor: .center) }
        // Rows far down aren't laid out yet and the lazy stack only estimates their height, so the first jump can
        // land short; once it has, the rows around the target are real and a second scroll centres it exactly.
        Task { try? await Task.sleep(for: .milliseconds(450)); withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(anchor, anchor: .center) } }
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            if theme.isPlaylistList {
                HStack(spacing: 8) {
                    Text("#").frame(width: 34, alignment: .trailing)
                    Text("Artist - Title").frame(maxWidth: .infinity, alignment: .leading)
                    if showsAlbum { Text("Album").frame(width: 190, alignment: .leading) }
                    Spacer().frame(width: 20)
                    Text("Time").frame(width: 40, alignment: .trailing)
                }
                .font(theme.listFont()).themed(.tertiary)
                .padding(.horizontal, 6).frame(height: 20)
            } else {
                HStack(spacing: 10) {
                    Text("#").frame(width: 28, alignment: .trailing)
                    Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                    if showsAlbum { Text("Album").frame(width: 190, alignment: .leading) }
                    Spacer().frame(width: 28)
                    Text("Time").frame(width: 48, alignment: .trailing)
                }
                .themedFont(.caption).themed(.tertiary)
                .padding(.horizontal, 8).frame(height: 28)
            }
            ThemedDivider()
            let playing = PlayingRow.index(of: model.player.track, in: tracks)
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                TrackRow(index: index, track: track, context: context, list: tracks, isCurrent: index == playing, showsAlbum: showsAlbum,
                         onNewPlaylist: { newPlaylistFor = $0 })
                    .id(TrackRowAnchor(index: index))
                    .onAppear { if index == tracks.count - 1 { onReachEnd?() } }
            }
        }
        .onGeometryChange(for: Bool.self) { [showsAlbum] in AdaptiveLayout.showsAlbumColumn(tableWidth: $0.size.width, wasShown: showsAlbum) } action: { v in withAnimation(.layoutChange) { showsAlbum = v } }
        .task(id: tracks.map(\.id)) { await model.library.refreshLikes(for: Array(tracks.prefix(40))) }
    }
}

/// A row's scroll target: its own type, so it can't match another list's ids on the same page.
struct TrackRowAnchor: Hashable { let index: Int }

struct TrackRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let index: Int
    let track: Track
    let context: TrackListContext
    let list: [Track]
    /// The playing song, matched by the table (`PlayingRow`: a relinked copy plays under another id).
    var isCurrent = false
    var showsAlbum = true
    @State private var hovering = false
    /// "New Playlist…" from the row's menu: the table shows the sheet (one per table, not one per row).
    var onNewPlaylist: (Track) -> Void = { _ in }

    var body: some View {
        Group {
            if theme.isPlaylistList { playlistLine } else { card }
        }
        .themedRow(selected: false, hovering: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(context.startsFromTop ? 0.55 : 1)
        .onTapGesture { play() } // a single click plays, as in Spotify
        .contextMenu { TrackContextMenu(track: track, context: context, onPlay: play, onNewPlaylist: { onNewPlaylist(track) }) }
    }

    /// Winamp's playlist editor: `12. Artist - Title`, the album, the heart and the time on one dense line. The
    /// playing song is the playing row's colour (white in Classic), with no icon (winamp window spec).
    private var playlistLine: some View {
        let ink = isCurrent ? theme.accent : theme.text
        return HStack(spacing: 8) {
            Text("\(index + 1).").monospacedDigit().frame(width: 34, alignment: .trailing)
            Text(track.artistLine.isEmpty ? track.name : "\(track.artistLine) - \(track.name)")
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if showsAlbum {
                Text(track.album?.name ?? "").lineLimit(1).frame(width: 190, alignment: .leading)
                    .foregroundStyle(isCurrent ? theme.accent : theme.textSecondary)
            }
            // A real button only under the pointer; otherwise just the heart (a button, its hover tip and hover
            // tracking in every one of ~50 dense rows added up).
            Group {
                if hovering { LikeButton(track: track, ink: ink) }
                else if model.library.isLiked(track) { Image(systemName: "heart.fill").foregroundStyle(ink) }
            }
            .frame(width: 20)
            Text(formatTime(track.durationMs)).monospacedDigit().frame(width: 40, alignment: .trailing)
        }
        .font(theme.listFont(weight: isCurrent ? .semibold : .regular))
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .frame(height: theme.playlistRowHeight)
    }

    private var card: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent && model.player.isPlaying {
                    // Still: an endless symbol effect redraws the window every frame while a song plays.
                    Image(systemName: "waveform")
                } else {
                    Text("\(index + 1)").monospacedDigit()
                }
            }
            .foregroundStyle(isCurrent ? theme.accent : theme.textSecondary)
            .frame(width: 28, alignment: .trailing)
            HStack(spacing: 10) {
                ArtworkView(images: track.album?.images ?? context.fallbackImages, size: theme.rowArtworkSize, corner: theme.artworkRadius)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(theme.font(14, weight: .medium))
                        .foregroundStyle(isCurrent ? theme.accent : theme.text).lineLimit(1)
                    Text(track.artistLine).font(theme.font(12)).themed(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsAlbum {
                Text(track.album?.name ?? "").themed(.secondary).lineLimit(1).frame(width: 190, alignment: .leading)
            }
            // As in the playlist rows: a real button only under the pointer, else just the heart.
            Group {
                if hovering { LikeButton(track: track) }
                else if model.library.isLiked(track) { Image(systemName: "heart.fill").foregroundStyle(theme.accent) }
            }
            .frame(width: 28)
            Text(formatTime(track.durationMs)).monospacedDigit().themed(.secondary).frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: theme.rowHeight)
    }

    func play() {
        AppModel.log.info("row play: \(track.name, privacy: .public)")
        Task {
            if let uri = context.contextURI {
                await model.player.play(.context(uri, startingAt: context.startsFromTop ? nil : track.uri))
            } else {
                await model.player.play(.songs(list.map(\.uri), clicked: track.uri))
            }
        }
    }
}

/// Right-click menu (spec §4.2).
struct TrackContextMenu: View {
    @Environment(AppModel.self) private var model
    let track: Track
    let context: TrackListContext
    let onPlay: () -> Void
    let onNewPlaylist: () -> Void

    var body: some View {
        Button("Play", systemImage: "play.fill", action: onPlay)
        Button("Add to Queue", systemImage: "text.badge.plus") { Task { await model.player.addToQueue(uri: track.uri) } }
        Button("Start Song Radio", systemImage: "dot.radiowaves.left.and.right") { Task { await model.player.startRadio(trackURI: track.uri) } }
        Divider()
        if let album = Album(of: track) {
            Button("Go to Album", systemImage: "square.stack") { model.open(.album(album)) }
        }
        let artists = track.artists.compactMap(Artist.init(ref:))
        if artists.count == 1 {
            Button("Go to Artist", systemImage: "music.mic") { model.open(.artist(artists[0])) }
        } else if artists.count > 1 {
            Menu("Go to Artist", systemImage: "music.mic") {
                ForEach(artists) { artist in Button(artist.name) { model.open(.artist(artist)) } }
            }
        }
        Divider()
        Menu("Add to Playlist", systemImage: "music.note.list") {
            Button("New Playlist…", systemImage: "plus", action: onNewPlaylist)
            Divider()
            ForEach(model.library.editablePlaylists()) { p in
                Button(p.name) { Task { await model.library.add(track, to: p) } }
            }
        }
        if let playlist = context.editablePlaylist {
            Button("Remove from This Playlist", systemImage: "minus.circle") { Task { await model.library.remove(track, from: playlist) } }
        }
        let liked = model.library.isLiked(track)
        Button(liked ? "Unlike" : "Like", systemImage: liked ? "heart.slash" : "heart") { Task { await model.library.toggleLike(track) } }
        if !track.isEpisode {
            MenuBarToggleButton(item: QuickPlayItem(uri: track.uri, name: track.name, subtitle: track.artistLine, images: track.album?.images ?? []))
        }
    }
}
