import Foundation
@testable import GreedifyKit

/// In-memory `SpotifyAPI` for store tests. Configure the `var`s, inspect `calls`.
actor FakeSpotifyAPI: SpotifyAPI {
    var calls: [String] = []
    var state: PlaybackState?
    var deviceList: [Device] = []
    var errorsQueue: [SpotifyError] = []   // thrown by the next commands, in order
    var user = SpotifyUser(id: "me", displayName: "Me")
    var playlistPages: [Paging<Playlist>] = []
    var itemsByPlaylist: [String: [PlaylistItem]] = [:]
    var searchResult = SearchResults(tracks: nil, albums: nil, artists: nil, playlists: nil)
    var containsResult: [Bool] = []
    var nextSnapshot = "s2"

    func set(state: PlaybackState?) { self.state = state }
    func set(devices: [Device]) { deviceList = devices }
    func enqueue(_ e: SpotifyError) { errorsQueue.append(e) }
    func set(playlistPages: [Paging<Playlist>]) { self.playlistPages = playlistPages }
    func set(items: [PlaylistItem], for id: String) { itemsByPlaylist[id] = items }
    func set(search: SearchResults) { searchResult = search }
    func set(contains: [Bool]) { containsResult = contains }

    var showPages: [Paging<SavedShow>] = []
    var episodePages: [String: [Paging<Track>]] = [:]
    var savedEpisodePages: [Paging<SavedEpisode>] = []
    func set(showPages: [Paging<SavedShow>]) { self.showPages = showPages }
    func set(episodePages: [Paging<Track>], for id: String) { self.episodePages[id] = episodePages }
    func set(savedEpisodePages: [Paging<SavedEpisode>]) { self.savedEpisodePages = savedEpisodePages }
    var failures: [(prefix: String, error: any Error)] = []
    var saved: [SavedTrack] = []
    var failItemsAtOffset: Int?
    func fail(_ prefix: String, with error: SpotifyError) { failures.append((prefix, error)) }
    func fail(_ prefix: String, throwing error: any Error) { failures.append((prefix, error)) }
    func set(saved: [SavedTrack]) { self.saved = saved }
    func set(failItemsAtOffset: Int?) { self.failItemsAtOffset = failItemsAtOffset }

    private func log(_ s: String) throws {
        calls.append(s)
        if let i = failures.firstIndex(where: { s.hasPrefix($0.prefix) }) { throw failures.remove(at: i).error }
        if !errorsQueue.isEmpty { throw errorsQueue.removeFirst() }
    }

    func playbackState() async throws -> PlaybackState? { try log("state"); return state }
    func devices() async throws -> [Device] { calls.append("devices"); return deviceList }
    var lastPlay: PlayRequest?
    func play(_ request: PlayRequest, deviceID: String?) async throws {
        lastPlay = request
        try log("play(\(request.contextURI ?? request.uris?.joined(separator: ",") ?? "resume"),\(deviceID ?? "nil"))")
    }
    func pause() async throws { try log("pause") }
    func next() async throws { try log("next") }
    func previous() async throws { try log("previous") }
    func seek(toMs: Int) async throws { try log("seek(\(toMs))") }
    func setVolume(_ percent: Int) async throws { try log("volume(\(percent))") }
    func setShuffle(_ on: Bool) async throws { try log("shuffle(\(on))") }
    func setRepeat(_ mode: RepeatMode) async throws { try log("repeat(\(mode.rawValue))") }
    func transferPlayback(to deviceID: String, play: Bool) async throws { try log("transfer(\(deviceID),\(play))") }
    func addToQueue(uri: String) async throws { try log("queue(\(uri))") }
    var upNext: [Track] = []
    func set(upNext: [Track]) { self.upNext = upNext }
    func queue() async throws -> QueueResponse { try log("getQueue"); return QueueResponse(currentlyPlaying: state?.item, queue: upNext) }

    func currentUser() async throws -> SpotifyUser { try log("me"); return user }
    func myPlaylists(offset: Int, limit: Int) async throws -> Paging<Playlist> {
        try log("playlists(\(offset))")
        return playlistPages.isEmpty ? Paging(items: [], next: nil, offset: 0, limit: limit, total: 0) : playlistPages.removeFirst()
    }
    func playlist(id: String) async throws -> Playlist { throw SpotifyError.notFound }
    var embedTracks: [String: [Track]] = [:]
    func set(embed: [Track]?, for id: String) { embedTracks[id] = embed }
    func publicPlaylistTracks(id: String) async throws -> [Track] {
        try log("embed(\(id))")
        guard let tracks = embedTracks[id] else { throw SpotifyError.transport("embed failed") }
        return tracks
    }
    func playlistItems(id: String, offset: Int, limit: Int) async throws -> Paging<PlaylistItem> {
        try log("items(\(id),\(offset))")
        if offset == failItemsAtOffset { throw SpotifyError.transport("page failed") }
        let all = itemsByPlaylist[id] ?? []
        let slice = Array(all.dropFirst(offset).prefix(limit))
        let more = offset + slice.count < all.count
        return Paging(items: slice, next: more ? URL(string: "https://next")! : nil, offset: offset, limit: limit, total: all.count)
    }
    func savedTracks(offset: Int, limit: Int) async throws -> Paging<SavedTrack> {
        try log("liked(\(offset))")
        let slice = Array(saved.dropFirst(offset).prefix(limit))
        return Paging(items: slice, next: offset + slice.count < saved.count ? URL(string: "https://n") : nil,
                      offset: offset, limit: limit, total: saved.count)
    }
    func savedAlbums(offset: Int, limit: Int) async throws -> Paging<SavedAlbum> {
        try log("albums(\(offset))"); return Paging(items: [], next: nil, offset: offset, limit: limit, total: 0)
    }
    func followedArtists(after: String?, limit: Int) async throws -> CursorPaging<Artist> {
        try log("artists"); return CursorPaging(items: [], next: nil, cursors: nil, total: 0)
    }
    func albumTracks(id: String, offset: Int, limit: Int) async throws -> Paging<Track> {
        try log("albumTracks(\(id))"); return Paging(items: [], next: nil, offset: 0, limit: limit, total: 0)
    }
    func artistAlbums(id: String, offset: Int, limit: Int) async throws -> Paging<Album> {
        try log("artistAlbums(\(id))"); return Paging(items: [], next: nil, offset: 0, limit: limit, total: 0)
    }
    func artist(id: String) async throws -> Artist {
        try log("artist(\(id))"); return Artist(id: id, name: "Artist", uri: "spotify:artist:\(id)", images: nil)
    }
    func savedShows(offset: Int, limit: Int) async throws -> Paging<SavedShow> {
        try log("shows(\(offset))")
        return showPages.isEmpty ? Paging(items: [], next: nil, offset: offset, limit: limit, total: 0) : showPages.removeFirst()
    }
    func showEpisodes(id: String, offset: Int, limit: Int) async throws -> Paging<Track> {
        try log("episodes(\(id),\(offset))")
        guard var pages = episodePages[id], !pages.isEmpty else { return Paging(items: [], next: nil, offset: offset, limit: limit, total: 0) }
        let page = pages.removeFirst(); episodePages[id] = pages
        return page
    }
    func savedEpisodes(offset: Int, limit: Int) async throws -> Paging<SavedEpisode> {
        try log("savedEpisodes(\(offset))")
        return savedEpisodePages.isEmpty ? Paging(items: [], next: nil, offset: offset, limit: limit, total: 0) : savedEpisodePages.removeFirst()
    }
    func show(id: String) async throws -> Show {
        try log("show(\(id))"); return Show(id: id, name: "Show", uri: "spotify:show:\(id)", images: [], totalEpisodes: nil, description: nil)
    }
    func saveToLibrary(uris: [String]) async throws { try log("save(\(uris.joined(separator: ",")))") }
    func removeFromLibrary(uris: [String]) async throws { try log("unsave(\(uris.joined(separator: ",")))") }
    func libraryContains(uris: [String]) async throws -> [Bool] { try log("contains(\(uris.count))"); return containsResult }
    func addToPlaylist(id: String, uris: [String]) async throws -> String { try log("add(\(id),\(uris.joined()))"); return nextSnapshot }
    func removeFromPlaylist(id: String, uris: [String], snapshotID: String?) async throws -> String {
        try log("remove(\(id),\(uris.joined()),\(snapshotID ?? "nil"))"); return nextSnapshot
    }
    func createPlaylist(name: String, isPublic: Bool) async throws -> Playlist {
        try log("create(\(name),\(isPublic))")
        return Playlist(id: "new", name: name, uri: "spotify:playlist:new", images: [], owner: PlaylistOwner(id: "me", displayName: nil),
                        collaborative: false, snapshotId: "s0", trackCount: 0)
    }
    func search(_ query: String, types: [SearchType], offset: Int, limit: Int) async throws -> SearchResults {
        try log("search(\(query),\(types.map(\.rawValue).joined(separator: "+")),\(offset))"); return searchResult
    }
}

/// A settable clock for `now:` injection.
final class TestNow: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}
