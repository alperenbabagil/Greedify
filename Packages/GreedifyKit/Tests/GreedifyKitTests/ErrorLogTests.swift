import Foundation
import Synchronization
import Testing
@testable import GreedifyKit

/// A settable clock for the repeat window.
final class TestClock: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { value.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { value.withLock { $0 += seconds } }
}

struct ErrorLogTests {
    static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("greedify-errorlog-\(UUID().uuidString)")
    }

    static func make(maxBytes: Int = 64 * 1024, clock: TestClock = TestClock()) -> (ErrorLog, URL) {
        let dir = tempDir()
        let log = ErrorLog(maxBytes: maxBytes, now: { clock.now })
        log.open(directory: dir)
        return (log, dir)
    }

    static func file(_ dir: URL, _ name: String = ErrorLog.fileName) -> String {
        (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    @Test func appendsOneLinePerErrorWithCategory() {
        let (log, dir) = Self.make()
        log.record("GET me/player → 500", category: "api")
        log.record("librespot exited", category: "librespot")
        let lines = Self.file(dir).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("[api] GET me/player → 500"))
        #expect(lines[1].hasSuffix("[librespot] librespot exited"))
    }

    @Test func keepsMultiLineMessagesOnOneLine() {
        let (log, dir) = Self.make()
        log.record("first\nsecond", category: "app")
        #expect(Self.file(dir).split(separator: "\n").count == 1)
        #expect(Self.file(dir).contains("first ⏎ second"))
    }

    @Test func writesNothingToDiskUntilOpened() {
        let log = ErrorLog()
        log.record("only to the unified log", category: "app")
        #expect(log.fileURL == nil)
        #expect(log.recentText() == "")
    }

    @Test func countsRepeatsInsteadOfRewritingThem() {
        let clock = TestClock()
        let (log, dir) = Self.make(clock: clock)
        for _ in 0..<5 { log.record("offline", category: "api"); clock.advance(5) }
        log.record("something else", category: "api")
        let lines = Self.file(dir).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasSuffix("[api] offline"))
        #expect(lines[1].contains("repeated 4 more times"))
        #expect(lines[2].hasSuffix("[api] something else"))
    }

    @Test func pendingRepeatsShowInRecentText() {
        let (log, _) = Self.make()
        log.record("offline", category: "api")
        log.record("offline", category: "api")
        #expect(log.recentText().contains("repeated 1 more time"))
    }

    @Test func repeatAfterTheWindowIsWrittenAgain() {
        let clock = TestClock()
        let (log, dir) = Self.make(clock: clock)
        log.record("offline", category: "api")
        clock.advance(ErrorLog.repeatWindow + 1)
        log.record("offline", category: "api")
        #expect(Self.file(dir).split(separator: "\n").count == 2)
    }

    @Test func rotatesIntoOnePreviousFile() {
        let (log, dir) = Self.make(maxBytes: 200)
        for i in 0..<12 { log.record("error number \(i) with some padding text", category: "api") }
        let current = Self.file(dir), previous = Self.file(dir, ErrorLog.previousFileName)
        #expect(!current.isEmpty && !previous.isEmpty)
        #expect(current.utf8.count <= 200 && previous.utf8.count <= 200)
        #expect(current.contains("error number 11"))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        #expect(Set(files) == [ErrorLog.fileName, ErrorLog.previousFileName])
    }

    @Test func recentTextIsOldestFirstAcrossRotationAndLimited() {
        let (log, _) = Self.make(maxBytes: 200)
        for i in 0..<12 { log.record("error number \(i) with some padding text", category: "api") }
        let text = log.recentText(maxLines: 3)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines.last?.hasSuffix("error number 11 with some padding text") == true)
        #expect(lines.first?.contains("error number 9") == true)
    }

    @Test func notesAreWrittenWithoutCountingAsRepeats() {
        let (log, dir) = Self.make()
        log.note("launched 1.0")
        log.note("launched 1.0")
        #expect(Self.file(dir).split(separator: "\n").count == 2)
        #expect(Self.file(dir).contains("── launched 1.0"))
    }
}

struct APIErrorLoggingTests {
    static func api(_ stub: StubTransport, tokens: Tokens? = Fixture.freshTokens) -> (LiveSpotifyAPI, URL) {
        let (log, dir) = ErrorLogTests.make()
        let auth = AuthService(config: AuthConfig(clientID: "cid", redirectURI: URL(string: "greedify://callback")!), transport: stub)
        return (LiveSpotifyAPI(auth: auth, tokens: InMemoryTokenStore(tokens), transport: stub, errors: log), dir)
    }

    @Test func recordsFailedRequests() async {
        let (api, dir) = Self.api(StubTransport { _ in (500, #"{"error":{"status":500,"message":"Server error"}}"#, [:]) })
        _ = try? await api.devices()
        #expect(ErrorLogTests.file(dir).contains("[api] GET me/player/devices → 500: http(status: 500, message: \"Server error\")"))
    }

    @Test func recordsTransportAndDecodingFailures() async {
        let stub = StubTransport { _ in throw SpotifyError.transport("offline") }
        let (api, dir) = Self.api(stub)
        _ = try? await api.devices()
        stub.setHandler { _ in (200, "not json", [:]) }
        _ = try? await api.devices()
        let text = ErrorLogTests.file(dir)
        #expect(text.contains("[api] GET me/player/devices: transport(\"offline\")"))
        #expect(text.contains("[api] decoding(\"me/player/devices:"))
    }

    @Test func successIsNotRecorded() async {
        let (api, dir) = Self.api(StubTransport { _ in (200, #"{"devices":[]}"#, [:]) })
        _ = try? await api.devices()
        #expect(ErrorLogTests.file(dir).isEmpty)
    }
}

struct CrashReportsTests {
    static func dir(_ files: [String: String]) throws -> URL {
        let dir = ErrorLogTests.tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, body) in files { try body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        return dir
    }

    @Test func findsOnlyGreedifyAndLibrespotReportsSince() throws {
        let dir = try Self.dir([
            "Greedify-2026-10-01-120000.ips": "{}",
            "librespot-2026-10-01-120000.ips": "{}",
            "Greedify_2026-10-01-120000_host.cpu_resource.diag": "x",
            "GreedifyOther-2026-10-01-120000.ips": "{}",
            "firefox_2026-10-01-120000_host.diag": "x",
            "Greedify-2026-09-01-120000.ips": "{}",
        ])
        let old = dir.appendingPathComponent("Greedify-2026-09-01-120000.ips")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: old.path)
        let found = CrashReports.find(in: [dir, dir.appendingPathComponent("missing")], since: Date(timeIntervalSinceNow: -3600))
        #expect(Set(found.map(\.lastPathComponent)) == [
            "Greedify-2026-10-01-120000.ips", "librespot-2026-10-01-120000.ips",
            "Greedify_2026-10-01-120000_host.cpu_resource.diag",
        ])
    }

    @Test func summarisesACrashReport() throws {
        let header = #"{"app_name":"Greedify","bug_type":"309","timestamp":"2026-10-01 12:00:00.00 +0300"}"#
        let body = #"""
        {"procName":"Greedify","exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
         "termination":{"indicator":"Trace/BPT trap: 5"},
         "asi":{"libswiftCore.dylib":["Greedify/PlayerStore.swift:12: Fatal error: boom"]}}
        """#
        let dir = try Self.dir(["Greedify-2026-10-01-120000.ips": header + "\n" + body])
        let summary = CrashReports.summary(of: dir.appendingPathComponent("Greedify-2026-10-01-120000.ips"))
        #expect(summary == "Greedify-2026-10-01-120000.ips: EXC_BREAKPOINT (SIGTRAP), Trace/BPT trap: 5, Greedify/PlayerStore.swift:12: Fatal error: boom")
    }

    @Test func summaryOfAnUnreadableReportIsItsName() throws {
        let dir = try Self.dir(["Greedify_2026-10-01_host.diag": "Date/Time: …"])
        #expect(CrashReports.summary(of: dir.appendingPathComponent("Greedify_2026-10-01_host.diag")) == "Greedify_2026-10-01_host.diag")
    }
}
