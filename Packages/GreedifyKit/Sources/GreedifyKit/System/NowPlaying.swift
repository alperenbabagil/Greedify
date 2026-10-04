import Foundation
import MediaPlayer

/// What macOS's Now Playing (Control Center, the menu-bar widget) shows for the current track.
public struct NowPlayingInfo: Equatable, Sendable {
    public let trackID: String
    public let title: String
    public let artist: String
    public let album: String
    public let durationSec: Double
    public let elapsedSec: Double
    public let isPlaying: Bool
    public let artworkURL: URL?
    public let isEpisode: Bool

    /// Artwork side, in pixels; the widget draws it small.
    public static let artworkPixels = 300

    /// `nil` when nothing (or an ad) is loaded.
    public init?(state: PlaybackState?, positionMs: Int) {
        guard let state, let track = state.item else { return nil }
        trackID = track.id
        title = track.name
        artist = track.artistLine
        album = track.album?.name ?? ""
        durationSec = Double(track.durationMs) / 1000
        elapsedSec = Double(positionMs) / 1000
        isPlaying = state.isPlaying
        artworkURL = track.album?.images.best(minSide: Self.artworkPixels)?.url
        isEpisode = track.isEpisode
    }

    public var playbackState: MPNowPlayingPlaybackState { isPlaying ? .playing : .paused }

    /// `nowPlayingInfo` without artwork, which is loaded separately. macOS advances the elapsed time by the rate.
    public var properties: [String: Any] {
        [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: durationSec,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSec,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }
}
