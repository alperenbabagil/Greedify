import Foundation

/// Everything Greedify asks of the Spotify Web API. Stores depend on this protocol only.
public protocol SpotifyAPI: Sendable {
    // Player
    func playbackState() async throws -> PlaybackState?
    func devices() async throws -> [Device]
    func play(_ request: PlayRequest, deviceID: String?) async throws
    func pause() async throws
    func next() async throws
    func previous() async throws
    func seek(toMs: Int) async throws
    func setVolume(_ percent: Int) async throws
    func setShuffle(_ on: Bool) async throws
    func setRepeat(_ mode: RepeatMode) async throws
    func transferPlayback(to deviceID: String, play: Bool) async throws
    func addToQueue(uri: String) async throws
    func queue() async throws -> QueueResponse

    // Library
    func currentUser() async throws -> SpotifyUser
    func myPlaylists(offset: Int, limit: Int) async throws -> Paging<Playlist>
    func playlist(id: String) async throws -> Playlist
    func playlistItems(id: String, offset: Int, limit: Int) async throws -> Paging<PlaylistItem>
    /// The first 100 songs of any public playlist, from open.spotify.com's embed page (no token, unofficial).
    func publicPlaylistTracks(id: String) async throws -> [Track]
    func savedTracks(offset: Int, limit: Int) async throws -> Paging<SavedTrack>
    func savedAlbums(offset: Int, limit: Int) async throws -> Paging<SavedAlbum>
    func followedArtists(after: String?, limit: Int) async throws -> CursorPaging<Artist>
    func albumTracks(id: String, offset: Int, limit: Int) async throws -> Paging<Track>
    func artistAlbums(id: String, offset: Int, limit: Int) async throws -> Paging<Album>
    func artist(id: String) async throws -> Artist
    func savedShows(offset: Int, limit: Int) async throws -> Paging<SavedShow>
    func showEpisodes(id: String, offset: Int, limit: Int) async throws -> Paging<Track>
    func savedEpisodes(offset: Int, limit: Int) async throws -> Paging<SavedEpisode>
    func show(id: String) async throws -> Show
    func saveToLibrary(uris: [String]) async throws
    func removeFromLibrary(uris: [String]) async throws
    func libraryContains(uris: [String]) async throws -> [Bool]
    func addToPlaylist(id: String, uris: [String]) async throws -> String
    func removeFromPlaylist(id: String, uris: [String], snapshotID: String?) async throws -> String
    func createPlaylist(name: String, isPublic: Bool) async throws -> Playlist

    // Search
    func search(_ query: String, types: [SearchType], offset: Int, limit: Int) async throws -> SearchResults
}
