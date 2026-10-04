import AppKit
import GreedifyKit
import MediaPlayer

/// Publishes the current track to macOS's Now Playing (Control Center and its menu-bar widget) and takes its
/// play/pause, skip and scrub commands. With no Accessibility grant these also carry the media keys.
@MainActor
final class NowPlayingPublisher {
    private let player: () -> PlayerStore
    private let images: ImageCache
    private var published: NowPlayingInfo?
    private var artwork: (url: URL, item: MPMediaItemArtwork)?
    private var artworkTask: Task<Void, Never>?

    init(player: @escaping () -> PlayerStore, images: ImageCache) {
        self.player = player; self.images = images
    }

    func start() {
        let center = MPRemoteCommandCenter.shared()
        // Handlers may run off the main thread: @Sendable, then hop to the main actor (see CLAUDE.md).
        let run: @Sendable (@escaping @MainActor (PlayerStore) async -> Void) -> MPRemoteCommandHandlerStatus = { [weak self] command in
            Task { @MainActor in
                guard let self else { return }
                await command(self.player())
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { @Sendable _ in run { await $0.togglePlayPause() } }
        center.playCommand.addTarget { @Sendable _ in run { if !$0.isPlaying { await $0.togglePlayPause() } } }
        center.pauseCommand.addTarget { @Sendable _ in run { if $0.isPlaying { await $0.togglePlayPause() } } }
        center.nextTrackCommand.addTarget { @Sendable _ in run { await $0.next() } }
        center.previousTrackCommand.addTarget { @Sendable _ in run { await $0.previous() } }
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let ms = Int(event.positionTime * 1000)
            return run { await $0.seek(toMs: ms) }
        }
        // Podcasts (spec §6.4): back 15 s and forward 30 s, enabled only while an episode plays.
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.addTarget { @Sendable _ in run { await $0.skipBack() } }
        center.skipForwardCommand.addTarget { @Sendable _ in run { await $0.skipForward() } }
        update()
    }

    /// Called whenever the player state or clock changes.
    func update() {
        let player = player()
        let info = NowPlayingInfo(state: player.state, positionMs: player.positionMs(at: Date()))
        guard info != published else { return }
        published = info
        let center = MPRemoteCommandCenter.shared()
        center.skipBackwardCommand.isEnabled = info?.isEpisode ?? false
        center.skipForwardCommand.isEnabled = info?.isEpisode ?? false
        let infoCenter = MPNowPlayingInfoCenter.default()
        guard let info else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }
        var properties = info.properties
        if let artwork, artwork.url == info.artworkURL { properties[MPMediaItemPropertyArtwork] = artwork.item }
        infoCenter.nowPlayingInfo = properties
        infoCenter.playbackState = info.playbackState
        if let url = info.artworkURL, artwork?.url != url { loadArtwork(url) }
    }

    private func loadArtwork(_ url: URL) {
        artworkTask?.cancel()
        artworkTask = Task { [images] in
            guard let image = await images.image(for: url, maxPixelSize: NowPlayingInfo.artworkPixels),
                  !Task.isCancelled else { return }
            let item = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
            artwork = (url, item)
            let center = MPNowPlayingInfoCenter.default()
            guard published?.artworkURL == url, var properties = center.nowPlayingInfo else { return }
            properties[MPMediaItemPropertyArtwork] = item
            center.nowPlayingInfo = properties
        }
    }
}
