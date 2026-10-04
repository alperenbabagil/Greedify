import Foundation

/// Advances the playback position locally between polls.
public struct PlaybackClock: Equatable, Sendable {
    public private(set) var anchorMs: Int
    public private(set) var anchorDate: Date
    public private(set) var isPlaying: Bool
    public private(set) var durationMs: Int

    public init(progressMs: Int = 0, durationMs: Int = 0, isPlaying: Bool = false, at date: Date = Date()) {
        anchorMs = progressMs; anchorDate = date; self.isPlaying = isPlaying; self.durationMs = durationMs
    }

    /// Re-anchors to a fresh server reading.
    public mutating func sync(progressMs: Int, durationMs: Int, isPlaying: Bool, at date: Date) {
        anchorMs = progressMs; anchorDate = date; self.isPlaying = isPlaying; self.durationMs = durationMs
    }

    public mutating func setPlaying(_ playing: Bool, at date: Date) {
        anchorMs = positionMs(at: date); anchorDate = date; isPlaying = playing
    }

    public mutating func seek(toMs ms: Int, at date: Date) {
        anchorMs = max(0, min(ms, durationMs)); anchorDate = date
    }

    public func positionMs(at date: Date) -> Int {
        guard isPlaying else { return anchorMs }
        let elapsed = Int(date.timeIntervalSince(anchorDate) * 1000)
        return max(0, min(anchorMs + elapsed, durationMs))
    }
}
