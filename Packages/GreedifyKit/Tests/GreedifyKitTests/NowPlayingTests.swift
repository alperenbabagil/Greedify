import Foundation
import MediaPlayer
import Testing
@testable import GreedifyKit

struct NowPlayingInfoTests {
    func state(playing: Bool, item: Track? = Fixture.track) -> PlaybackState {
        PlaybackState(device: nil, isPlaying: playing, progressMs: 0, item: item)
    }

    @Test func nothingLoadedMeansNoInfo() {
        #expect(NowPlayingInfo(state: nil, positionMs: 0) == nil)
        #expect(NowPlayingInfo(state: state(playing: true, item: nil), positionMs: 0) == nil)
    }

    @Test func describesTheTrack() throws {
        let info = try #require(NowPlayingInfo(state: state(playing: true), positionMs: 61_500))
        #expect(info.trackID == "t1")
        #expect(info.title == "Paper Satellites")
        #expect(info.artist == "The Quiet Harbor")
        #expect(info.album == "Low Orbit")
        #expect(info.durationSec == 245)
        #expect(info.elapsedSec == 61.5)
        #expect(info.artworkURL?.absoluteString == "https://i.scdn.co/300")   // smallest that covers 300 px
        #expect(info.playbackState == .playing)
    }

    @Test func propertiesForTheInfoCenter() throws {
        let playing = try #require(NowPlayingInfo(state: state(playing: true), positionMs: 10_000)).properties
        #expect(playing[MPMediaItemPropertyTitle] as? String == "Paper Satellites")
        #expect(playing[MPMediaItemPropertyArtist] as? String == "The Quiet Harbor")
        #expect(playing[MPMediaItemPropertyAlbumTitle] as? String == "Low Orbit")
        #expect(playing[MPMediaItemPropertyPlaybackDuration] as? Double == 245)
        #expect(playing[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 10)
        #expect(playing[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(playing[MPNowPlayingInfoPropertyMediaType] as? UInt == MPNowPlayingInfoMediaType.audio.rawValue)

        let paused = try #require(NowPlayingInfo(state: state(playing: false), positionMs: 10_000))
        #expect(paused.properties[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)   // macOS stops the clock
        #expect(paused.playbackState == .paused)
    }
}

struct NowPlayingEpisodeTests {
    @Test func anEpisodeIsMarkedAndShowsItsShow() throws {
        let state = PlaybackState(device: nil, isPlaying: true, progressMs: 0, item: PodcastFixture.episode())
        let info = try #require(NowPlayingInfo(state: state, positionMs: 1000))
        #expect(info.isEpisode && info.artist == "The Show" && info.album == "The Show")
        #expect(NowPlayingInfo(state: PlaybackState(device: nil, isPlaying: true, progressMs: 0, item: Fixture.track), positionMs: 0)?.isEpisode == false)
    }
}
