import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.alperen.greedify", category: "player")

/// How often `/me/player` is polled. Spotify's development-mode quota is small, so poll only as much as needed.
public enum PollInterval {
    public static let visible: TimeInterval = 3
    public static let hidden: TimeInterval = 15
    /// Nothing playing: only a resume elsewhere (e.g. on the phone) would change anything.
    public static let idleVisible: TimeInterval = 10
    public static let idleHidden: TimeInterval = 60
    /// The Mac speaker is active and reports through librespot events; polling is only a safety net.
    public static let local: TimeInterval = 300
    public static let backoff: TimeInterval = 60

    public static func next(uiVisible: Bool, backingOff: Bool, localActive: Bool, isPlaying: Bool) -> TimeInterval {
        if backingOff { return backoff }
        if localActive { return local }
        if !isPlaying { return uiVisible ? idleVisible : idleHidden }
        return uiVisible ? visible : hidden
    }
}

/// The last track played, saved so a fresh launch can show it (paused where it stopped) before anything plays.
public struct LastPlayed: Codable, Equatable, Sendable {
    public let track: Track
    public let context: PlaybackContext?
    public let positionMs: Int
}

/// `player state` as Spotify's and Music's AppleScript dictionaries spell it.
public enum ScriptPlayerState: Sendable { case stopped, playing, paused }

@MainActor @Observable
public final class PlayerStore {
    public private(set) var state: PlaybackState?
    public private(set) var devices: [Device] = []
    public private(set) var clock = PlaybackClock()
    public private(set) var lastError: SpotifyError?
    public private(set) var isRateLimited = false
    /// Open UI surfaces (popover, main window). Polling is fast while any is open.
    public private(set) var visibleSurfaces: Set<String> = []
    public var uiVisible: Bool { !visibleSurfaces.isEmpty || scriptLeaseEnds.map { now() < $0 } ?? false }
    /// Until when an AppleScript client (e.g. a terminal's now-playing widget) counts as an open surface.
    private var scriptLeaseEnds: Date?
    /// How long one AppleScript read keeps polling fast.
    public static let scriptLease: TimeInterval = 10
    private var devicesFetched = false
    /// Name of the librespot device, used when no device is active.
    public var localDeviceName: String
    /// The Mac speaker is playing (or paused on) the current track: librespot events are the source of truth
    /// and the Web API is only asked for what they lack (artist and album ids, the context).
    public private(set) var isLocalActive = false
    /// Wait before fetching a new track's full metadata; the Web API lags the speaker by a few seconds.
    var metadataDelay: Duration = .seconds(3)
    private(set) var metadataTask: Task<Void, Never>?

    let api: SpotifyAPI
    let now: @Sendable () -> Date
    private var pollTask: Task<Void, Never>?
    private var sleeper: Task<Void, Never>?
    /// Last context played, remembered so media keys can resume it with no active device.
    public private(set) var lastContextURI: String?
    /// Where the last played track is saved; `nil` keeps nothing across launches.
    let defaults: UserDefaults?
    static let lastPlayedKey = "lastPlayed"
    /// The state shows last run's track, not anything Spotify reports: play starts it, seek only moves its start.
    public private(set) var isRestored = false
    private var lastSavedKey: String?

    public init(api: SpotifyAPI, localDeviceName: String, defaults: UserDefaults? = nil,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api; self.localDeviceName = localDeviceName; self.defaults = defaults; self.now = now
        restoreLastPlayed()
    }

    public var track: Track? { state?.item }
    public var isPlaying: Bool { state?.isPlaying ?? false }
    public var activeDevice: Device? { state?.device ?? devices.first(where: \.isActive) }
    public func positionMs(at date: Date) -> Int { clock.positionMs(at: date) }

    // MARK: Polling

    public func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = PollInterval.next(uiVisible: self.uiVisible, backingOff: self.isRateLimited,
                                                 localActive: self.isLocalActive, isPlaying: self.isPlaying)
                let nap = Task<Void, Never> { try? await Task.sleep(for: .seconds(interval)) }
                self.sleeper = nap
                await nap.value
            }
        }
    }

    public func stopPolling() { pollTask?.cancel(); pollTask = nil; sleeper?.cancel() }

    /// Ends the current poll wait early so the next poll uses the new interval.
    func nudge() { sleeper?.cancel() }

    /// A surface opened: poll now (the woken loop does it) unless the Mac speaker keeps the state current.
    private func pollSoon() {
        guard !isLocalActive else { return }
        if pollTask != nil { nudge() } else { Task { await refresh() } }
    }

    public func surfaceAppeared(_ id: String) {
        let wasVisible = uiVisible
        visibleSurfaces.insert(id)
        if !wasVisible { pollSoon() }
    }

    public func surfaceDisappeared(_ id: String) { visibleSurfaces.remove(id) }

    /// An AppleScript client read the player. Keeps polling fast while it keeps asking, so it sees fresh state.
    public func scriptDidRead() {
        let wasVisible = uiVisible
        scriptLeaseEnds = now().addingTimeInterval(Self.scriptLease)
        if !wasVisible { pollSoon() }
    }

    /// `player state` for AppleScript, in Spotify's vocabulary.
    public var scriptPlayerState: ScriptPlayerState {
        guard let state, state.item != nil else { return .stopped }
        return state.isPlaying ? .playing : .paused
    }

    public func refresh() async {
        do {
            let fresh = try await api.playbackState()
            apply(fresh)
            await queueNextEpisode()
            isRateLimited = false
            if case .rateLimited? = lastError { lastError = nil }
        } catch let error as SpotifyError {
            record(error)
        } catch is CancellationError {
            // cancelled with its task: nothing went wrong
        } catch {
            record(.transport("\(error)"))
        }
    }

    func apply(_ fresh: PlaybackState?) {
        defer { rememberLastPlayed() }
        if isRestored {
            guard fresh?.item != nil else { return } // nothing playing yet: keep showing last run's track
            isRestored = false
        }
        if isLocalActive, let local = state, local.item != nil {
            // The API lags the speaker: a 204 or an older track here is stale, not news.
            guard let fresh, let device = fresh.device else { return }
            if device.name == localDeviceName {
                guard fresh.item?.id == local.item?.id else { return }
                // Same track: take its metadata; the speaker's play state, position, shuffle and repeat win.
                state = PlaybackState(device: device, isPlaying: local.isPlaying, progressMs: fresh.progressMs,
                                      item: fresh.item, shuffleState: local.shuffleState ?? fresh.shuffleState,
                                      repeatState: local.repeatState ?? fresh.repeatState, context: fresh.context)
                if let context = fresh.context?.uri { lastContextURI = context }
                return
            }
            isLocalActive = false // another device took over
        }
        if fresh?.item == nil, fresh?.isPlaying != true, track != nil { keepLastPlayed(); return }
        if fresh?.item?.id != track?.id { noteEpisodeProgress() }
        state = fresh
        if let context = fresh?.context?.uri { lastContextURI = context }
        clock.sync(progressMs: fresh?.progressMs ?? 0, durationMs: fresh?.item?.durationMs ?? 0,
                   isPlaying: fresh?.isPlaying ?? false, at: now())
    }

    func record(_ error: SpotifyError) {
        lastError = error
        if case .rateLimited = error { isRateLimited = true }
    }

    public func clearError() { lastError = nil }
    /// nil until the device list has been fetched; then whether the librespot device is in it.
    public var isLocalDeviceOnline: Bool? {
        devicesFetched ? devices.contains { $0.name == localDeviceName } : nil
    }

    public func refreshDevices() async {
        do { devices = try await api.devices(); devicesFetched = true } catch let e as SpotifyError { record(e) } catch {}
    }

    // MARK: Local speaker events

    /// Applies an event from the local librespot (see `LibrespotEvent`).
    public func apply(_ event: LibrespotEvent) async {
        defer { rememberLastPlayed() }
        switch event {
        case .trackChanged(let track):
            if track.id != self.track?.id { noteEpisodeProgress() }
            isRestored = false
            isLocalActive = true
            let old = state
            state = PlaybackState(device: localDevice(), isPlaying: old?.isPlaying ?? false, progressMs: 0, item: track,
                                  shuffleState: old?.shuffleState, repeatState: old?.repeatState, context: old?.context)
            clock.sync(progressMs: 0, durationMs: track.durationMs, isPlaying: isPlaying, at: now())
            fetchMetadata()
            await reshuffleIfPending(trackID: track.id, loaded: true)
            await queueNextEpisode()
        case .playing(let id, let position):
            await applyLocal(playing: true, trackID: id, positionMs: position)
            await reshuffleIfPending(trackID: id, loaded: false)
        case .paused(let id, let position):
            await applyLocal(playing: false, trackID: id, positionMs: position)
            noteEpisodeProgress()
        case .seeked(let id, let position):
            guard state?.item?.id == id else { return }
            clock.seek(toMs: position, at: now())
        case .stopped, .sessionDisconnected:
            guard isLocalActive else { return }
            isLocalActive = false
            nudge()
            await refresh() // where did playback go?
        case .volume(let percent):
            guard let s = state, let d = s.device, d.name == localDeviceName else { return }
            state = s.replacing(device: Device(id: d.id, name: d.name, type: d.type, isActive: d.isActive, volumePercent: percent))
        case .shuffle(let on):
            state = state?.replacing(shuffle: on)
        case .repeatMode(let mode):
            state = state?.replacing(repeatMode: mode)
        case .other:
            break
        }
    }

    private func applyLocal(playing: Bool, trackID: String, positionMs: Int) async {
        isLocalActive = true
        isRestored = false
        if state?.item?.id != trackID {
            await refresh() // Greedify started mid-track: learn the track once
            if state?.item?.id != trackID { fetchMetadata() }
        }
        guard let s = state, s.item?.id == trackID else { return }
        state = s.replacing(isPlaying: playing)
        clock.sync(progressMs: positionMs, durationMs: s.item?.durationMs ?? 0, isPlaying: playing, at: now())
    }

    /// One delayed poll for what librespot doesn't report (ids, context).
    private func fetchMetadata() {
        metadataTask?.cancel()
        let delay = metadataDelay
        metadataTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isLocalActive else { return }
            await self.refresh()
        }
    }

    /// The Mac speaker as a device: from the last poll or device list when known.
    private func localDevice() -> Device {
        if let d = state?.device, d.name == localDeviceName { return d }
        let known = devices.first { $0.name == localDeviceName }
        return Device(id: known?.id, name: localDeviceName, type: "Computer", isActive: true, volumePercent: known?.volumePercent)
    }

    // MARK: Commands

    /// Runs a command, then re-polls. `NO_ACTIVE_DEVICE` moves playback to the Mac (paused) and retries once there.
    func perform(_ command: @escaping @Sendable (String?) async throws -> Void) async {
        do {
            try await command(nil)
        } catch SpotifyError.noActiveDevice {
            do {
                guard let id = try await localDeviceIDRestartingSpeaker() else { record(.noActiveDevice); return }
                try await api.transferPlayback(to: id, play: false)
                try await afterTransfer { try await command(id) }
            } catch let e as SpotifyError { record(e) } catch { ErrorLog.shared.record("command after transfer: \(error)", category: "player") }
        } catch let e as SpotifyError {
            record(e)
        } catch {
            ErrorLog.shared.record("command: \(error)", category: "player")
        }
        // The Mac speaker reports the result itself; otherwise ask.
        if !isLocalActive { await refresh() }
    }

    /// How long the Mac gets to take over after a transfer before a rejected command is re-sent.
    var deviceWakeDelay: Duration = .milliseconds(500)

    /// Runs a command sent right after a transfer. Spotify answers 403 "Restriction violated" until the new device
    /// has taken over, so a rejection is retried twice.
    private func afterTransfer(_ command: () async throws -> Void) async throws {
        for attempt in 0..<3 {
            do { return try await command() }
            catch SpotifyError.forbidden where attempt < 2 { try? await Task.sleep(for: deviceWakeDelay) }
        }
    }

    /// Restarts librespot. Its connection to Spotify can go stale (sleep, network change); librespot reconnects
    /// by itself, but the new connection may never register the Mac as a Connect device again.
    public var restartSpeaker: (@MainActor () async -> Void)?
    static let deviceWaitAttempts = 10
    /// Between device-list checks while a restarted speaker registers.
    var deviceWaitInterval: Duration = .seconds(1)
    private var speakerRestart: Task<String?, Error>?
    /// The speaker is being restarted for a command: the app shows it connecting, not an error.
    public private(set) var isConnectingSpeaker = false

    /// The Mac's device id; if Spotify doesn't list it, restarts the speaker and waits for it to register.
    /// Commands arriving meanwhile share the one restart.
    private func localDeviceIDRestartingSpeaker() async throws -> String? {
        if let running = speakerRestart { return try await running.value }
        if let id = try await localDeviceID() { return id }
        guard let restartSpeaker else { return nil }
        let task = Task { [weak self] () -> String? in
            log.notice("restarting the speaker to register it again")
            await restartSpeaker()
            for _ in 0..<Self.deviceWaitAttempts {
                guard let self else { return nil }
                try? await Task.sleep(for: self.deviceWaitInterval)
                if let id = try await self.localDeviceID() { return id }
            }
            return nil
        }
        speakerRestart = task
        isConnectingSpeaker = true
        defer { speakerRestart = nil; isConnectingSpeaker = false }
        return try await task.value
    }

    func localDeviceID() async throws -> String? {
        let list = try await api.devices()
        devices = list
        devicesFetched = true
        let id = list.first { $0.name == localDeviceName }?.id
        if id == nil { ErrorLog.shared.record("\(localDeviceName) not among devices: \(list.map(\.name))", category: "player") }
        return id
    }

    /// Play/pause. With no active device, moves playback to the Mac and resumes (or plays the last context).
    public func togglePlayPause() async {
        if isRestored, let track {
            await playRestored(track)
        } else if isPlaying {
            clock.setPlaying(false, at: now())
            await perform { [api] _ in try await api.pause() }
        } else {
            clock.setPlaying(true, at: now())
            let fallback = lastContextURI
            await perform { [api] device in
                if let device {
                    // Resume where Spotify left off; only restart the last context if there's nothing to resume.
                    do { try await api.play(.resume, deviceID: device) }
                    catch let error as SpotifyError where error != .noActiveDevice && fallback != nil {
                        try await api.play(.context(fallback!), deviceID: device)
                    }
                } else {
                    try await api.play(.resume, deviceID: nil)
                }
            }
        }
    }

    /// Starts last run's track where it stopped, in its context when the context allows starting at a track.
    private func playRestored(_ track: Track) async {
        let position = clock.positionMs(at: now())
        let context = state?.context?.uri
        clock.setPlaying(true, at: now())
        await perform { [api] device in
            if let context {
                do {
                    try await api.play(PlayRequest(contextURI: context, uris: nil, offsetURI: track.uri, positionMs: position),
                                       deviceID: device)
                    return
                } catch let error as SpotifyError where error != .noActiveDevice {
                    // e.g. an artist context can't start at a given track: play the track alone
                }
            }
            try await api.play(PlayRequest(contextURI: nil, uris: [track.uri], offsetURI: nil, positionMs: position),
                               deviceID: device)
        }
    }

    public func next() async { await perform { [api] _ in try await api.next() } }
    public func previous() async { await perform { [api] _ in try await api.previous() } }

    static let skipBackMs = 15_000
    static let skipForwardMs = 30_000

    /// Back 15 s, for episodes (podcasts spec §6.3).
    public func skipBack() async {
        await seek(toMs: max(0, clock.positionMs(at: now()) - Self.skipBackMs))
    }

    /// Forward 30 s, stopping a second before the end.
    public func skipForward() async {
        guard let duration = track?.durationMs, duration > 0 else { return } // unknown length: don't jump to the start
        let end = duration - 1000
        await seek(toMs: min(end, clock.positionMs(at: now()) + Self.skipForwardMs))
    }

    // MARK: Next newer episode

    /// The show's episodes, newest first (the app reads them through `LibraryStore`'s cache).
    /// Given the show and the playing episode's id (the app pages on until the list holds it).
    public var episodesOfShow: (@MainActor (ShowRef, String) async -> [Track])?
    /// The episode whose follower was already queued (or found to be the newest), so polls don't queue it again.
    private var queuedAfter: String?

    /// When an episode plays, queues the one released after it (podcasts spec §6.2). Needs the show's id, which a
    /// librespot event lacks: the metadata poll brings it and calls this again.
    func queueNextEpisode() async {
        guard !isRestored, state?.device != nil, let current = track, current.isEpisode, current.id != queuedAfter,
              let show = current.show, show.id != nil, let episodesOfShow else { return }
        queuedAfter = current.id // before any await: an overlapping poll stops at the guard
        let episodes = await episodesOfShow(show, current.id)
        guard track?.id == current.id else { return }
        guard let index = episodes.firstIndex(where: { $0.id == current.id }) else { queuedAfter = nil; return } // retry later
        guard index > 0 else { return } // the newest: nothing after it
        let next = episodes[index - 1]
        guard !upNext.contains(where: { $0.id == next.id }) else { return }
        // Queued items survive new plays and relaunches, and Spotify can't unqueue: ask before adding.
        if let queued = try? await api.queue(), queued.queue.contains(where: { $0.id == next.id }) { return }
        await addToQueue(uri: next.uri)
    }

    // MARK: Episode progress

    /// Where each episode stopped this session: its cached resume point can be hours old (podcasts review 4).
    public private(set) var episodeProgress: [String: Int] = [:]

    /// Where playing `episode` should start: where it stopped this session, else its resume point.
    public func startPosition(for episode: Track) -> Int? { episodeProgress[episode.id] ?? episode.startPositionMs }

    /// Remembers the current episode's position before the player moves on or pauses.
    private func noteEpisodeProgress() {
        guard let current = track, current.isEpisode, !isRestored else { return }
        episodeProgress[current.id] = clock.positionMs(at: now())
    }

    public func seek(toMs ms: Int) async {
        clock.seek(toMs: ms, at: now())
        if isRestored { return } // nothing loaded anywhere yet: play will start here
        await perform { [api] _ in try await api.seek(toMs: ms) }
    }

    public func setVolume(_ percent: Int) async { await perform { [api] _ in try await api.setVolume(percent) } }
    public func setShuffle(_ on: Bool) async { await perform { [api] _ in try await api.setShuffle(on) } }
    public func setRepeat(_ mode: RepeatMode) async { await perform { [api] _ in try await api.setRepeat(mode) } }

    /// Starts a list. With shuffle on (or `shuffled`), shuffle is sent again once the list has loaded: librespot 0.8
    /// loads a Web API play in list order even while shuffling, and re-sending reshuffles it after the playing track.
    /// Sent together with the play, Spotify may run the two in either order.
    public func play(_ request: PlayRequest, shuffled: Bool? = nil) async {
        log.info("play \(request.contextURI ?? request.uris?.first ?? "?", privacy: .public) from \(request.offsetURI ?? "start", privacy: .public)")
        if let context = request.contextURI { lastContextURI = context }
        // An episode plays alone: nothing to shuffle.
        let isEpisode = request.uris?.first?.hasPrefix("spotify:episode:") == true
        // Its follower rides in the request: nothing to queue after it.
        if isEpisode, let uris = request.uris, uris.count > 1, let id = uris[0].split(separator: ":").last { queuedAfter = String(id) }
        let shuffle = !isEpisode && (shuffled ?? state?.shuffleState ?? false)
        let onMac = isLocalActive || activeDevice == nil || activeDevice?.name == localDeviceName
        pendingReshuffle = shuffle && onMac
            ? PendingReshuffle(startTrackID: request.offsetURI.flatMap { Self.trackID(fromURI: $0) }, until: now().addingTimeInterval(10))
            : nil
        await perform { [api] device in try await api.play(request, deviceID: device) }
        if shuffle && !onMac {
            try? await Task.sleep(for: remoteReshuffleDelay)
            await setShuffle(true)
        }
    }

    /// Shuffle to re-send when the Mac reports the list it was just asked to play.
    struct PendingReshuffle {
        let startTrackID: String?
        let until: Date
    }
    private var pendingReshuffle: PendingReshuffle?
    /// How long a remote device gets to load the list before shuffle is sent.
    var remoteReshuffleDelay: Duration = .seconds(1)

    /// A new track loaded (or the requested first track started): send the pending shuffle once.
    private func reshuffleIfPending(trackID: String, loaded: Bool) async {
        guard let pending = pendingReshuffle else { return }
        guard now() < pending.until else { pendingReshuffle = nil; return }
        guard loaded || pending.startTrackID == nil || pending.startTrackID == trackID else { return }
        pendingReshuffle = nil
        await setShuffle(true)
    }

    private static func trackID(fromURI uri: String) -> String? {
        uri.hasPrefix("spotify:track:") ? String(uri.dropFirst("spotify:track:".count)) : nil
    }

    /// Song radio (spec §4.6): play only this track; autoplay continues with similar songs.
    public func startRadio(trackURI: String) async { await play(.tracks([trackURI])) }

    /// Up next, for the player bar's queue popover.
    public private(set) var upNext: [Track] = []

    public func refreshQueue() async {
        do { upNext = try await api.queue().queue } catch let e as SpotifyError { record(e) } catch {}
    }

    public func addToQueue(uri: String) async { await perform { [api] _ in try await api.addToQueue(uri: uri) } }

    public func transfer(to device: Device) async {
        guard let id = device.id else { return }
        await perform { [api] _ in try await api.transferPlayback(to: id, play: true) }
    }
}

// MARK: Last played

extension PlayerStore {
    private func restoreLastPlayed() {
        guard let data = defaults?.data(forKey: Self.lastPlayedKey),
              let saved = try? JSONDecoder().decode(LastPlayed.self, from: data) else { return }
        state = PlaybackState(device: nil, isPlaying: false, progressMs: saved.positionMs, item: saved.track,
                              context: saved.context)
        clock.sync(progressMs: saved.positionMs, durationMs: saved.track.durationMs, isPlaying: false, at: now())
        lastContextURI = saved.context?.uri
        isRestored = true
    }

    /// Playback stopped everywhere: keep showing the last track, paused, as if restored at launch (play starts it again).
    private func keepLastPlayed() {
        noteEpisodeProgress()
        clock.setPlaying(false, at: now())
        state = PlaybackState(device: nil, isPlaying: false, progressMs: clock.positionMs(at: now()), item: track,
                              context: state?.context)
        rememberLastPlayed()
        isRestored = true
    }

    /// Saves when the track, play state or context changes (a pause saves the position it paused at).
    func rememberLastPlayed() {
        guard !isRestored, let track else { return }
        let key = "\(track.id)|\(isPlaying)|\(state?.context?.uri ?? "")"
        guard key != lastSavedKey else { return }
        lastSavedKey = key
        saveLastPlayed()
    }

    /// Saves the current track and position now; call it when the app quits.
    public func saveLastPlayed() {
        guard let defaults, let track else { return }
        let saved = LastPlayed(track: track, context: state?.context, positionMs: clock.positionMs(at: now()))
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.lastPlayedKey) }
    }
}

extension PlaybackState {
    func replacing(isPlaying: Bool? = nil, device: Device? = nil, shuffle: Bool? = nil, repeatMode: RepeatMode? = nil) -> PlaybackState {
        PlaybackState(device: device ?? self.device, isPlaying: isPlaying ?? self.isPlaying, progressMs: progressMs, item: item,
                      shuffleState: shuffle ?? shuffleState, repeatState: repeatMode ?? repeatState, context: context)
    }
}
