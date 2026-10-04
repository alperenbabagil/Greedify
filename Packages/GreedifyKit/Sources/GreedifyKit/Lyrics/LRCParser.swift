import Foundation

public struct LyricLine: Equatable, Sendable, Identifiable {
    public let timeMs: Int
    public let text: String
    public var id: Int { timeMs }
    public init(timeMs: Int, text: String) { self.timeMs = timeMs; self.text = text }
    /// Empty lines in LRC mark instrumental gaps.
    public var isGap: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

public enum Lyrics: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case none
}

public enum LRCParser {
    /// Parses `[mm:ss.xx] text` lines. A line may carry several timestamps. Metadata tags are ignored.
    public static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Int] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let ms = timestamp(tag) { times.append(ms) }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { LyricLine(timeMs: $0, text: text) }
        }
        return lines.sorted { $0.timeMs < $1.timeMs }
    }

    static func timestamp(_ tag: Substring) -> Int? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let min = Int(parts[0]), let sec = Double(parts[1]) else { return nil }
        return min * 60_000 + Int((sec * 1000).rounded())
    }

    /// Index of the line being sung at `positionMs`, or nil before the first line.
    public static func currentIndex(in lines: [LyricLine], at positionMs: Int) -> Int? {
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].timeMs <= positionMs { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    /// Time of the next line after `positionMs`, for scheduling the next label update.
    public static func nextChangeMs(in lines: [LyricLine], after positionMs: Int) -> Int? {
        lines.first { $0.timeMs > positionMs }?.timeMs
    }
}
