import Foundation
import os
import Synchronization

/// Errors worth keeping. Each goes to the unified log and, once `open(directory:)` has run, to
/// `~/Library/Logs/Greedify/errors.log`, which outlives the unified log's few days and is copied from
/// Settings → Diagnostics. The file rotates at `maxBytes` (one previous file kept). A message repeated
/// within `repeatWindow` of its last occurrence is counted instead of written, so a failing poll can't fill it.
public final class ErrorLog: Sendable {
    /// The app's log. Only the unified log until the app opens it; tests never do.
    public static let shared = ErrorLog()
    public static let fileName = "errors.log"
    public static let previousFileName = "errors.1.log"
    public static let repeatWindow: TimeInterval = 300

    struct Repeat { let key: String; let category: String; var last: Date; var count = 0 }
    struct State {
        var directory: URL?
        var streak: Repeat?
        let formatter: DateFormatter
    }

    private let state: Mutex<State>
    let maxBytes: Int
    let now: @Sendable () -> Date

    public init(maxBytes: Int = 512 * 1024, now: @escaping @Sendable () -> Date = Date.init) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        state = Mutex(State(formatter: formatter))
        self.maxBytes = maxBytes
        self.now = now
    }

    /// Starts writing to `directory/errors.log`.
    public func open(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        state.withLock { $0.directory = directory }
    }

    public var fileURL: URL? { state.withLock { $0.directory?.appendingPathComponent(Self.fileName) } }

    public func record(_ message: String, category: String = "app") {
        Logger(subsystem: "com.alperen.greedify", category: category).error("\(message, privacy: .public)")
        let message = Self.oneLine(message)
        let t = now()
        state.withLock { s in
            guard let dir = s.directory else { return }
            let key = category + "\u{0}" + message
            if var streak = s.streak, streak.key == key, t.timeIntervalSince(streak.last) < Self.repeatWindow {
                streak.count += 1
                streak.last = t
                s.streak = streak
                return
            }
            flushRepeats(&s, dir)
            append("\(s.formatter.string(from: t)) [\(category)] \(message)", dir)
            s.streak = Repeat(key: key, category: category, last: t)
        }
    }

    /// A marker that isn't an error (e.g. a launch), so the errors around it can be placed.
    public func note(_ text: String) {
        let t = now()
        state.withLock { s in
            guard let dir = s.directory else { return }
            flushRepeats(&s, dir)
            s.streak = nil
            append("\(s.formatter.string(from: t)) ── \(Self.oneLine(text)) ──", dir)
        }
    }

    /// The last `maxLines` lines, oldest first, across the previous and current file, plus any uncounted repeats.
    public func recentText(maxLines: Int = 300) -> String {
        state.withLock { s in
            guard let dir = s.directory else { return "" }
            let read = { (name: String) in (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? "" }
            var lines = (read(Self.previousFileName) + read(Self.fileName)).split(separator: "\n").map(String.init)
            if let pending = repeatLine(s) { lines.append(pending) }
            return lines.suffix(maxLines).joined(separator: "\n")
        }
    }

    // MARK: Private (called with the lock held)

    private func repeatLine(_ s: State) -> String? {
        guard let streak = s.streak, streak.count > 0 else { return nil }
        let times = streak.count == 1 ? "time" : "times"
        return "\(s.formatter.string(from: streak.last)) [\(streak.category)] ↳ repeated \(streak.count) more \(times)"
    }

    private func flushRepeats(_ s: inout State, _ dir: URL) {
        if let line = repeatLine(s) { append(line, dir) }
        s.streak = nil
    }

    private func append(_ line: String, _ dir: URL) {
        let data = Data((line + "\n").utf8)
        let fm = FileManager.default
        let file = dir.appendingPathComponent(Self.fileName)
        let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if size > 0, size + data.count > maxBytes {
            let previous = dir.appendingPathComponent(Self.previousFileName)
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: file, to: previous)
        }
        guard let handle = try? FileHandle(forWritingTo: file) else {
            fm.createFile(atPath: file.path, contents: data)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    static func oneLine(_ text: String) -> String {
        String(text.replacingOccurrences(of: "\r\n", with: " ⏎ ").replacingOccurrences(of: "\n", with: " ⏎ ").prefix(2000))
    }
}

/// macOS crash and resource reports (`.ips`, `.diag`) for Greedify and its librespot.
public enum CrashReports {
    /// Per-user reports, and the system folder where recent macOS versions write them.
    public static var directories: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"),
         URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")]
    }

    /// Reports modified after `since`, oldest first.
    public static func find(in directories: [URL] = directories, since: Date,
                            processes: [String] = ["Greedify", "librespot"]) -> [URL] {
        let fm = FileManager.default
        let found = directories.flatMap { dir -> [(URL, Date)] in
            let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return urls.compactMap { url in
                let name = url.lastPathComponent
                guard processes.contains(where: { name.hasPrefix($0 + "-") || name.hasPrefix($0 + "_") }),
                      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date > since else { return nil }
                return (url, date)
            }
        }
        return found.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// One line: the file name, then the exception, termination reason and the app-specific message
    /// (e.g. a Swift fatal error) when the report is an `.ips` with a JSON body.
    public static func summary(of url: URL) -> String {
        let name = url.lastPathComponent
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let newline = text.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any]
        else { return name }
        var parts: [String] = []
        if let exception = body["exception"] as? [String: Any], let type = exception["type"] as? String {
            parts.append((exception["signal"] as? String).map { "\(type) (\($0))" } ?? type)
        }
        if let indicator = (body["termination"] as? [String: Any])?["indicator"] as? String { parts.append(indicator) }
        if let asi = body["asi"] as? [String: [String]] { parts += asi.keys.sorted().flatMap { asi[$0] ?? [] } }
        return parts.isEmpty ? name : "\(name): " + parts.joined(separator: ", ")
    }
}
