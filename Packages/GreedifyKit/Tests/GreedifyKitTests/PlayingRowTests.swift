import Testing
@testable import GreedifyKit

/// Which row of a song list is the playing song, including a relinked copy (another id for the same song).
struct PlayingRowTests {
    func song(_ id: String, _ name: String, by artist: String, artistID: String? = "a") -> Track {
        Track(id: id, name: name, uri: "spotify:track:\(id)", durationMs: 1000,
              artists: [ArtistRef(id: artistID, name: artist, uri: "")], album: nil)
    }

    @Test func theSameIDMatches() {
        let list = [song("1", "Battery", by: "Metallica"), song("2", "One", by: "Metallica")]
        #expect(PlayingRow.index(of: song("2", "One", by: "Metallica"), in: list) == 1)
    }

    /// Spotify plays a playable copy for the listener's country: other id, same title and artist. The speaker's
    /// events carry no artist ids, so the artist is matched by name.
    @Test func aRelinkedCopyMatchesByTitleAndArtist() {
        let list = [song("1", "Battery", by: "Metallica"), song("5IX4", "One", by: "Metallica")]
        #expect(PlayingRow.index(of: song("02xh", "one", by: "Metallica", artistID: nil), in: list) == 1)
    }

    @Test func anExactIDWinsOverATitleMatch() {
        let list = [song("live", "One", by: "Metallica"), song("studio", "One", by: "Metallica")]
        #expect(PlayingRow.index(of: song("studio", "One", by: "Metallica"), in: list) == 1)
    }

    @Test func anotherArtistsSongWithTheSameTitleDoesntMatch() {
        let list = [song("u2", "One", by: "U2")]
        #expect(PlayingRow.index(of: song("02xh", "One", by: "Metallica"), in: list) == nil)
        #expect(PlayingRow.index(of: nil, in: list) == nil)
    }
}
