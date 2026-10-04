import Foundation

/// A list or song added to the menu-bar popover (right-click → Add to Menu Bar); a click there plays it.
/// Name and cover are copied when added, so the popover shows them without loading the library.
public struct QuickPlayItem: Codable, Hashable, Sendable, Identifiable {
    public let uri: String
    public var name: String
    /// The artists, for a song.
    public var subtitle: String?
    public var images: [SpotifyImage]
    public var id: String { uri }

    public init(uri: String, name: String, subtitle: String? = nil, images: [SpotifyImage] = []) {
        self.uri = uri; self.name = name; self.subtitle = subtitle; self.images = images
    }

    public var isSong: Bool { uri.hasPrefix("spotify:track:") }

    /// A song plays alone (Spotify's autoplay carries on after it); anything else is a context.
    public var playRequest: PlayRequest { isSong ? .tracks([uri]) : .context(uri) }
}
