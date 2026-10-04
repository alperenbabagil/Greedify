import Foundation

/// A playback event from the local librespot, printed by the bundled `greedify-event` script (`--onevent`).
/// While the Mac is the speaker these replace polling the Web API: they cost no quota and arrive at once.
public enum LibrespotEvent: Equatable, Sendable {
    case trackChanged(Track)
    case playing(trackID: String, positionMs: Int)
    case paused(trackID: String, positionMs: Int)
    /// A seek, or librespot correcting its position.
    case seeked(trackID: String, positionMs: Int)
    case stopped
    case sessionDisconnected
    case volume(percent: Int)
    case shuffle(Bool)
    case repeatMode(RepeatMode)
    /// Anything else (loading, preloading, end_of_track, an episode…), by its librespot name.
    case other(String)

    static let prefix = "GREEDIFY-EVENT"
    /// Joins the lines of multi-line values (ARTISTS, COVERS) in the script's output.
    static let lineSeparator: Character = "\u{1F}"

    /// Parses one line of librespot's stdout; nil for anything that isn't an event line.
    public static func parse(_ line: String) -> LibrespotEvent? {
        var fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.first == Substring(prefix) else { return nil }
        fields.removeFirst()
        var env: [String: String] = [:]
        for field in fields {
            guard let eq = field.firstIndex(of: "=") else { continue }
            env[String(field[..<eq])] = String(field[field.index(after: eq)...])
        }
        guard let name = env["PLAYER_EVENT"] else { return nil }
        let id = env["TRACK_ID"] ?? ""
        let position = env["POSITION_MS"].flatMap(Int.init) ?? 0
        switch name {
        case "track_changed":
            switch env["ITEM_TYPE"] {
            case "Track": return track(env).map { .trackChanged($0) } ?? .other(name)
            case "Episode": return episode(env).map { .trackChanged($0) } ?? .other(name)
            default: return .other(name)
            }
        case "playing": return .playing(trackID: id, positionMs: position)
        case "paused": return .paused(trackID: id, positionMs: position)
        case "seeked", "position_correction": return .seeked(trackID: id, positionMs: position)
        case "stopped": return .stopped
        case "session_disconnected": return .sessionDisconnected
        case "volume_changed":
            guard let raw = env["VOLUME"].flatMap(Int.init) else { return .other(name) }
            return .volume(percent: Int((Double(raw) / 65_535 * 100).rounded()))
        case "shuffle_changed": return .shuffle(env["SHUFFLE"] == "true")
        case "repeat_changed":
            return .repeatMode(env["REPEAT_TRACK"] == "true" ? .track : env["REPEAT"] == "true" ? .context : .off)
        default: return .other(name)
        }
    }

    private static func track(_ env: [String: String]) -> Track? {
        guard let id = env["TRACK_ID"], let uri = env["URI"], let name = env["NAME"] else { return nil }
        let artists = lines(env["ARTISTS"]).map { ArtistRef(id: nil, name: $0, uri: "") }
        let covers = lines(env["COVERS"]).compactMap(URL.init(string:)).map { SpotifyImage(url: $0, width: coverWidth($0)) }
        let album = env["ALBUM"].map { AlbumRef(id: nil, name: $0, uri: "", images: covers) }
        return Track(id: id, name: name, uri: uri, durationMs: env["DURATION_MS"].flatMap(Int.init) ?? 0,
                     artists: artists, album: album)
    }

    /// An episode as librespot reports it: the show's name only (its id comes with the next Web API poll).
    private static func episode(_ env: [String: String]) -> Track? {
        guard let bare = track(env), let showName = env["SHOW_NAME"] else { return nil }
        let covers = lines(env["COVERS"]).compactMap(URL.init(string:)).map { SpotifyImage(url: $0, width: coverWidth($0)) }
        return bare.inShow(ShowRef(id: nil, name: showName, uri: "", images: covers))
    }

    private static func lines(_ value: String?) -> [String] {
        (value ?? "").split(separator: lineSeparator).map(String.init)
    }

    /// librespot passes cover URLs without sizes; Spotify's album-art ids encode them.
    private static func coverWidth(_ url: URL) -> Int? {
        let id = url.lastPathComponent
        if id.hasPrefix("ab67616d0000b273") { return 640 }
        if id.hasPrefix("ab67616d00001e02") { return 300 }
        if id.hasPrefix("ab67616d00004851") { return 64 }
        return nil
    }
}
