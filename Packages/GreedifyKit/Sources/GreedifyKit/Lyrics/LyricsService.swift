import Foundation

/// Lyrics from LRCLIB (https://lrclib.net), cached per Spotify track ID.
public actor LyricsService {
    let transport: HTTPTransport
    let cache: DataCache
    let now: @Sendable () -> Date
    static let base = URL(string: "https://lrclib.net/api")!
    static let notFoundTTL: TimeInterval = 7 * 24 * 3600

    public init(transport: HTTPTransport, cache: DataCache, now: @escaping @Sendable () -> Date = Date.init) {
        self.transport = transport; self.cache = cache; self.now = now
    }

    struct LRCLIBRecord: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    struct CacheEntry: Codable {
        let synced: String?
        let plain: String?
        let storedAt: Date
    }

    public func lyrics(for track: Track) async -> Lyrics {
        let key = "lyrics:\(track.id)"
        if let entry = await cache.value(CacheEntry.self, for: key) {
            let result = Self.lyrics(synced: entry.synced, plain: entry.plain)
            let expired = result == .none && now().timeIntervalSince(entry.storedAt) > Self.notFoundTTL
            if !expired { return result }
        }
        guard let record = await fetch(track) else { return .none } // network error: don't cache
        let entry = CacheEntry(synced: record.syncedLyrics, plain: record.plainLyrics, storedAt: now())
        await cache.store(entry, for: key)
        return Self.lyrics(synced: entry.synced, plain: entry.plain)
    }

    static func lyrics(synced: String?, plain: String?) -> Lyrics {
        if let synced, case let lines = LRCParser.parse(synced), !lines.isEmpty { return .synced(lines) }
        if let plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(plain) }
        return .none
    }

    /// Exact match via `/get`; falls back to the first `/search` hit. Returns an empty record on 404.
    func fetch(_ track: Track) async -> LRCLIBRecord? {
        let artist = track.artists.first?.name ?? ""
        var get = URLComponents(url: Self.base.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        get.queryItems = [
            .init(name: "track_name", value: track.name),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: track.album?.name ?? ""),
            .init(name: "duration", value: String(track.durationMs / 1000)),
        ]
        switch await request(get.url!) {
        case .ok(let data):
            if let record = try? SpotifyJSON.decoder.decode(LRCLIBRecord.self, from: data) { return record }
        case .notFound: break
        case .failed: return nil
        }
        var search = URLComponents(url: Self.base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        search.queryItems = [.init(name: "track_name", value: track.name), .init(name: "artist_name", value: artist)]
        switch await request(search.url!) {
        case .ok(let data):
            let hits = (try? SpotifyJSON.decoder.decode([LRCLIBRecord].self, from: data)) ?? []
            return hits.first { $0.syncedLyrics != nil } ?? hits.first ?? LRCLIBRecord(syncedLyrics: nil, plainLyrics: nil, instrumental: nil)
        case .notFound: return LRCLIBRecord(syncedLyrics: nil, plainLyrics: nil, instrumental: nil)
        case .failed: return nil
        }
    }

    enum Outcome { case ok(Data), notFound, failed }

    func request(_ url: URL) async -> Outcome {
        var req = URLRequest(url: url)
        req.setValue("Greedify/1.0 (personal macOS client)", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await transport.send(req) else { return .failed }
        switch http.statusCode {
        case 200..<300: return .ok(data)
        case 404: return .notFound
        default: return .failed
        }
    }
}
