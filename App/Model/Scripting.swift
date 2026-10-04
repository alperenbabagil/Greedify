import AppKit
import GreedifyKit

/// AppleScript access in Spotify's vocabulary (dictionary: `Resources/Greedify.sdef`), so now-playing widgets
/// written for Spotify work with `tell application "Greedify"`. Cocoa scripting runs on the main thread.
@MainActor
enum Scripting {
    static weak var model: AppModel?

    /// Every read keeps the player polling fast for a while, so a widget that polls us sees fresh state.
    static var player: PlayerStore? {
        let player = model?.player
        player?.scriptDidRead()
        return player
    }

    static var playerState: NSNumber {
        let code: String = switch player?.scriptPlayerState ?? .stopped {
        case .stopped: "kPSS"
        case .playing: "kPSP"
        case .paused: "kPSp"
        }
        return NSNumber(value: fourCharCode(code))
    }

    static var currentTrack: ScriptTrack? {
        player?.track.map(ScriptTrack.init)
    }

    /// Commands return at once; the Web API call finishes in the background.
    nonisolated static func run(_ command: @escaping @MainActor (PlayerStore) async -> Void) {
        MainActor.assumeIsolated {
            guard let player = model?.player else { return }
            Task { await command(player) }
        }
    }

    static func fourCharCode(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}

/// `current track`: a snapshot of the track playing when the script asked.
@objc(GreedifyScriptTrack)
final class ScriptTrack: NSObject {
    @objc let name: String
    @objc let artist: String
    @objc let album: String
    @objc let duration: Int
    @objc let trackID: String
    @objc let spotifyURL: String

    init(_ track: Track) {
        name = track.name
        artist = track.artistLine
        album = track.album?.name ?? ""
        duration = track.durationMs / 1000
        trackID = track.uri
        spotifyURL = track.uri
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let app = NSScriptClassDescription(for: NSApplication.self) else { return nil }
        return NSPropertySpecifier(containerClassDescription: app, containerSpecifier: nil, key: "currentTrack")
    }
}

@objc(GreedifyPlayPauseCommand)
final class PlayPauseCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? { Scripting.run { await $0.togglePlayPause() }; return nil }
}

@objc(GreedifyPlayCommand)
final class PlayCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Scripting.run { if !$0.isPlaying { await $0.togglePlayPause() } }; return nil
    }
}

@objc(GreedifyPauseCommand)
final class PauseCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Scripting.run { if $0.isPlaying { await $0.togglePlayPause() } }; return nil
    }
}

@objc(GreedifyNextCommand)
final class NextCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? { Scripting.run { await $0.next() }; return nil }
}

@objc(GreedifyPreviousCommand)
final class PreviousCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? { Scripting.run { await $0.previous() }; return nil }
}
