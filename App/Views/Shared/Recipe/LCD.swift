import GreedifyKit
import SwiftUI

/// A recipe LCD: the display's material inside a sunken bevel (curated skins spec §2.3).
struct LCDPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        let lcd = theme.style?.lcd
        content
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxHeight: .infinity)
            .recipeSurface(lcd?.material ?? .solid(.black), bevel: lcd?.bevel, radius: CGFloat(lcd?.radius ?? 0))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(lcd?.radius ?? 0)))
    }
}

/// Time digits in the recipe's LCD style: native 7-segment shapes, the skin's pixel letterforms, or a mono font.
struct LCDDigits: View {
    @Environment(\.theme) private var theme
    let text: String
    var height: CGFloat = 22

    var body: some View {
        let lcd = theme.style?.lcd
        let ink = Color(lcd?.text ?? .white)
        let glow = CGFloat(lcd?.glow ?? 0)
        Group {
            switch lcd?.digits ?? .mono {
            case .segment:
                SegmentDigits(text: text, height: height, halo: glow).foregroundStyle(ink)
            case .pixel where theme.pixelFont != nil:
                // 3× at the bar's size: 4× read as heavy blocks.
                PixelText(text: text, font: theme.pixelFont!, scale: max(1, (height / CGFloat(PixelFont.cellHeight) * 0.75).rounded(.down)), ink: ink, halo: glow)
            default:
                Text(text).font(.system(size: height * 0.9, weight: .semibold, design: .monospaced)).foregroundStyle(ink)
            }
        }
        .accessibilityLabel(text)
    }
}

/// Seven-segment digits drawn as paths (0–9, `:` and `-`), filled with the foreground style.
struct SegmentDigits: View {
    let text: String
    var height: CGFloat = 22
    /// A soft glow drawn in the same pass (a stroked copy of the segments), never a blur.
    var halo: CGFloat = 0

    /// Segments a (top), b (top right), c (bottom right), d (bottom), e (bottom left), f (top left), g (middle).
    static let segments: [Character: Set<Character>] = [
        "0": ["a", "b", "c", "d", "e", "f"], "1": ["b", "c"], "2": ["a", "b", "g", "e", "d"], "3": ["a", "b", "g", "c", "d"],
        "4": ["f", "g", "b", "c"], "5": ["a", "f", "g", "c", "d"], "6": ["a", "f", "g", "e", "c", "d"], "7": ["a", "b", "c"],
        "8": ["a", "b", "c", "d", "e", "f", "g"], "9": ["a", "b", "c", "d", "f", "g"], "-": ["g"],
    ]

    var body: some View {
        let digitWidth = height * 0.55, gap = height * 0.14
        Canvas { context, _ in
            var x: CGFloat = 0
            for ch in text {
                if ch == ":" {
                    let dot = height * 0.12
                    context.fill(Path(CGRect(x: x + gap * 0.3, y: height * 0.28, width: dot, height: dot)), with: .foreground)
                    context.fill(Path(CGRect(x: x + gap * 0.3, y: height * 0.64, width: dot, height: dot)), with: .foreground)
                    x += dot + gap
                } else {
                    let path = Self.path(Self.segments[ch] ?? [], x: x, width: digitWidth, height: height)
                    if halo > 0 {
                        var glow = context
                        glow.opacity = 0.3
                        glow.stroke(path, with: .foreground, lineWidth: halo)
                    }
                    context.fill(path, with: .foreground)
                    x += digitWidth + gap
                }
            }
        }
        .frame(width: Self.width(text, height: height), height: height)
    }

    static func width(_ text: String, height: CGFloat) -> CGFloat {
        let digitWidth = height * 0.55, gap = height * 0.14, dot = height * 0.12
        return text.reduce(0) { $0 + ($1 == ":" ? dot + gap : digitWidth + gap) }
    }

    static func path(_ on: Set<Character>, x: CGFloat, width w: CGFloat, height h: CGFloat) -> Path {
        let t = h * 0.12, half = h / 2
        var p = Path()
        func bar(_ r: CGRect) { p.addRoundedRect(in: r, cornerSize: CGSize(width: t / 3, height: t / 3)) }
        if on.contains("a") { bar(CGRect(x: x + t * 0.6, y: 0, width: w - t * 1.2, height: t)) }
        if on.contains("g") { bar(CGRect(x: x + t * 0.6, y: half - t / 2, width: w - t * 1.2, height: t)) }
        if on.contains("d") { bar(CGRect(x: x + t * 0.6, y: h - t, width: w - t * 1.2, height: t)) }
        if on.contains("f") { bar(CGRect(x: x, y: t * 0.6, width: t, height: half - t * 1.1)) }
        if on.contains("b") { bar(CGRect(x: x + w - t, y: t * 0.6, width: t, height: half - t * 1.1)) }
        if on.contains("e") { bar(CGRect(x: x, y: half + t * 0.5, width: t, height: half - t * 1.1)) }
        if on.contains("c") { bar(CGRect(x: x + w - t, y: half + t * 0.5, width: t, height: half - t * 1.1)) }
        return p
    }
}

/// The now-playing title in the recipe's title style, scrolling like Winamp's when it's wider than its strip.
struct LCDTitle: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        let spec = theme.style?.text[.title]
        let ink = Color(spec?.color ?? theme.style?.lcd?.text ?? .white)
        Marquee {
            Group {
                if spec?.font == .pixel, let font = theme.pixelFont {
                    PixelText(text: text, font: font, ink: ink, halo: CGFloat(spec?.glow ?? 0), fixedWidth: true).fixedSize()
                } else {
                    Text(text).font(Self.font(spec, theme: theme)).foregroundStyle(ink).fixedSize()
                }
            }
        }
        .accessibilityLabel(text)
    }

    static func font(_ spec: Style.TextSpec?, theme: ResolvedTheme) -> Font {
        let size = CGFloat(spec?.size ?? 13)
        let weight = RecipeButtonStyle.weight(spec?.weight)
        if case .family(let name)? = spec?.font { return Font.custom(name, fixedSize: size).weight(weight) }
        return theme.font(size, weight: weight)
    }
}

/// Scrolls its content left in a loop when it doesn't fit, pausing at the start; still otherwise.
/// The content is drawn once and only its offset moves: re-evaluating it every frame (a 24 fps `TimelineView`)
/// redrew the skin's pixel text on the CPU each frame and kept the main thread busy enough to drop clicks.
/// It steps like Winamp's title, a few points eight times a second, never animated: a 60 fps offset animation
/// still cost ~10% CPU on the main thread while it ran, and starting one briefly took ~50 MB.
struct Marquee<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var contentWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    static var step: CGFloat { 4 } // points per tick
    static var tick: Duration { .milliseconds(125) } // 8 ticks a second: 32 pt/s
    static var pause: Duration { .seconds(2) }
    private let gap: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let overflow = contentWidth > geo.size.width
            HStack(spacing: gap) {
                content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                if overflow { content }
            }
            .offset(x: overflow ? -offset : 0)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            // A new title (or strip width) restarts the loop from the start.
            .task(id: overflow ? contentWidth : -1) { await scroll(overflow: overflow) }
        }
        .clipped()
    }

    /// Pause, step one copy's width left, jump back (the second copy is then where the first was), repeat.
    private func scroll(overflow: Bool) async {
        offset = 0
        guard overflow else { return }
        let span = contentWidth + gap
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pause)
            while offset < span {
                try? await Task.sleep(for: Self.tick)
                if Task.isCancelled { return }
                offset = min(span, offset + Self.step)
            }
            offset = 0
        }
    }
}
