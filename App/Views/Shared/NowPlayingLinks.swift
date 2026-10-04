import GreedifyKit
import SwiftUI

/// Opens the album a track sits on. Disabled until the album id is known (a few seconds after a track change
/// on the Mac speaker, which reports no ids).
struct AlbumLink<Label: View>: View {
    @Environment(AppModel.self) private var model
    let track: Track?
    @ViewBuilder let label: () -> Label

    private var goTo: String {
        track.map { $0.isEpisode ? "Go to \($0.show?.name ?? "show")" : "Go to \($0.album?.name ?? "album")" } ?? ""
    }

    var body: some View {
        // An episode opens its show; a song its album.
        let destination: Route? = if let track, track.isEpisode {
            track.show.flatMap(Show.init(ref:)).map { .show($0) }
        } else {
            track.flatMap(Album.init(of:)).map { .album($0) }
        }
        Button { if let destination { model.open(destination) } } label: { label() }
            .buttonStyle(.plain)
            .allowsHitTesting(destination != nil)
            .hoverHelp(goTo)
    }
}

/// A track's artists, each opening its own page.
struct ArtistLinks: View {
    @Environment(AppModel.self) private var model
    let track: Track?
    let placeholder: String

    var body: some View {
        if let track, track.isEpisode, let name = track.show?.name {
            let show = track.show.flatMap(Show.init(ref:))
            Button(name) { if let show { model.open(.show(show)) } }
                .buttonStyle(.plain)
                .allowsHitTesting(show != nil)
                .lineLimit(1)
        } else if let track, !track.artists.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(track.artists.enumerated()), id: \.offset) { index, ref in
                    if index > 0 { Text(", ") }
                    let artist = Artist(ref: ref)
                    Button(ref.name) { if let artist { model.open(.artist(artist)) } }
                        .buttonStyle(.plain)
                        .allowsHitTesting(artist != nil)
                        .hoverHelp(artist == nil ? "" : "Go to \(ref.name)")
                        .layoutPriority(index == 0 ? 1 : 0)
                }
            }
            .lineLimit(1)
        } else {
            Text(placeholder).lineLimit(1)
        }
    }
}
