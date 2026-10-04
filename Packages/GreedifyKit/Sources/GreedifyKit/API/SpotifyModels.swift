import Foundation

/// Decoder shared by every Spotify response: snake_case keys map to camelCase properties.
public enum SpotifyJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}

/// Decodes `T`, or `nil` if the element is null or malformed. Spotify returns `null`
/// entries in some lists (e.g. search playlists), which would fail a plain `[T]`.
struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

public struct SpotifyImage: Codable, Hashable, Sendable {
    public let url: URL
    public let width: Int?
    public let height: Int?
    public init(url: URL, width: Int? = nil, height: Int? = nil) {
        self.url = url; self.width = width; self.height = height
    }
}

extension Array where Element == SpotifyImage {
    /// The smallest image at least `minSide` px wide, else the largest available.
    public func best(minSide: Int = 300) -> SpotifyImage? {
        let sized = sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return sized.first { ($0.width ?? 0) >= minSide } ?? sized.last
    }
}

public struct ArtistRef: Codable, Hashable, Sendable {
    public let id: String?
    public let name: String
    public let uri: String
    public init(id: String?, name: String, uri: String) { self.id = id; self.name = name; self.uri = uri }
}

public struct AlbumRef: Codable, Hashable, Sendable {
    public let id: String?
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]
    public init(id: String?, name: String, uri: String, images: [SpotifyImage]) {
        self.id = id; self.name = name; self.uri = uri; self.images = images
    }
}

public enum ItemKind: String, Codable, Sendable { case track, episode }

/// The show an episode belongs to: the part of `Show` an episode carries.
public struct ShowRef: Codable, Hashable, Sendable {
    public let id: String?
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]
    public init(id: String?, name: String, uri: String, images: [SpotifyImage]) {
        self.id = id; self.name = name; self.uri = uri; self.images = images
    }
}

/// Where the user stopped in an episode (needs the `user-read-playback-position` scope).
public struct ResumePoint: Codable, Hashable, Sendable {
    public let fullyPlayed: Bool
    public let resumePositionMs: Int
    public init(fullyPlayed: Bool, resumePositionMs: Int) { self.fullyPlayed = fullyPlayed; self.resumePositionMs = resumePositionMs }
}

/// A song, or a podcast episode (`kind == .episode`, podcasts spec §3): an episode's show stands in for its artist
/// and album, so every surface that shows a track shows an episode too.
public struct Track: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let durationMs: Int
    public let artists: [ArtistRef]
    /// `nil` for tracks listed inside an album response.
    public let album: AlbumRef?
    public var kind: ItemKind = .track
    public var show: ShowRef?
    public var releaseDate: String?
    public var resumePoint: ResumePoint?
    public var isPlayable: Bool?

    public init(id: String, name: String, uri: String, durationMs: Int, artists: [ArtistRef], album: AlbumRef?) {
        self.id = id; self.name = name; self.uri = uri; self.durationMs = durationMs
        self.artists = artists; self.album = album
    }

    public var artistLine: String { artists.map(\.name).joined(separator: ", ") }
    public var isEpisode: Bool { kind == .episode }
    /// Where playing starts: the resume point, the beginning when it was played to the end, or nil when Spotify didn't
    /// say (a token without the playback-position scope), so the play request leaves the position to Spotify.
    public var startPositionMs: Int? {
        guard let resumePoint else { return nil }
        return resumePoint.fullyPlayed ? 0 : resumePoint.resumePositionMs
    }

    /// This episode as part of `show` (a show's own episode list carries no show object).
    public func inShow(_ show: ShowRef) -> Track {
        let images = album?.images.isEmpty == false ? album!.images : show.images
        var t = Track(id: id, name: name, uri: uri, durationMs: durationMs,
                      artists: [ArtistRef(id: nil, name: show.name, uri: "")],
                      album: AlbumRef(id: nil, name: show.name, uri: show.uri, images: images))
        t.kind = .episode; t.show = show; t.releaseDate = releaseDate; t.resumePoint = resumePoint; t.isPlayable = isPlayable
        return t
    }
}

extension Track: Codable {
    enum CodingKeys: String, CodingKey { case id, name, uri, durationMs, artists, album, kind, show, releaseDate, resumePoint, isPlayable, type, images }

    /// Reads Spotify's tracks and episodes (snake_case, via `SpotifyJSON.decoder`) and Greedify's own saved tracks.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        uri = try c.decode(String.self, forKey: .uri)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        show = try? c.decodeIfPresent(ShowRef.self, forKey: .show)
        releaseDate = try? c.decodeIfPresent(String.self, forKey: .releaseDate)
        resumePoint = try? c.decodeIfPresent(ResumePoint.self, forKey: .resumePoint)
        isPlayable = try? c.decodeIfPresent(Bool.self, forKey: .isPlayable)
        let type = try? c.decodeIfPresent(String.self, forKey: .type)
        kind = (try? c.decodeIfPresent(ItemKind.self, forKey: .kind)) ?? (type == "episode" ? .episode : .track)
        if let artists = try? c.decodeIfPresent([ArtistRef].self, forKey: .artists) {
            self.artists = artists
            album = try? c.decodeIfPresent(AlbumRef.self, forKey: .album)
        } else if kind == .episode {
            // A Spotify episode: the show stands in for artist and album.
            let images = (try? c.decodeIfPresent([SpotifyImage].self, forKey: .images)) ?? show?.images ?? []
            artists = [ArtistRef(id: nil, name: show?.name ?? "", uri: "")]
            album = AlbumRef(id: nil, name: show?.name ?? "", uri: show?.uri ?? "", images: images)
        } else {
            throw DecodingError.keyNotFound(CodingKeys.artists, .init(codingPath: c.codingPath, debugDescription: "a track needs artists"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(uri, forKey: .uri)
        try c.encode(durationMs, forKey: .durationMs); try c.encode(artists, forKey: .artists)
        try c.encodeIfPresent(album, forKey: .album); try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(show, forKey: .show); try c.encodeIfPresent(releaseDate, forKey: .releaseDate)
        try c.encodeIfPresent(resumePoint, forKey: .resumePoint); try c.encodeIfPresent(isPlayable, forKey: .isPlayable)
    }
}

/// A podcast (podcasts spec §3.2). Development mode no longer returns `publisher`.
public struct Show: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]
    public let totalEpisodes: Int?
    public let description: String?

    public init(id: String, name: String, uri: String, images: [SpotifyImage], totalEpisodes: Int?, description: String?) {
        self.id = id; self.name = name; self.uri = uri; self.images = images
        self.totalEpisodes = totalEpisodes; self.description = description
    }

    /// A show page from an episode's show, once its id is known.
    public init?(ref: ShowRef) {
        guard let id = ref.id else { return nil }
        self.init(id: id, name: ref.name, uri: ref.uri.isEmpty ? "spotify:show:\(id)" : ref.uri, images: ref.images,
                  totalEpisodes: nil, description: nil)
    }

    public var ref: ShowRef { ShowRef(id: id, name: name, uri: uri, images: images) }
}

public struct SavedShow: Codable, Sendable { public let show: Show }
public struct SavedEpisode: Codable, Sendable { public let episode: Track }

public struct Album: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]
    public let artists: [ArtistRef]
    public let totalTracks: Int?
}

public struct Artist: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]?
}

extension Album {
    /// The album a track sits on, for opening its page: the track already carries everything the page shows.
    /// `nil` until the album id is known (librespot reports none).
    public init?(of track: Track) {
        guard let ref = track.album, let id = ref.id else { return nil }
        self.init(id: id, name: ref.name, uri: ref.uri, images: ref.images, artists: track.artists, totalTracks: nil)
    }
}

extension Artist {
    /// An artist page from a track's artist; the photo is fetched by the page. `nil` until the id is known.
    public init?(ref: ArtistRef) {
        guard let id = ref.id else { return nil }
        self.init(id: id, name: ref.name, uri: ref.uri.isEmpty ? "spotify:artist:\(id)" : ref.uri, images: nil)
    }
}

public struct PlaylistOwner: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String?
}

public struct Playlist: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let uri: String
    public let images: [SpotifyImage]
    public let owner: PlaylistOwner
    public let collaborative: Bool
    public let snapshotId: String
    public let trackCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, uri, images, owner, collaborative, snapshotId, tracks, items
    }
    struct CountRef: Codable { let total: Int }

    public init(id: String, name: String, uri: String, images: [SpotifyImage], owner: PlaylistOwner,
                collaborative: Bool, snapshotId: String, trackCount: Int) {
        self.id = id; self.name = name; self.uri = uri; self.images = images; self.owner = owner
        self.collaborative = collaborative; self.snapshotId = snapshotId; self.trackCount = trackCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        uri = try c.decode(String.self, forKey: .uri)
        images = (try? c.decodeIfPresent([SpotifyImage].self, forKey: .images)) ?? []
        owner = try c.decode(PlaylistOwner.self, forKey: .owner)
        collaborative = (try? c.decodeIfPresent(Bool.self, forKey: .collaborative)) ?? false
        snapshotId = try c.decode(String.self, forKey: .snapshotId)
        // The Feb 2026 rename moved some `tracks` fields to `items`; accept either.
        let ref = (try? c.decodeIfPresent(CountRef.self, forKey: .items))
            ?? (try? c.decodeIfPresent(CountRef.self, forKey: .tracks))
        trackCount = ref?.total ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(uri, forKey: .uri)
        try c.encode(images, forKey: .images); try c.encode(owner, forKey: .owner)
        try c.encode(collaborative, forKey: .collaborative); try c.encode(snapshotId, forKey: .snapshotId)
        try c.encode(CountRef(total: trackCount), forKey: .items)
    }

    public func isEditable(by userID: String) -> Bool { owner.id == userID || collaborative }
}

public struct PlaylistItem: Codable, Hashable, Sendable {
    public let addedAt: String?
    /// `nil` for episodes, local files and removed tracks.
    public let track: Track?

    enum CodingKeys: String, CodingKey { case addedAt, item, track }

    public init(addedAt: String?, track: Track?) { self.addedAt = addedAt; self.track = track }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addedAt = try? c.decodeIfPresent(String.self, forKey: .addedAt)
        track = (try? c.decodeIfPresent(Track.self, forKey: .item))
            ?? (try? c.decodeIfPresent(Track.self, forKey: .track))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(addedAt, forKey: .addedAt)
        try c.encodeIfPresent(track, forKey: .item)
    }
}

public struct SavedTrack: Codable, Hashable, Sendable {
    public let addedAt: String?
    public let track: Track
}

public struct SavedAlbum: Codable, Hashable, Sendable {
    public let addedAt: String?
    public let album: Album
}

public struct Paging<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let next: URL?
    public let offset: Int
    public let limit: Int
    public let total: Int

    enum CodingKeys: String, CodingKey { case items, next, offset, limit, total }

    public init(items: [T], next: URL?, offset: Int, limit: Int, total: Int) {
        self.items = items; self.next = next; self.offset = offset; self.limit = limit; self.total = total
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([Failable<T>].self, forKey: .items).compactMap(\.value)
        next = try c.decodeIfPresent(URL.self, forKey: .next)
        offset = try c.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? items.count
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
    }

    public var hasMore: Bool { next != nil }
}

public struct CursorPaging<T: Codable & Sendable>: Codable, Sendable {
    public struct Cursors: Codable, Sendable { public let after: String? }
    public let items: [T]
    public let next: URL?
    public let cursors: Cursors?
    public let total: Int?
}

public struct FollowedArtistsResponse: Codable, Sendable {
    public let artists: CursorPaging<Artist>
}

public struct SpotifyUser: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String?
}

public struct Device: Codable, Hashable, Sendable, Identifiable {
    public let id: String?
    public let name: String
    public let type: String
    public let isActive: Bool
    public let volumePercent: Int?
    public init(id: String?, name: String, type: String, isActive: Bool, volumePercent: Int?) {
        self.id = id; self.name = name; self.type = type; self.isActive = isActive; self.volumePercent = volumePercent
    }
}

public struct DevicesResponse: Codable, Sendable { public let devices: [Device] }

public struct PlaybackContext: Codable, Hashable, Sendable {
    public let uri: String
    public let type: String
}

public enum RepeatMode: String, Codable, Sendable, CaseIterable { case off, context, track }

public struct PlaybackState: Codable, Hashable, Sendable {
    public let device: Device?
    public let isPlaying: Bool
    public let progressMs: Int?
    /// `nil` when an ad or nothing is playing (episodes need `additional_types=episode`).
    public let item: Track?
    public let shuffleState: Bool?
    public let repeatState: RepeatMode?
    public let context: PlaybackContext?

    enum CodingKeys: String, CodingKey { case device, isPlaying, progressMs, item, shuffleState, repeatState, context }

    public init(device: Device?, isPlaying: Bool, progressMs: Int?, item: Track?,
                shuffleState: Bool? = nil, repeatState: RepeatMode? = nil, context: PlaybackContext? = nil) {
        self.device = device; self.isPlaying = isPlaying; self.progressMs = progressMs; self.item = item
        self.shuffleState = shuffleState; self.repeatState = repeatState; self.context = context
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try? c.decodeIfPresent(Device.self, forKey: .device)
        isPlaying = (try? c.decodeIfPresent(Bool.self, forKey: .isPlaying)) ?? false
        progressMs = try? c.decodeIfPresent(Int.self, forKey: .progressMs)
        item = try? c.decodeIfPresent(Track.self, forKey: .item)
        shuffleState = try? c.decodeIfPresent(Bool.self, forKey: .shuffleState)
        repeatState = try? c.decodeIfPresent(RepeatMode.self, forKey: .repeatState)
        context = try? c.decodeIfPresent(PlaybackContext.self, forKey: .context)
    }
}

public enum SearchType: String, Sendable, CaseIterable { case track, album, artist, playlist, show, episode }

public struct SearchResults: Codable, Sendable {
    public let tracks: Paging<Track>?
    public let albums: Paging<Album>?
    public let artists: Paging<Artist>?
    public let playlists: Paging<Playlist>?
    public var shows: Paging<Show>? = nil
    public var episodes: Paging<Track>? = nil
}

public struct QueueResponse: Codable, Sendable {
    public let currentlyPlaying: Track?
    /// Songs and episodes.
    public let queue: [Track]

    enum CodingKeys: String, CodingKey { case currentlyPlaying, queue }

    public init(currentlyPlaying: Track?, queue: [Track]) { self.currentlyPlaying = currentlyPlaying; self.queue = queue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentlyPlaying = try? c.decodeIfPresent(Track.self, forKey: .currentlyPlaying)
        queue = ((try? c.decodeIfPresent([Failable<Track>].self, forKey: .queue)) ?? []).compactMap(\.value)
    }
}

public struct SnapshotResponse: Codable, Sendable { public let snapshotId: String }

/// What to start playing. Exactly one of `contextURI` or `uris` is set.
public struct PlayRequest: Equatable, Sendable {
    public var contextURI: String?
    public var uris: [String]?
    public var offsetURI: String?
    public var positionMs: Int?

    public static func context(_ uri: String, startingAt trackURI: String? = nil) -> PlayRequest {
        PlayRequest(contextURI: uri, uris: nil, offsetURI: trackURI, positionMs: nil)
    }
    /// A list of songs, started at `trackURI`. Name it whenever shuffle may be on: without an offset Spotify starts
    /// a shuffled list at a random song.
    public static func tracks(_ uris: [String], startingAt trackURI: String? = nil) -> PlayRequest {
        PlayRequest(contextURI: nil, uris: uris, offsetURI: trackURI, positionMs: nil)
    }
    /// A click on a song in a list with no context (search results): the whole list when it fits the 100 songs a play
    /// takes (so shuffle draws from all of it and previous goes back), else 100 from the clicked one (or the last 100).
    public static func songs(_ uris: [String], clicked: String) -> PlayRequest {
        let start = uris.firstIndex(of: clicked) ?? 0
        let lower = max(0, min(start, uris.count - 100))
        return .tracks(Array(uris[lower..<min(uris.count, lower + 100)]), startingAt: clicked)
    }
    /// One episode from `positionMs` (nil: wherever Spotify has it), optionally followed by `next`: episodes can't be
    /// started inside a show context at a chosen episode, and a follower sent here needs no queueing.
    public static func episode(_ uri: String, at positionMs: Int?, then next: String? = nil) -> PlayRequest {
        PlayRequest(contextURI: nil, uris: [uri] + [next].compactMap { $0 }, offsetURI: nil, positionMs: positionMs)
    }
    /// Resume whatever the device had loaded.
    public static let resume = PlayRequest(contextURI: nil, uris: nil, offsetURI: nil, positionMs: nil)

    var jsonBody: [String: Any]? {
        var body: [String: Any] = [:]
        if let contextURI { body["context_uri"] = contextURI }
        if let uris { body["uris"] = uris }
        if let offsetURI { body["offset"] = ["uri": offsetURI] }
        if let positionMs { body["position_ms"] = positionMs }
        return body.isEmpty ? nil : body
    }
}
