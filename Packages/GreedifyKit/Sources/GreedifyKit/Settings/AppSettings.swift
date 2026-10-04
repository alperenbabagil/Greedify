import Foundation
import Observation

public enum AppearanceMode: String, CaseIterable, Sendable { case system, light, dark }

/// User preferences, persisted to `UserDefaults` on every change.
@MainActor @Observable
public final class AppSettings {
    @ObservationIgnored let defaults: UserDefaults

    public var clientID: String { didSet { defaults.set(clientID, forKey: "clientID") } }
    public var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    public var blockAppleMusic: Bool { didSet { defaults.set(blockAppleMusic, forKey: "blockAppleMusic") } }
    public var lyricsInMenuBar: Bool { didSet { defaults.set(lyricsInMenuBar, forKey: "lyricsInMenuBar") } }
    /// The podcast pages' "log in again for progress" notice was closed (podcasts spec §5).
    public var podcastNoticeDismissed: Bool { didSet { defaults.set(podcastNoticeDismissed, forKey: "podcastNoticeDismissed") } }
    public var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    /// The selected theme's id (`builtin.<slug>` or a file name in the Themes folder).
    public var themeID: String { didSet { defaults.set(themeID, forKey: "themeID") } }
    public var deviceName: String { didSet { defaults.set(deviceName, forKey: "deviceName") } }
    public var bitrate: Int { didSet { defaults.set(bitrate, forKey: "bitrate") } }
    public var normalisation: Bool { didSet { defaults.set(normalisation, forKey: "normalisation") } }
    public var artworkMemoryMB: Int { didSet { defaults.set(artworkMemoryMB, forKey: "artworkMemoryMB") } }
    public var appCacheMB: Int { didSet { defaults.set(appCacheMB, forKey: "appCacheMB") } }
    /// 0 = audio cache off.
    public var audioCacheGB: Int { didSet { defaults.set(audioCacheGB, forKey: "audioCacheGB") } }
    public var mixes: [MixLink] { didSet { defaults.set(try? JSONEncoder().encode(mixes), forKey: "mixes") } }
    /// Lists and songs shown in the menu-bar popover, in the order they were added.
    public private(set) var quickPlay: [QuickPlayItem] {
        didSet { defaults.set(try? JSONEncoder().encode(quickPlay), forKey: "quickPlay") }
    }
    /// Songs of each mix, by mix URI, collected from the queue while the mix plays.
    public private(set) var mixSongs: [String: MixTracks] {
        didSet { defaults.set(try? JSONEncoder().encode(mixSongs), forKey: "mixSongs") }
    }

    public static let artworkMemoryOptions = [15, 30, 60]
    public static let appCacheOptions = [100, 300, 1024, 2048]
    public static let audioCacheOptions = [0, 1, 2, 5]
    public static let bitrateOptions = [96, 160, 320]

    public init(defaults: UserDefaults = .standard, hostName: String = Host.current().localizedName ?? "Mac") {
        self.defaults = defaults
        defaults.register(defaults: [
            "blockAppleMusic": true, "lyricsInMenuBar": true, "appearance": AppearanceMode.system.rawValue, "themeID": ThemeStore.systemID,
            "deviceName": hostName, "bitrate": 320, "normalisation": true,
            "artworkMemoryMB": 15, "appCacheMB": 300, "audioCacheGB": 0,
        ])
        clientID = defaults.string(forKey: "clientID") ?? ""
        onboardingDone = defaults.bool(forKey: "onboardingDone")
        blockAppleMusic = defaults.bool(forKey: "blockAppleMusic")
        lyricsInMenuBar = defaults.bool(forKey: "lyricsInMenuBar")
        podcastNoticeDismissed = defaults.bool(forKey: "podcastNoticeDismissed")
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        themeID = defaults.string(forKey: "themeID") ?? ThemeStore.systemID
        deviceName = defaults.string(forKey: "deviceName") ?? hostName
        bitrate = defaults.integer(forKey: "bitrate")
        normalisation = defaults.bool(forKey: "normalisation")
        artworkMemoryMB = defaults.integer(forKey: "artworkMemoryMB")
        appCacheMB = defaults.integer(forKey: "appCacheMB")
        audioCacheGB = defaults.integer(forKey: "audioCacheGB")
        mixes = defaults.data(forKey: "mixes").flatMap { try? JSONDecoder().decode([MixLink].self, from: $0) } ?? []
        quickPlay = defaults.data(forKey: "quickPlay").flatMap { try? JSONDecoder().decode([QuickPlayItem].self, from: $0) } ?? []
        mixSongs = defaults.data(forKey: "mixSongs").flatMap { try? JSONDecoder().decode([String: MixTracks].self, from: $0) } ?? [:]
    }

    public var librespotConfig: LibrespotConfig {
        LibrespotConfig(deviceName: deviceName, bitrate: bitrate, normalisation: normalisation,
                        audioCacheLimitBytes: audioCacheGB == 0 ? nil : audioCacheGB * 1_073_741_824,
                        systemCacheDir: GreedifyPaths.librespotSystemCache, audioCacheDir: GreedifyPaths.librespotAudioCache)
    }

    public func addMix(link: String, name: String) -> Bool {
        guard let uri = MixLink.uri(fromLink: link), !mixes.contains(where: { $0.uri == uri }) else { return false }
        mixes.append(MixLink(uri: uri, name: name.isEmpty ? "Mix \(mixes.count + 1)" : name))
        return true
    }

    public func removeMix(_ mix: MixLink) {
        mixes.removeAll { $0.uri == mix.uri }
        mixSongs[mix.uri] = nil
    }

    /// Records the songs seen in the queue while the mix `uri` plays (the current song first).
    public func recordMixTracks(uri: String, tracks: [Track], at date: Date = Date(), calendar: Calendar = .current) {
        guard let mix = mixes.first(where: { $0.uri == uri }), !tracks.isEmpty else { return }
        let saved = mixSongs[uri] ?? MixTracks(tracks: [], startedAt: .distantPast)
        let updated = saved.merged(with: tracks, at: date, name: mix.name, calendar: calendar)
        // Also saved when only the time moves: it's what keeps the list from counting as outdated.
        if updated.tracks.map(\.id) != saved.tracks.map(\.id) || date.timeIntervalSince(saved.capturedAt) > 600 {
            mixSongs[uri] = updated
        }
    }

    /// When the mix's songs were last seen, and whether playing it would refresh them. `nil` before its first play.
    public func mixFreshness(_ uri: String, at date: Date = Date()) -> (capturedAt: Date, outdated: Bool)? {
        guard let songs = mixSongs[uri], !songs.tracks.isEmpty, let mix = mixes.first(where: { $0.uri == uri }) else { return nil }
        return (songs.capturedAt, songs.isOutdated(at: date, name: mix.name))
    }

    public func mixTracks(_ uri: String) -> [Track] { mixSongs[uri]?.tracks ?? [] }
    /// The mix's cover: its first song's album art.
    public func mixCover(_ uri: String) -> [SpotifyImage] { mixTracks(uri).first?.album?.images ?? [] }

    public func addToMenuBar(_ item: QuickPlayItem) {
        guard !isInMenuBar(item.uri) else { return }
        quickPlay.append(item)
    }

    public func removeFromMenuBar(_ uri: String) { quickPlay.removeAll { $0.uri == uri } }

    /// Moves an added item so it ends up at `index` in the popover's list. An unknown item or index does nothing.
    public func moveInMenuBar(_ uri: String, to index: Int) {
        guard let from = quickPlay.firstIndex(where: { $0.uri == uri }), quickPlay.indices.contains(index), from != index else { return }
        quickPlay.insert(quickPlay.remove(at: from), at: index)
    }

    public func isInMenuBar(_ uri: String) -> Bool { quickPlay.contains { $0.uri == uri } }

    /// Wipes everything (Settings → Reset Greedify).
    public func reset() {
        for key in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: key) }
    }
}
