import AppKit
import Foundation
import ServiceManagement

/// librespot command line (spec §3, §5). Written one argument per line to an args file that
/// the bundled `greedify-speaker` launcher reads, so settings can change without re-signing the app.
public struct LibrespotConfig: Equatable, Sendable {
    public var deviceName: String
    public var bitrate: Int                 // 96, 160 or 320
    public var normalisation: Bool
    public var audioCacheLimitBytes: Int?   // nil = audio cache off
    public var systemCacheDir: URL          // credentials; never cleared by "Clear"
    public var audioCacheDir: URL

    public init(deviceName: String, bitrate: Int, normalisation: Bool, audioCacheLimitBytes: Int?,
                systemCacheDir: URL, audioCacheDir: URL) {
        self.deviceName = deviceName; self.bitrate = bitrate; self.normalisation = normalisation
        self.audioCacheLimitBytes = audioCacheLimitBytes
        self.systemCacheDir = systemCacheDir; self.audioCacheDir = audioCacheDir
    }

    public var arguments: [String] {
        var args = ["--name", deviceName, "--device-type", "computer",
                    "--bitrate", String(bitrate), "--autoplay", "on",
                    "--system-cache", systemCacheDir.path, "--cache", audioCacheDir.path,
                    // The default log scale over 60 dB made 70% sound like 30% (-18 dB); linear keeps 70% near -3 dB.
                    "--volume-ctrl", "linear"]
        if normalisation { args.append("--enable-volume-normalisation") }
        if let limit = audioCacheLimitBytes {
            args += ["--cache-size-limit", "\(max(1, limit / 1_048_576))M"]
        } else {
            args.append("--disable-audio-cache")
        }
        return args
    }

    /// Arguments for the one-time interactive login (setup step 3).
    public var loginArguments: [String] { arguments + ["--enable-oauth"] }

    public var argsFileContents: String { arguments.joined(separator: "\n") + "\n" }

    public var credentialsFile: URL { systemCacheDir.appendingPathComponent("credentials.json") }
}

public enum GreedifyPaths {
    public static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Greedify")
    }
    public static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Greedify")
    }
    public static var appCache: URL { caches.appendingPathComponent("data") }
    /// The import era's user themes; read once to migrate a selection (curated skins spec §4).
    public static var themes: URL { appSupport.appendingPathComponent("Themes") }
    /// Recipes being tuned, loaded live in Debug builds (curated skins spec §5).
    public static var recipes: URL { appSupport.appendingPathComponent("Recipes") }
    public static var librespotSystemCache: URL { appSupport.appendingPathComponent("librespot") }
    public static var librespotAudioCache: URL { caches.appendingPathComponent("librespot-audio") }
    public static var librespotArgsFile: URL { appSupport.appendingPathComponent("librespot-args") }
    /// `errors.log` (see `ErrorLog`); in ~/Library/Logs so Console.app lists it.
    public static var logs: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Greedify")
    }
}

/// The Mac speaker: librespot running as a child of Greedify (spec §3), so it stops when Greedify quits.
@MainActor
public final class LibrespotService {
    /// The launchd label used by earlier builds, which ran librespot as a LaunchAgent.
    public nonisolated static let legacyAgentLabel = "com.alperen.greedify.librespot"
    let speaker: SpeakerProcess?

    /// `launcher` is the bundled `greedify-speaker` script; nil only when the bundle is broken.
    public init(launcher: URL? = Bundle.main.url(forAuxiliaryExecutable: "greedify-speaker")) {
        speaker = launcher.map { SpeakerProcess(launcher: $0) }
    }

    public var isRunning: Bool { speaker?.isRunning ?? false }
    /// Player events from the Mac speaker (see `LibrespotEvent`).
    public var events: AsyncStream<LibrespotEvent> { speaker?.events ?? AsyncStream { $0.finish() } }
    public var hasCredentials: Bool { FileManager.default.fileExists(atPath: GreedifyPaths.librespotSystemCache.appendingPathComponent("credentials.json").path) }

    public func writeArgs(_ config: LibrespotConfig) throws {
        try FileManager.default.createDirectory(at: GreedifyPaths.appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.systemCacheDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.audioCacheDir, withIntermediateDirectories: true)
        try config.argsFileContents.write(to: GreedifyPaths.librespotArgsFile, atomically: true, encoding: .utf8)
    }

    /// Writes the arguments and starts librespot (no-op if it's already running).
    public func start(_ config: LibrespotConfig) throws {
        try writeArgs(config)
        speaker?.start()
    }

    public func stop() async { await speaker?.stop() }

    /// True when the args file on disk differs from `config` (e.g. a rename that was never applied).
    public func argsOutdated(_ config: LibrespotConfig) -> Bool {
        (try? String(contentsOf: GreedifyPaths.librespotArgsFile, encoding: .utf8)) != config.argsFileContents
    }

    /// For app termination: signal librespot and return immediately.
    public func stopNow() { speaker?.stopNow() }

    /// Applies new settings: rewrite args and restart librespot (~1 s of silence).
    public func apply(_ config: LibrespotConfig) async throws {
        try writeArgs(config)
        await restart()
    }

    public func restart() async { await speaker?.restart() }

    /// Clears the audio cache without touching credentials, then restarts librespot.
    public func clearAudioCache(_ config: LibrespotConfig) async {
        try? FileManager.default.removeItem(at: config.audioCacheDir)
        try? FileManager.default.createDirectory(at: config.audioCacheDir, withIntermediateDirectories: true)
        await restart()
    }

    /// Earlier builds registered librespot as a LaunchAgent that outlived Greedify. Remove it.
    public static func removeLegacyAgent() async {
        let agent = SMAppService.agent(plistName: "\(legacyAgentLabel).plist")
        if agent.status != .notRegistered { try? await agent.unregister() }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["bootout", "gui/\(getuid())/\(legacyAgentLabel)"]
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { _ in cont.resume() }
            do { try p.run() } catch { cont.resume() }
        }
    }

    /// Setup step 3: runs librespot with `--enable-oauth`, reports the login URL it prints through
    /// `onLoginURL` (the caller opens it and offers "Copy Login Link"), and waits until
    /// `credentials.json` appears. Returns false on timeout or if librespot can't start.
    public func interactiveLogin(_ config: LibrespotConfig, librespotURL: URL, timeout: Duration = .seconds(300),
                                 onLoginURL: @escaping @Sendable (URL) -> Void) async -> Bool {
        try? FileManager.default.createDirectory(at: config.systemCacheDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: config.audioCacheDir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = librespotURL
        p.arguments = config.loginArguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        // Runs on a background queue, so it must not be main-actor isolated (@Sendable).
        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return } // EOF: librespot exited
            if let url = Self.loginURL(in: String(decoding: data, as: UTF8.self)) { onLoginURL(url) }
        }
        do { try p.run() } catch { return false }
        defer { pipe.fileHandleForReading.readabilityHandler = nil; if p.isRunning { p.terminate() } }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if FileManager.default.fileExists(atPath: config.credentialsFile.path) { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    public nonisolated static func loginURL(in output: String) -> URL? {
        guard let range = output.range(of: #"https://accounts\.spotify\.com/[^\s"']+"#, options: .regularExpression) else { return nil }
        return URL(string: String(output[range]))
    }
}

/// Greedify itself as a login item.
@MainActor
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public static func set(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { ErrorLog.shared.record("login item \(enabled ? "on" : "off"): \(error.localizedDescription)", category: "app") }
    }
}
