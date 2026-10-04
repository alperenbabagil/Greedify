import Foundation

/// A still spectrum for a skin's analyser (winamp window spec). Greedify can't hear librespot's audio, and a moving
/// fake would redraw every frame, so each song gets its own fixed shape: worked out from its id, tallest in the low
/// bands and falling off toward the high ones, like a real spectrum.
public enum Analyser {
    public static func bars(seed: String, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        // FNV-1a over the id, then a xorshift stream: stable across launches (Swift's hashValue isn't).
        var state: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 { state = (state ^ UInt64(byte)) &* 0x100_0000_01b3 }
        if state == 0 { state = 1 }
        func next() -> Double {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Double(state >> 11) / Double(1 << 53)
        }
        var out: [Double] = []
        var previous = 0.6 + next() * 0.4
        for i in 0..<count {
            let band = Double(i) / Double(max(1, count - 1))
            let envelope = 0.95 - band * 0.55 // the falloff toward the highs
            // Neighbouring bands follow each other a little, so the shape reads as a spectrum, not noise.
            let raw = envelope * (0.35 + next() * 0.65)
            let value = previous * 0.35 + raw * 0.65
            previous = value
            out.append(min(max(value, 0.05), 1))
        }
        return out
    }
}
