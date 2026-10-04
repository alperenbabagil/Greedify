import Foundation
import os

private let librespotLog = Logger(subsystem: "com.alperen.greedify", category: "librespot")

/// Runs librespot (through the `greedify-speaker` launcher) as a child of Greedify, so the music stops
/// when Greedify quits. The launcher also watches Greedify's pid and stops librespot if Greedify crashes.
/// If librespot exits on its own, it is restarted with a growing delay.
@MainActor
public final class SpeakerProcess {
    public private(set) var isRunning = false
    /// Player events librespot prints on stdout (see `LibrespotEvent`), in order, across restarts.
    public let events: AsyncStream<LibrespotEvent>
    private let eventSink: AsyncStream<LibrespotEvent>.Continuation

    let launcher: URL
    let environment: [String: String]
    let baseDelay: Duration
    private var process: Process?
    private var wanted = false
    private var delay: Duration
    private var startedAt = ContinuousClock.now
    static let maxDelay: Duration = .seconds(30)
    /// A run at least this long counts as healthy and resets the restart delay.
    static let healthyRun: Duration = .seconds(30)
    /// How long librespot gets to reconnect by itself after its session to Spotify closes.
    let reconnectGrace: Duration
    private var reconnectWatch: Task<Void, Never>?

    public init(launcher: URL, environment: [String: String] = [:], restartDelay: Duration = .seconds(2),
                reconnectGrace: Duration = .seconds(10)) {
        self.launcher = launcher
        self.environment = environment
        self.reconnectGrace = reconnectGrace
        baseDelay = restartDelay
        delay = restartDelay
        (events, eventSink) = AsyncStream.makeStream(of: LibrespotEvent.self)
    }

    public func start() {
        wanted = true
        guard process == nil else { return }
        let p = Process()
        p.executableURL = launcher
        p.environment = ProcessInfo.processInfo.environment
            .merging(["GREEDIFY_PARENT_PID": String(getpid())]) { $1 }
            .merging(environment) { $1 }
        // Called on a background queue: @Sendable, and nothing here touches the main actor.
        let lines = LineSplitter()
        let sink = eventSink
        let stdout = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return } // EOF: the launcher exited
            for line in lines.feed(data) {
                if let event = LibrespotEvent.parse(line) { sink.yield(event) }
            }
        }
        p.standardOutput = stdout
        // librespot's own log (stderr) goes to the unified log, so a device that drops out leaves a trace.
        let errLines = LineSplitter()
        let stderr = Pipe()
        stderr.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            for line in errLines.feed(data) {
                // librespot's lines look like `[2026-10-01T12:00:00Z ERROR librespot_core::session] …`.
                if line.contains(" ERROR ") { ErrorLog.shared.record(line, category: "librespot") }
                else { librespotLog.info("\(line, privacy: .public)") }
                if let session = SessionLine(line) { Task { @MainActor [weak self] in self?.saw(session, from: p) } }
            }
        }
        p.standardError = stderr
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.exited(p) }
        }
        do {
            try p.run()
            process = p
            isRunning = true
            startedAt = .now
        } catch {
            ErrorLog.shared.record("can't start the speaker: \(error.localizedDescription)", category: "librespot")
            scheduleRestart()
        }
    }

    /// librespot 0.8 re-checks its session only when something wakes its main loop, so a session Spotify closes
    /// while the speaker is idle is never replaced and the Mac drops out of the device list. If librespot doesn't
    /// log in again within `reconnectGrace`, it is restarted.
    private func saw(_ line: SessionLine, from p: Process) {
        guard process === p else { return }
        switch line {
        case .closed:
            guard reconnectWatch == nil else { return }
            let grace = reconnectGrace
            reconnectWatch = Task { [weak self] in
                try? await Task.sleep(for: grace)
                guard !Task.isCancelled, let self, self.process === p else { return }
                self.reconnectWatch = nil
                ErrorLog.shared.record("speaker's session closed and it didn't reconnect; restarting it", category: "librespot")
                await self.restart()
            }
        case .authenticated:
            reconnectWatch?.cancel()
            reconnectWatch = nil
        }
    }

    /// Stops librespot and waits (up to 5 s) for it to exit. It won't be restarted.
    public func stop() async {
        wanted = false
        reconnectWatch?.cancel()
        reconnectWatch = nil
        guard let p = process else { return }
        p.terminate()
        let deadline = ContinuousClock.now + .seconds(5)
        while p.isRunning, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        if process === p { process = nil; isRunning = false }
    }

    /// For app termination, where there is no time to await: signal and return.
    public func stopNow() {
        wanted = false
        process?.terminate()
    }

    public func restart() async {
        await stop()
        delay = baseDelay
        start()
    }

    private func exited(_ p: Process) {
        guard process === p else { return }
        process = nil
        isRunning = false
        let ran = ContinuousClock.now - startedAt
        if ran >= Self.healthyRun { delay = baseDelay }
        if wanted {
            let reason = p.terminationReason == .uncaughtSignal ? "signal \(p.terminationStatus)" : "status \(p.terminationStatus)"
            ErrorLog.shared.record("speaker exited (\(reason)) after \(ran.formatted(.units(allowed: [.minutes, .seconds], width: .narrow))); restarting in \(delay.formatted(.units(allowed: [.seconds], width: .narrow)))",
                                   category: "librespot")
        }
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard wanted else { return }
        let wait = delay
        delay = min(delay * 2, Self.maxDelay)
        Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, self.wanted, self.process == nil else { return }
            self.start()
        }
    }
}

/// The librespot log lines that say its session to Spotify ended or began. Every error librespot's session logs
/// (closed connection, broken pipe, no access point) leaves the session unusable.
enum SessionLine {
    case closed, authenticated

    init?(_ line: String) {
        if line.contains("Connection to server closed") || line.contains("ERROR librespot_core::session]") {
            self = .closed
        } else if line.contains("Authenticated as ") {
            self = .authenticated
        } else {
            return nil
        }
    }
}

/// Splits a byte stream into lines; keeps a partial last line for the next chunk.
final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func feed(_ data: Data) -> [String] {
        lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
    }
}
