import Foundation

/// A Daily Mix (or any playlist) the user pasted by link. Played by URI; its tracks can't be listed,
/// so they're collected from the playback queue while it plays (`MixTracks`).
public struct MixLink: Codable, Hashable, Sendable, Identifiable {
    public let uri: String
    public var name: String
    public var id: String { uri }

    public init(uri: String, name: String) { self.uri = uri; self.name = name }

    /// Accepts `https://open.spotify.com/playlist/<id>?si=…` (optionally with `/intl-xx/`) or `spotify:playlist:<id>`.
    public static func uri(fromLink link: String) -> String? {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("spotify:playlist:") {
            let id = s.dropFirst("spotify:playlist:".count)
            return isID(id) ? s : nil
        }
        guard let url = URL(string: s), url.host == "open.spotify.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(of: "playlist"), i + 1 < parts.count, isID(parts[i + 1]) else { return nil }
        return "spotify:playlist:\(parts[i + 1])"
    }

    static func isID<S: StringProtocol>(_ s: S) -> Bool {
        s.count == 22 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

/// A mix's songs as last seen in the playback queue. Stored apart from `MixLink` so a mix's
/// identity (its sidebar selection) doesn't change when its songs do.
///
/// Spotify won't let apps read a mix, so its songs are only learnt while it plays. A Daily Mix changes
/// "within a day of when you last listened", reshuffled after hours unplayed; Discover Weekly refreshes on
/// Mondays and Release Radar on Fridays. So a new play after a long gap, or past the refresh day, starts over.
public struct MixTracks: Codable, Sendable {
    public var tracks: [Track]
    /// When collecting started.
    public var startedAt: Date
    /// The last recording; `nil` in lists saved before it was kept.
    var lastCapturedAt: Date?

    init(tracks: [Track], startedAt: Date, lastCapturedAt: Date? = nil) {
        self.tracks = tracks; self.startedAt = startedAt; self.lastCapturedAt = lastCapturedAt
    }

    /// When the list was last seen in the queue.
    public var capturedAt: Date { lastCapturedAt ?? startedAt }

    /// Unplayed this long, Spotify has likely changed the mix: the next play replaces the list.
    static let refreshGap: TimeInterval = 8 * 3600
    static let maxCount = 200

    /// Whether playing the mix now would show a different list than the one saved.
    public func isOutdated(at date: Date, name: String, calendar: Calendar = .current) -> Bool {
        if date.timeIntervalSince(capturedAt) >= Self.refreshGap { return true }
        guard let day = Self.refreshWeekday(name: name) else { return false }
        return capturedAt < Self.start(of: day, atOrBefore: date, calendar: calendar)
    }

    /// Adds `seen` (the current song plus the queue) to what's known, keeping known songs in place,
    /// or starts over when the saved list is outdated.
    func merged(with seen: [Track], at date: Date, name: String, calendar: Calendar = .current) -> MixTracks {
        let outdated = tracks.isEmpty || isOutdated(at: date, name: name, calendar: calendar)
        let base = outdated ? [] : tracks
        var ids = Set(base.map(\.id))
        let added = seen.filter { ids.insert($0.id).inserted }
        return MixTracks(tracks: Array((base + added).prefix(Self.maxCount)), startedAt: outdated ? date : startedAt,
                         lastCapturedAt: date)
    }

    /// Gregorian weekday (Sunday = 1) a weekly playlist refreshes on.
    static func refreshWeekday(name: String) -> Int? {
        let n = name.lowercased()
        if n.contains("discover weekly") { return 2 }
        if n.contains("release radar") { return 6 }
        return nil
    }

    /// Midnight of the latest `weekday` at or before `date`.
    static func start(of weekday: Int, atOrBefore date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: today) - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: today) ?? today
    }
}
