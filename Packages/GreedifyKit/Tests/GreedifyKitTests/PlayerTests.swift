import Foundation
import Testing
@testable import GreedifyKit

struct PlaybackClockTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test func advancesWhilePlayingAndClampsToDuration() {
        let c = PlaybackClock(progressMs: 1000, durationMs: 5000, isPlaying: true, at: t0)
        #expect(c.positionMs(at: t0.addingTimeInterval(2)) == 3000)
        #expect(c.positionMs(at: t0.addingTimeInterval(60)) == 5000)
    }

    @Test func frozenWhilePaused() {
        var c = PlaybackClock(progressMs: 1000, durationMs: 5000, isPlaying: true, at: t0)
        c.setPlaying(false, at: t0.addingTimeInterval(1))
        #expect(c.positionMs(at: t0.addingTimeInterval(10)) == 2000)
    }

    @Test func seekClamps() {
        var c = PlaybackClock(progressMs: 0, durationMs: 5000, isPlaying: false, at: t0)
        c.seek(toMs: 9000, at: t0)
        #expect(c.positionMs(at: t0) == 5000)
        c.seek(toMs: -5, at: t0)
        #expect(c.positionMs(at: t0) == 0)
    }

    @Test func pollIntervals() {
        func next(visible: Bool, backingOff: Bool = false, local: Bool = false, playing: Bool = true) -> TimeInterval {
            PollInterval.next(uiVisible: visible, backingOff: backingOff, localActive: local, isPlaying: playing)
        }
        #expect(next(visible: true) == 3)                       // another device playing: watch it
        #expect(next(visible: false) == 15)
        #expect(next(visible: true, playing: false) == 10)      // nothing playing: little to watch
        #expect(next(visible: false, playing: false) == 60)
        #expect(next(visible: true, local: true) == 300)        // the Mac speaker reports by itself
        #expect(next(visible: true, backingOff: true) == 60)
    }
}

@MainActor
struct PlayerStoreTests {
    let mac = Device(id: "mac", name: "Studio Mac", type: "Computer", isActive: false, volumePercent: 50)

    func playing(_ playing: Bool, context: String? = "spotify:playlist:p") -> PlaybackState {
        PlaybackState(device: mac, isPlaying: playing, progressMs: 1000, item: Fixture.track,
                      context: context.map { PlaybackContext(uri: $0, type: "playlist") })
    }

    @Test func refreshAppliesStateAndRemembersContext() async {
        let api = FakeSpotifyAPI()
        await api.set(state: playing(true))
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await store.refresh()
        #expect(store.track?.id == "t1")
        #expect(store.isPlaying)
        #expect(store.lastContextURI == "spotify:playlist:p")
    }

    @Test func pauseWhenPlaying() async {
        let api = FakeSpotifyAPI()
        await api.set(state: playing(true))
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await store.refresh()
        await store.togglePlayPause()
        #expect(await api.calls.contains("pause"))
    }

    @Test func noActiveDeviceResumesOnMacWhereItLeftOff() async {
        let api = FakeSpotifyAPI()
        await api.set(state: playing(false))
        await api.set(devices: [mac])
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await store.refresh()                       // remembers spotify:playlist:p
        await api.fail("play(resume,nil)", with: .noActiveDevice)
        await store.togglePlayPause()
        let calls = await api.calls
        #expect(calls.contains("transfer(mac,false)"))
        #expect(calls.contains("play(resume,mac)"))
        #expect(!calls.contains("play(spotify:playlist:p,mac)"))
    }

    @Test func resumeFailureOnMacFallsBackToLastContext() async {
        let api = FakeSpotifyAPI()
        await api.set(state: playing(false))
        await api.set(devices: [mac])
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await store.refresh()
        await api.fail("play(resume,nil)", with: .noActiveDevice)
        await api.fail("play(resume,mac)", with: .notFound)
        await store.togglePlayPause()
        #expect(await api.calls.contains("play(spotify:playlist:p,mac)"))
        #expect(store.lastError == nil)
    }

    @Test func nonPlayCommandTransfersToMacThenRetries() async {
        let api = FakeSpotifyAPI()
        await api.set(devices: [mac])
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await api.fail("shuffle(true)", with: .noActiveDevice)
        await store.setShuffle(true)
        let calls = await api.calls
        #expect(calls.filter { $0 == "shuffle(true)" }.count == 2)
        #expect(calls.contains("transfer(mac,false)"))
        #expect(store.lastError == nil)
    }

    @Test func playRightAfterTransferIsRetriedWhileTheMacWakes() async {
        let api = FakeSpotifyAPI()
        await api.set(devices: [mac])
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        store.deviceWakeDelay = .zero
        await api.fail("play(spotify:user:me:collection,nil)", with: .noActiveDevice)
        // Spotify rejects a command sent before the new device has taken over.
        await api.fail("play(spotify:user:me:collection,mac)", with: .forbidden("Player command failed: Restriction violated"))
        await store.play(.context("spotify:user:me:collection"))
        #expect(await api.calls.filter { $0 == "play(spotify:user:me:collection,mac)" }.count == 2)
        #expect(store.lastError == nil)
    }

    @Test func visibilityCountsSurfaces() {
        let store = PlayerStore(api: FakeSpotifyAPI(), localDeviceName: "Mac")
        store.surfaceAppeared("popover")
        store.surfaceAppeared("window")
        store.surfaceDisappeared("popover")
        #expect(store.uiVisible)          // window still open
        store.surfaceDisappeared("window")
        #expect(!store.uiVisible)
    }

    // MARK: Local speaker events

    let local = Device(id: "mac", name: "Mac", type: "Computer", isActive: true, volumePercent: 40)

    func localStore(_ api: FakeSpotifyAPI, clock: TestNow = TestNow(Date(timeIntervalSince1970: 0))) -> PlayerStore {
        let store = PlayerStore(api: api, localDeviceName: "Mac", now: { clock.date })
        store.metadataDelay = .zero
        return store
    }

    /// A track as librespot reports it: no artist or album ids.
    static let bare = Track(id: "t1", name: "Paper Satellites", uri: "spotify:track:t1", durationMs: 245_000,
                            artists: [ArtistRef(id: nil, name: "The Quiet Harbor", uri: "")],
                            album: AlbumRef(id: nil, name: "Low Orbit", uri: "", images: []))

    @Test func localEventsDriveThePlayerWithoutTheAPI() async {
        let api = FakeSpotifyAPI()
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let store = localStore(api, clock: clock)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        #expect(store.track?.name == "Paper Satellites")
        #expect(store.activeDevice?.name == "Mac")
        #expect(store.isLocalActive)
        await store.apply(.playing(trackID: "t1", positionMs: 5000))
        #expect(store.isPlaying)
        clock.date = clock.date.addingTimeInterval(2)
        #expect(store.positionMs(at: clock.date) == 7000)
        await store.apply(.seeked(trackID: "t1", positionMs: 60_000))
        #expect(store.positionMs(at: clock.date) == 60_000)
        await store.apply(.paused(trackID: "t1", positionMs: 61_000))
        #expect(!store.isPlaying)
        await store.apply(.shuffle(true))
        await store.apply(.repeatMode(.track))
        await store.apply(.volume(percent: 30))
        #expect(store.state?.shuffleState == true && store.state?.repeatState == .track)
        #expect(store.activeDevice?.volumePercent == 30)
        #expect(await api.calls.filter { $0 == "state" }.count == 1)   // one metadata fetch for the new track
    }

    @Test func pollAddsMetadataButLocalPositionWins() async {
        let api = FakeSpotifyAPI()
        await api.set(state: PlaybackState(device: local, isPlaying: false, progressMs: 99_000, item: Fixture.track,
                                           context: PlaybackContext(uri: "spotify:playlist:p", type: "playlist")))
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let store = localStore(api, clock: clock)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        await store.apply(.playing(trackID: "t1", positionMs: 5000))
        await store.refresh()
        #expect(store.track?.album?.id == "al1")                       // full metadata from the API
        #expect(store.lastContextURI == "spotify:playlist:p")
        #expect(store.isPlaying)                                        // not the API's stale "paused"
        #expect(store.positionMs(at: clock.date) == 5000)               // nor its position
    }

    @Test func stalePollDoesNotUndoATrackChange() async {
        let api = FakeSpotifyAPI()
        await api.set(state: PlaybackState(device: local, isPlaying: true, progressMs: 0, item: Fixture.track("old")))
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        await store.refresh()
        #expect(store.track?.id == "t1")
        await api.set(state: nil)                                       // 204 lagging behind the speaker
        await store.refresh()
        #expect(store.track?.id == "t1")
    }

    @Test func anotherDeviceTakingOverEndsLocalMode() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Fixture.track("phone")))
        await store.apply(.stopped)
        #expect(!store.isLocalActive)
        #expect(store.track?.id == "phone")                             // stopped → asked the API where playback went
    }

    @Test func openingTheUIPollsOnceAndNotInLocalMode() async {
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        func polls() async -> Int { await api.calls.filter { $0 == "state" }.count }
        store.startPolling()
        for _ in 0..<50 where await polls() < 1 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(await polls() == 1)                                           // first poll, then a long nap
        store.surfaceAppeared("popover")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await polls() == 2)                                           // woken once, not twice
        store.surfaceDisappeared("popover")
        store.metadataDelay = .seconds(60)
        await store.apply(.trackChanged(Self.bare))
        store.surfaceAppeared("popover")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await polls() == 2)                                           // the speaker reports by itself
        store.stopPolling()
    }

    @Test func scriptReadsDoNotPollInLocalMode() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        let before = await api.calls.filter { $0 == "state" }.count
        store.scriptDidRead()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await api.calls.filter { $0 == "state" }.count == before)
    }

    @Test func commandsSkipTheFollowUpPollInLocalMode() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        let before = await api.calls.filter { $0 == "state" }.count
        await store.next()
        #expect(await api.calls.filter { $0 == "state" }.count == before)   // librespot will report the result
    }

    /// librespot 0.8 loads a Web API play in list order even with shuffle on; shuffle is re-sent once it loads.
    @Test func playWithShuffleOnReshufflesOnceTheMacLoadsTheTrack() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.apply(.shuffle(true))
        await store.metadataTask?.value
        await store.play(.context("spotify:playlist:p", startingAt: "spotify:track:t2"))
        #expect(await !api.calls.contains("shuffle(true)"))               // not before the new list has loaded
        await store.apply(.trackChanged(Fixture.track("t2")))
        #expect(await api.calls.filter { $0 == "shuffle(true)" }.count == 1)
        await store.apply(.trackChanged(Fixture.track("t3")))             // later track changes are just playback
        #expect(await api.calls.filter { $0 == "shuffle(true)" }.count == 1)
    }

    @Test func playWithShuffleOffDoesNotShuffle() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        await store.play(.context("spotify:playlist:p", startingAt: "spotify:track:t2"))
        await store.apply(.trackChanged(Fixture.track("t2")))
        #expect(await !api.calls.contains { $0.hasPrefix("shuffle") })
    }

    @Test func shuffledPlayTurnsShuffleOnAfterTheLoad() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.metadataTask?.value
        await store.play(.context("spotify:album:a"), shuffled: true)
        #expect(await !api.calls.contains("shuffle(true)"))
        await store.apply(.playing(trackID: "t1", positionMs: 0))       // same first track: only `playing` arrives
        #expect(await api.calls.filter { $0 == "shuffle(true)" }.count == 1)
    }

    @Test func shuffleOnARemoteDeviceIsSentAfterAShortWait() async {
        let api = FakeSpotifyAPI()
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Fixture.track, shuffleState: true))
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        store.remoteReshuffleDelay = .zero
        await store.refresh()
        await store.play(.context("spotify:playlist:p"))
        let calls = await api.calls
        #expect(calls.firstIndex(of: "shuffle(true)") ?? -1 > calls.firstIndex(of: "play(spotify:playlist:p,nil)") ?? .max)
    }

    @Test func pollDoesNotUndoTheSpeakersShuffle() async {
        let api = FakeSpotifyAPI()
        await api.set(state: PlaybackState(device: local, isPlaying: true, progressMs: 0, item: Fixture.track("t1"),
                                           shuffleState: false, repeatState: .off))
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.apply(.shuffle(true))
        await store.apply(.repeatMode(.context))
        await store.metadataTask?.value
        await store.refresh()
        #expect(store.state?.shuffleState == true)                      // the API lags the speaker
        #expect(store.state?.repeatState == .context)
    }

    static func episode(_ id: String, show: Bool = true) -> Track {
        let bare = Track(id: id, name: id, uri: "spotify:episode:\(id)", durationMs: 600_000, artists: [], album: nil)
        return bare.inShow(ShowRef(id: show ? "s1" : nil, name: "The Show", uri: "spotify:show:s1", images: []))
    }

    @Test func anEpisodeQueuesTheNextNewerOnceAndNotForTheNewest() async {
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        store.episodesOfShow = { _, _ in [Self.episode("e3"), Self.episode("e2"), Self.episode("e1")] }   // newest first
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Self.episode("e2")))
        await store.refresh()
        await store.refresh()                                            // review focus 5: polls don't queue it twice
        #expect(await api.calls.filter { $0 == "queue(spotify:episode:e3)" }.count == 1)
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Self.episode("e3")))
        await store.refresh()
        #expect(await !api.calls.contains { $0.hasPrefix("queue(spotify:episode:") && $0 != "queue(spotify:episode:e3)" })
    }

    /// Review focus 1: from librespot the show's id isn't known yet; the metadata poll brings it.
    @Test func anEpisodeWithoutItsShowIDWaitsForThePoll() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        store.episodesOfShow = { _, _ in [Self.episode("e2"), Self.episode("e1")] }
        await api.set(state: PlaybackState(device: local, isPlaying: true, progressMs: 0, item: Self.episode("e1")))
        store.metadataDelay = .seconds(60)                               // hold the poll back
        await store.apply(.trackChanged(Self.episode("e1", show: false)))
        #expect(await !api.calls.contains { $0.hasPrefix("queue(") })
        await store.refresh()                                            // what the delayed poll does
        #expect(await api.calls.contains("queue(spotify:episode:e2)"))
    }

    @Test func skipsMoveWithinTheEpisode() async {
        let api = FakeSpotifyAPI()
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let store = PlayerStore(api: api, localDeviceName: "Mac", now: { clock.date })
        await api.set(state: PlaybackState(device: mac, isPlaying: false, progressMs: 10_000, item: Self.episode("e1")))
        await store.refresh()
        await store.skipBack()
        #expect(await api.calls.contains("seek(0)"))                    // 10 s − 15 s clamps to 0
        await store.skipForward()
        #expect(await api.calls.contains("seek(40000)"))              // the follow-up poll put the clock back at the fake's 10 s
        await api.set(state: PlaybackState(device: mac, isPlaying: false, progressMs: 590_000, item: Self.episode("e1")))
        await store.refresh()
        await store.skipForward()
        #expect(await api.calls.contains("seek(599000)"))               // clamped to duration − 1 s
    }

    @Test func playingAnEpisodeNeverReshuffles() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.bare))
        await store.apply(.shuffle(true))
        await store.metadataTask?.value
        await store.play(.episode("spotify:episode:e1", at: 120_000))
        await store.apply(.trackChanged(Self.episode("e1", show: false)))
        #expect(await !api.calls.contains("shuffle(true)"))
        #expect(await api.lastPlay == .episode("spotify:episode:e1", at: 120_000))
    }

    @Test func aRestoredEpisodeResumesWhereItStopped() async throws {
        let d = UserDefaults(suiteName: "ep-\(UUID().uuidString)")!
        let saved = LastPlayed(track: Self.episode("e1"), context: nil, positionMs: 42_000)
        d.set(try JSONEncoder().encode(saved), forKey: PlayerStore.lastPlayedKey)
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac", defaults: d)
        #expect(store.track?.isEpisode == true)
        await store.togglePlayPause()
        #expect(await api.lastPlay == PlayRequest(contextURI: nil, uris: ["spotify:episode:e1"], offsetURI: nil, positionMs: 42_000))
    }

    /// Final review 1: overlapping polls must not both queue the follower (Spotify can't unqueue).
    @Test func overlappingPollsQueueTheFollowerOnce() async {
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        store.episodesOfShow = { _, _ in
            try? await Task.sleep(for: .milliseconds(50))                 // a slow first fetch
            return [Self.episode("e3"), Self.episode("e2")]
        }
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Self.episode("e2")))
        async let a: Void = store.refresh()
        async let b: Void = store.refresh()
        _ = await (a, b)
        #expect(await api.calls.filter { $0 == "queue(spotify:episode:e3)" }.count == 1)
    }

    /// Final review 2: last run's episode shown at launch must not queue anything (no device, nothing playing).
    @Test func aRestoredEpisodeQueuesNothingBeforePlay() async throws {
        let d = UserDefaults(suiteName: "ep-\(UUID().uuidString)")!
        d.set(try JSONEncoder().encode(LastPlayed(track: Self.episode("e2"), context: nil, positionMs: 1000)), forKey: PlayerStore.lastPlayedKey)
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac", defaults: d)
        store.episodesOfShow = { _, _ in [Self.episode("e3"), Self.episode("e2")] }
        await store.refresh()                                              // 204: nothing playing
        #expect(await !api.calls.contains { $0.hasPrefix("queue(") || $0.hasPrefix("transfer(") })
    }

    /// Final review 3: a follower already in Spotify's queue (queued before a relaunch) isn't queued again.
    @Test func aFollowerAlreadyQueuedIsLeftAlone() async {
        let api = FakeSpotifyAPI()
        await api.set(upNext: [Self.episode("e3")])
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        store.episodesOfShow = { _, _ in [Self.episode("e3"), Self.episode("e2")] }
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Self.episode("e2")))
        await store.refresh()
        #expect(await !api.calls.contains("queue(spotify:episode:e3)"))
    }

    /// Final review 3: started from a show page, the follower goes in the play request; nothing is queued.
    @Test func aFollowerInThePlayRequestIsNotQueued() async {
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        store.episodesOfShow = { _, _ in [Self.episode("e3"), Self.episode("e2")] }
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Self.episode("e2")))
        await store.play(.episode("spotify:episode:e2", at: 5000, then: "spotify:episode:e3"))
        #expect(await api.lastPlay?.uris == ["spotify:episode:e2", "spotify:episode:e3"])
        #expect(await !api.calls.contains { $0.hasPrefix("queue(") })
    }

    /// Final review 4: where an episode stopped this session beats its (cached, older) resume point.
    @Test func whereAnEpisodeStoppedIsRemembered() async {
        let api = FakeSpotifyAPI()
        let store = localStore(api)
        await store.apply(.trackChanged(Self.episode("e1", show: false)))
        await store.apply(.playing(trackID: "e1", positionMs: 300_000))
        await store.apply(.trackChanged(Self.bare))                       // music took over
        #expect(store.startPosition(for: Self.episode("e1")) == 300_000)
    }

    @Test func forwardWithAnUnknownLengthStaysPut() async {
        let api = FakeSpotifyAPI()
        let bare = Track(id: "e1", name: "e1", uri: "spotify:episode:e1", durationMs: 0, artists: [], album: nil)
        await api.set(state: PlaybackState(device: mac, isPlaying: false, progressMs: 60_000, item: bare.inShow(ShowRef(id: "s1", name: "S", uri: "", images: []))))
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        await store.refresh()
        await store.skipForward()
        #expect(await !api.calls.contains { $0.hasPrefix("seek(") })
    }

    @Test func scriptReadKeepsPollingFastForAWhile() async {
        let clock = TestNow(Date(timeIntervalSince1970: 0))
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac", now: { clock.date })
        #expect(!store.uiVisible)
        store.scriptDidRead()
        #expect(store.uiVisible)
        clock.date = clock.date.addingTimeInterval(PlayerStore.scriptLease - 1)
        #expect(store.uiVisible)
        clock.date = clock.date.addingTimeInterval(2)
        #expect(!store.uiVisible)
    }

    @Test func scriptPlayerState() async {
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        #expect(store.scriptPlayerState == .stopped)       // nothing loaded
        await api.set(state: playing(true))
        await store.refresh()
        #expect(store.scriptPlayerState == .playing)
        await api.set(state: playing(false))
        await store.refresh()
        #expect(store.scriptPlayerState == .paused)
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: nil, context: nil))
        await store.refresh()
        #expect(store.scriptPlayerState == .stopped)       // an ad or episode: no track to report
    }

    @Test func localDeviceOnlineNeedsAFetchedList() async {
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        #expect(store.isLocalDeviceOnline == nil)      // unknown until fetched
        await api.set(devices: [])
        await store.refreshDevices()
        #expect(store.isLocalDeviceOnline == false)    // empty list = speaker missing
        await api.set(devices: [mac])
        await store.refreshDevices()
        #expect(store.isLocalDeviceOnline == true)
    }

    /// A poll cancelled with its task (polling restarted or stopped) isn't "Can't reach Spotify".
    @Test func cancelledPollIsNotAnError() async {
        let api = FakeSpotifyAPI()
        await api.fail("state", throwing: CancellationError())
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await store.refresh()
        #expect(store.lastError == nil)
    }

    @Test func noActiveDeviceAndMacMissingRecordsError() async {
        let api = FakeSpotifyAPI()
        await api.set(devices: [])
        await api.enqueue(.noActiveDevice)
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await store.next()
        #expect(store.lastError == .noActiveDevice)
    }

    @Test func macMissingRestartsSpeakerAndRetriesOnceItRegisters() async {
        let api = FakeSpotifyAPI()
        await api.set(devices: [])
        await api.fail("shuffle(true)", with: .noActiveDevice)
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        store.deviceWaitInterval = .zero
        var restarts = 0
        var connectingDuringRestart = false
        // librespot's connection went stale: the device is back only after a restart.
        store.restartSpeaker = {
            restarts += 1
            connectingDuringRestart = store.isConnectingSpeaker
            await api.set(devices: [self.mac])
        }
        await store.setShuffle(true)
        let calls = await api.calls
        #expect(restarts == 1)
        #expect(connectingDuringRestart)
        #expect(!store.isConnectingSpeaker)
        #expect(calls.contains("transfer(mac,false)"))
        #expect(calls.filter { $0 == "shuffle(true)" }.count == 2)
        #expect(store.lastError == nil)
    }

    @Test func macStillMissingAfterRestartRecordsError() async {
        let api = FakeSpotifyAPI()
        await api.set(devices: [])
        await api.enqueue(.noActiveDevice)
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        store.deviceWaitInterval = .zero
        var restarts = 0
        store.restartSpeaker = { restarts += 1 }
        await store.next()
        #expect(restarts == 1)
        #expect(await api.calls.filter { $0 == "devices" }.count == 1 + PlayerStore.deviceWaitAttempts)
        #expect(store.lastError == .noActiveDevice)
        #expect(!store.isConnectingSpeaker)
    }

    @Test func rateLimitFlagsStoreAndClearsOnSuccess() async {
        let api = FakeSpotifyAPI()
        await api.enqueue(.rateLimited(retryAfter: 30, quotaExceeded: true))
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        await store.refresh()
        #expect(store.isRateLimited)
        await store.refresh()
        #expect(!store.isRateLimited)
        #expect(store.lastError == nil)
    }

    @Test func refreshQueueLoadsUpNext() async {
        let api = FakeSpotifyAPI()
        await api.set(upNext: [Fixture.track("n1"), Fixture.track("n2")])
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        await store.refreshQueue()
        #expect(store.upNext.map(\.id) == ["n1", "n2"])
    }

    @Test func radioPlaysSingleTrack() async {
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Mac")
        await store.startRadio(trackURI: "spotify:track:t1")
        #expect(await api.calls.contains("play(spotify:track:t1,nil)"))
    }

    @Test func seekMovesLocalClockImmediately() async {
        let api = FakeSpotifyAPI()
        let fixed = Date(timeIntervalSince1970: 100)
        let store = PlayerStore(api: api, localDeviceName: "Mac", now: { fixed })
        await api.set(state: PlaybackState(device: mac, isPlaying: false, progressMs: 0, item: Fixture.track))
        await store.refresh()
        await api.set(state: PlaybackState(device: mac, isPlaying: false, progressMs: 60_000, item: Fixture.track))
        await store.seek(toMs: 60_000)
        #expect(store.positionMs(at: fixed) == 60_000)
        #expect(await api.calls.contains("seek(60000)"))
    }

    // MARK: Last played, across launches

    func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "greedify-test-\(UUID().uuidString)")! }

    /// A first run that played t1 in spotify:playlist:p and paused at 42 s.
    func previousRun(_ defaults: UserDefaults) async {
        let api = FakeSpotifyAPI()
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 42_000, item: Fixture.track,
                                           context: PlaybackContext(uri: "spotify:playlist:p", type: "playlist")))
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac", defaults: defaults)
        await store.refresh()
        await api.set(state: PlaybackState(device: mac, isPlaying: false, progressMs: 42_000, item: Fixture.track,
                                           context: PlaybackContext(uri: "spotify:playlist:p", type: "playlist")))
        await store.refresh()
    }

    @Test func freshLaunchShowsLastPlayedTrackPaused() async {
        let defaults = freshDefaults()
        await previousRun(defaults)
        let api = FakeSpotifyAPI()                  // nothing playing anywhere (204)
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac", defaults: defaults)
        #expect(store.track?.id == "t1")
        #expect(!store.isPlaying)
        #expect(store.positionMs(at: Date()) == 42_000)
        #expect(store.lastContextURI == "spotify:playlist:p")
        await store.refresh()
        #expect(store.track?.id == "t1")            // a 204 doesn't clear it
        #expect(store.scriptPlayerState == .paused)
    }

    @Test func playingTheRestoredTrackStartsItWhereItStopped() async {
        let defaults = freshDefaults()
        await previousRun(defaults)
        let api = FakeSpotifyAPI()
        await api.set(devices: [mac])
        await api.fail("play(spotify:playlist:p,nil)", with: .noActiveDevice)
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac", defaults: defaults)
        await store.togglePlayPause()
        let calls = await api.calls
        #expect(calls.contains("transfer(mac,false)"))
        #expect(calls.contains("play(spotify:playlist:p,mac)"))
        let request = await api.lastPlay
        #expect(request?.offsetURI == "spotify:track:t1")
        #expect(request?.positionMs == 42_000)
    }

    @Test func restoredTrackFallsBackToTheTrackAloneIfTheContextFails() async {
        let defaults = freshDefaults()
        await previousRun(defaults)
        let api = FakeSpotifyAPI()
        await api.fail("play(spotify:playlist:p,nil)", with: .notFound)
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac", defaults: defaults)
        await store.togglePlayPause()
        #expect(await api.calls.contains("play(spotify:track:t1,nil)"))
        #expect(await api.lastPlay?.positionMs == 42_000)
    }

    @Test func seekingTheRestoredTrackOnlyMovesTheStartPoint() async {
        let defaults = freshDefaults()
        await previousRun(defaults)
        let api = FakeSpotifyAPI()
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac", defaults: defaults)
        await store.seek(toMs: 10_000)
        #expect(await api.calls.isEmpty)
        #expect(store.positionMs(at: Date()) == 10_000)
        await store.togglePlayPause()
        #expect(await api.lastPlay?.positionMs == 10_000)
    }

    @Test func livePlaybackReplacesTheRestoredTrack() async {
        let defaults = freshDefaults()
        await previousRun(defaults)
        let api = FakeSpotifyAPI()
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 0, item: Fixture.track("t2")))
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac", defaults: defaults)
        await store.refresh()
        #expect(store.track?.id == "t2")
        await api.set(state: nil)
        await store.refresh()
        #expect(store.track?.id == "t2")            // stopped during this run: still shows the last track
        #expect(!store.isPlaying)
    }

    @Test func stoppingKeepsTheLastTrackReadyToPlay() async {
        let api = FakeSpotifyAPI()
        await api.set(devices: [mac])
        await api.set(state: PlaybackState(device: mac, isPlaying: true, progressMs: 30_000, item: Fixture.track,
                                           context: PlaybackContext(uri: "spotify:playlist:p", type: "playlist")))
        let store = PlayerStore(api: api, localDeviceName: "Studio Mac")
        await store.refresh()
        await api.set(state: nil)                   // playback ended everywhere (204)
        await store.refresh()
        #expect(store.track?.id == "t1")
        #expect(!store.isPlaying)
        #expect(store.state?.device == nil)
        #expect(store.scriptPlayerState == .paused)
        await store.togglePlayPause()               // plays it again in its context
        #expect(await api.lastPlay?.offsetURI == "spotify:track:t1")
    }
}
