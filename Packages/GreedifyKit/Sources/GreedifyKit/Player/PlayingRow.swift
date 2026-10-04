import Foundation

/// Which row of a song list is the playing song.
public enum PlayingRow {
    /// The row with the playing song's id; else one with its title and first artist. Spotify relinks a song to a
    /// playable copy for the listener's country, so what plays can carry another id than the list's row (One by
    /// Metallica played as `02xh…` from a playlist holding `5IX4…`). The artist is matched by name: the speaker's
    /// events carry no artist ids.
    public static func index(of playing: Track?, in tracks: [Track]) -> Int? {
        guard let playing else { return nil }
        if let exact = tracks.firstIndex(where: { $0.id == playing.id }) { return exact }
        guard let artist = playing.artists.first?.name else { return nil }
        return tracks.firstIndex { track in
            track.name.caseInsensitiveCompare(playing.name) == .orderedSame
                && track.artists.first?.name.caseInsensitiveCompare(artist) == .orderedSame
        }
    }
}
