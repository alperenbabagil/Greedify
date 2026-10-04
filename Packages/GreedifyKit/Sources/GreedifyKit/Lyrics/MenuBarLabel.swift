import Foundation

/// What the menu-bar item shows next to the icon (spec §4.8).
public enum MenuBarLabel: Equatable, Sendable {
    case iconOnly
    case text(String)

    public static let gapSymbol = "♪"
    public static let maxCharacters = 48
    /// How long a new song's "Artist – Song" stays in the menu bar.
    public static let announcementSeconds: Double = 5

    /// `announcement` (a new song's "Artist – Song") takes over while playing, even with lyrics off in the menu bar.
    public static func make(enabled: Bool, isPlaying: Bool, trackName: String?, lyrics: Lyrics, positionMs: Int,
                            announcement: String? = nil) -> MenuBarLabel {
        if isPlaying, let announcement { return .text(truncate(announcement)) }
        guard enabled, isPlaying, let trackName else { return .iconOnly }
        switch lyrics {
        case .synced(let lines):
            guard let i = LRCParser.currentIndex(in: lines, at: positionMs), !lines[i].isGap else { return .text(gapSymbol) }
            return .text(truncate(lines[i].text))
        case .plain:
            return .text(truncate(trackName))
        case .none:
            return .iconOnly
        }
    }

    public static func announcement(for track: Track) -> String {
        "\(track.artistLine) – \(track.name)"
    }

    /// Character cap as a backstop; the view also clips to ~280 pt with a tail ellipsis.
    static func truncate(_ s: String) -> String {
        s.count <= maxCharacters ? s : String(s.prefix(maxCharacters - 1)) + "…"
    }
}
