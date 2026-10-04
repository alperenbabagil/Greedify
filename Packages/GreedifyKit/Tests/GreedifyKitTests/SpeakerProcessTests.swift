import Foundation
import Testing
@testable import GreedifyKit

/// Drives the real launcher script (App/Resources/greedify-speaker) with a fake librespot.
@MainActor
struct SpeakerProcessTests {
    static let launcher = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // Tests/GreedifyKitTests → package
        .deletingLastPathComponent().deletingLastPathComponent()                             // Packages/GreedifyKit → repo
        .appendingPathComponent("App/Resources/greedify-speaker")

    struct Rig {
        let dir: URL
        let env: [String: String]
        var pidFile: URL { dir.appendingPathComponent("pid") }
        var countFile: URL { dir.appendingPathComponent("count") }
        var argsFile: URL { dir.appendingPathComponent("args") }

        /// Fake librespot: records its pid, a start count and its arguments, prints `stdout`, and on its first run
        /// `stderr`; exits 3 on its first run when `crashFirst`, otherwise sleeps until killed.
        init(crashFirst: Bool = false, args: [String] = ["--name", "Studio Mac"], stdout: String = "",
             stderr: String = "") throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("greedify-speaker-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fake = dir.appendingPathComponent("librespot")
            try """
            #!/bin/sh
            d="\(dir.path)"
            echo $$ > "$d/pid"
            n=$(cat "$d/count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$d/count"
            printf '%s\\n' "$@" > "$d/args"
            printf '\(stdout)'
            if [ $n -eq 1 ]; then printf '\(stderr)' >&2; fi
            if [ "\(crashFirst ? 1 : 0)" = 1 ] && [ $n -eq 1 ]; then exit 3; fi
            exec sleep 60
            """.write(to: fake, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
            let argsFile = dir.appendingPathComponent("librespot-args")
            try (args.joined(separator: "\n") + "\n").write(to: argsFile, atomically: true, encoding: .utf8)
            env = ["GREEDIFY_LIBRESPOT": fake.path, "GREEDIFY_ARGS_FILE": argsFile.path]
        }

        func pid() -> Int32? { (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
        func count() -> Int { (try? String(contentsOf: countFile, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0 }
    }

    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    static func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    @Test func startsLibrespotWithArgsAndStopsIt() async throws {
        let rig = try Rig()
        let speaker = SpeakerProcess(launcher: Self.launcher, environment: rig.env)
        speaker.start()
        #expect(await Self.waitUntil { rig.pid() != nil })
        #expect(speaker.isRunning)
        let event = Self.launcher.deletingLastPathComponent().appendingPathComponent("greedify-event").path
        #expect(try String(contentsOf: rig.argsFile, encoding: .utf8) == "--name\nStudio Mac\n--onevent\n\(event)\n")
        let pid = try #require(rig.pid())
        await speaker.stop()
        #expect(await Self.waitUntil { !Self.isAlive(pid) })
        #expect(!speaker.isRunning)
    }

    @Test func eventsOnStdoutArriveInOrder() async throws {
        let rig = try Rig(stdout: "[INFO] noise\\nGREEDIFY-EVENT\\tPLAYER_EVENT=playing\\tTRACK_ID=t\\tPOSITION_MS=5\\n"
                            + "GREEDIFY-EVENT\\tPLAYER_EVENT=paused\\tTRACK_ID=t\\tPOSITION_MS=9\\n")
        let speaker = SpeakerProcess(launcher: Self.launcher, environment: rig.env)
        speaker.start()
        var received: [LibrespotEvent] = []
        for await event in speaker.events {
            received.append(event)
            if received.count == 2 { break }
        }
        #expect(received == [.playing(trackID: "t", positionMs: 5), .paused(trackID: "t", positionMs: 9)])
        await speaker.stop()
    }

    @Test func restartsAfterLibrespotExitsOnItsOwn() async throws {
        let rig = try Rig(crashFirst: true)
        let speaker = SpeakerProcess(launcher: Self.launcher, environment: rig.env, restartDelay: .milliseconds(200))
        speaker.start()
        #expect(await Self.waitUntil { rig.count() >= 2 })
        #expect(await Self.waitUntil { speaker.isRunning })
        await speaker.stop()
    }

    @Test func stoppedSpeakerIsNotRestarted() async throws {
        let rig = try Rig()
        let speaker = SpeakerProcess(launcher: Self.launcher, environment: rig.env, restartDelay: .milliseconds(100))
        speaker.start()
        #expect(await Self.waitUntil { rig.count() == 1 })
        await speaker.stop()
        try await Task.sleep(for: .milliseconds(600))
        #expect(rig.count() == 1)
    }

    static let sessionClosed = "[2026-10-02T17:53:08Z ERROR librespot_core::session] Connection to server closed.\\n"

    /// librespot 0.8 doesn't notice a closed session while idle, so the Mac drops out of the device list for good.
    @Test func restartsWhenTheSessionClosesAndLibrespotDoesNotReconnect() async throws {
        let rig = try Rig(stderr: Self.sessionClosed)
        let speaker = SpeakerProcess(launcher: Self.launcher, environment: rig.env, reconnectGrace: .milliseconds(300))
        speaker.start()
        #expect(await Self.waitUntil { rig.count() >= 2 })
        #expect(await Self.waitUntil { speaker.isRunning })
        await speaker.stop()
    }

    @Test func leavesLibrespotAloneWhenItReconnectsItself() async throws {
        let rig = try Rig(stderr: Self.sessionClosed + "[2026-10-02T17:53:09Z INFO  librespot_core::session] Authenticated as 'me' !\\n")
        let speaker = SpeakerProcess(launcher: Self.launcher, environment: rig.env, reconnectGrace: .milliseconds(300))
        speaker.start()
        #expect(await Self.waitUntil { rig.count() == 1 })
        try await Task.sleep(for: .milliseconds(900))
        #expect(rig.count() == 1)
        await speaker.stop()
    }

    @Test func sessionLinesAreRecognised() {
        #expect(SessionLine("[2026-10-02T18:15:40Z ERROR librespot_core::session] Broken pipe (os error 32)") == .closed)
        #expect(SessionLine("[2026-10-02T17:53:08Z WARN  librespot_core::session] Connection to server closed.") == .closed)
        #expect(SessionLine("[2026-10-02T18:27:19Z INFO  librespot_core::session] Authenticated as 'me' !") == .authenticated)
        #expect(SessionLine("[2026-10-02T18:27:19Z INFO  librespot_core::session] Country: \"TR\"") == nil)
        #expect(SessionLine("[2026-10-02T18:15:55Z ERROR librespot_connect::spirc] Client specified an invalid argument") == nil)
    }

    /// The music must not outlive Greedify, even if Greedify crashes or is force-quit.
    @Test func librespotExitsWhenTheParentDies() async throws {
        let rig = try Rig()
        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/bin/sleep")
        parent.arguments = ["60"]
        try parent.run()
        let launcher = Process()
        launcher.executableURL = Self.launcher
        launcher.environment = ProcessInfo.processInfo.environment.merging(rig.env) { $1 }
            .merging(["GREEDIFY_PARENT_PID": String(parent.processIdentifier)]) { $1 }
        try launcher.run()
        #expect(await Self.waitUntil { rig.pid() != nil })
        let pid = try #require(rig.pid())
        kill(parent.processIdentifier, SIGKILL)   // simulate Greedify crashing
        #expect(await Self.waitUntil(.seconds(4)) { !Self.isAlive(pid) })
        launcher.waitUntilExit()
    }
}
