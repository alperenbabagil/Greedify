import GreedifyKit
import SwiftUI

extension View {
    /// The skin's panel frame around the view, as Winamp draws round its playlist and library windows: a striped
    /// title strip with the panel's name, then the frame's face and bevel round the sides and bottom (winamp window
    /// spec). Without a frame in the recipe the view is left as it is.
    ///
    /// It's padding plus backgrounds, so it never changes a column's minimum (the content still sizes from the
    /// proposal), and nothing it draws takes clicks.
    ///
    /// `titleBar` draws the band under the window's toolbar as Winamp's title bar: the title strip's stripes, with a
    /// name in the middle when it has one, kept clear of the toolbar's buttons on the leading side.
    func winampFrame(_ name: String, titleBar: TitleBarBand? = nil) -> some View {
        modifier(WinampFrameModifier(name: name, titleBar: titleBar))
    }
}

/// What a frame draws under the toolbar: a name (the window's title, which a framed skin hides) and the room the
/// toolbar's own items need on the leading side (traffic lights, the sidebar button).
struct TitleBarBand: Equatable {
    var label: String? = nil
    var leading: CGFloat = 0
}

private struct WinampFrameModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let name: String
    let titleBar: TitleBarBand?
    /// The toolbar's height above this column: where the content starts, in the window.
    @State private var toolbarHeight: CGFloat = 0

    func body(content: Content) -> some View {
        if let frame = theme.style?.frame {
            let edge = CGFloat(frame.thickness ?? 3)
            let strip = CGFloat(frame.title?.height ?? 14)
            let radius = CGFloat(frame.radius ?? 0)
            content
                // Set into the frame like a screen: rounded corners and a dark line round it (Classified).
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay {
                    if let outline = frame.outline {
                        RoundedRectangle(cornerRadius: radius).strokeBorder(Color(outline), lineWidth: 1).allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, edge).padding(.bottom, edge).padding(.top, strip)
                .background { WinampFrameChrome(frame: frame, title: title(frame), edge: edge, strip: strip) }
                // Under the toolbar: the skin's header material (the window title is drawn there in light text), else
                // the face, so the frame reads as one piece with the title bar.
                // Only the band reads it, never the content's size: no feedback.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY.rounded() } action: { toolbarHeight = $0 }
                .background {
                    // The band only, never the whole column: a gradient stretched over the column showed just its top.
                    ZStack(alignment: .top) {
                        // Only under a toolbar (the window's columns); the popover's frames have none.
                        if titleBar != nil, let fill = theme.style?.materials[.header] ?? frame.face { MaterialFill(material: fill) }
                        if let titleBar {
                            TitleBarStripes(frame: frame, band: titleBar, label: titleBar.label.map { $0.uppercased() })
                        }
                    }
                    .frame(height: max(toolbarHeight, 0))
                    .frame(maxHeight: .infinity, alignment: .top)
                    // Up only: sideways, the page column's safe area reaches under the sidebar, and the band's
                    // leading room was measured from there.
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }
        } else {
            content
        }
    }


    private func title(_ frame: Style.FrameSpec) -> String {
        // No name: just the prefix ("WINAMP"), like the original's main window.
        [frame.title?.prefix, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").uppercased()
    }
}

/// The frame's drawing: the face round the content, the outer bevel, the title strip and the sunken edge round
/// the content. Strips and edges only, never a panel-sized drawing: a `Canvas` bevel (or a face) as big as the
/// panel got a full-size backing buffer each, +27 MB for the three panels.
private struct WinampFrameChrome: View {
    @Environment(\.theme) private var theme
    let frame: Style.FrameSpec
    let title: String
    let edge: CGFloat
    let strip: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            // Wider by the corner radius, so the face shows in the content's rounded corners.
            if let face = frame.face { FrameFace(material: face, edge: edge + CGFloat(frame.radius ?? 0), top: strip + CGFloat(frame.radius ?? 0)) }
            if let bevel = frame.bevel { EdgeBevel(light: Color(bevel.light), dark: Color(bevel.dark), width: CGFloat(bevel.width)) }
            titleStrip
                .frame(height: strip)
                .padding(.horizontal, edge + 2)
            if let bevel = frame.bevel, frame.radius == nil {
                // The content sits in a groove: the same colours, sunken, one point outside it.
                EdgeBevel(light: Color(bevel.dark), dark: Color(bevel.light), width: 1)
                    .padding(.horizontal, edge - 1).padding(.bottom, edge - 1).padding(.top, strip - 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Stripes either side of the name, on the strip's own band (Classified's steel) or the frame's face.
    private var titleStrip: some View {
        HStack(spacing: 6) {
            TitleStripe(title: frame.title, band: strip)
            TitleLabel(text: title, title: frame.title, scale: 1, ink: Color(frame.title?.text ?? .white))
            TitleStripe(title: frame.title, band: strip)
        }
        .padding(.horizontal, 2)
        .background { if let background = frame.title?.background { MaterialFill(material: background).padding(.horizontal, -2) } }
    }
}

/// One stripe band of a title strip: the recipe's stripes filling the band, or one groove `stripeHeight` tall
/// (round-ended when `rounded`).
struct TitleStripe: View {
    let title: Style.TitleStripSpec?
    let band: CGFloat

    var body: some View {
        let height = title?.stripeHeight.map { CGFloat($0) } ?? max(4, band - 6)
        Group {
            if let material = title?.material {
                if title?.rounded == true { MaterialFill(material: material).clipShape(Capsule()) } else { MaterialFill(material: material) }
            } else {
                Color.clear
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

/// A title strip's name: the recipe's lettering (Classified's heavy silver type), else the skin's pixel font.
/// `scale` grows it for the toolbar's taller band.
struct TitleLabel: View {
    @Environment(\.theme) private var theme
    let text: String
    let title: Style.TitleStripSpec?
    let scale: CGFloat
    let ink: Color

    var body: some View {
        if let choice = title?.font {
            let size = CGFloat(title?.size ?? 10) * scale
            let weight = RecipeButtonStyle.weight(title?.weight)
            Group {
                if case .family(let name) = choice { Text(text).font(.custom(name, fixedSize: size).weight(weight)) }
                else { Text(text).font(.system(size: size, weight: weight)) }
            }
            .kerning(scale)
            .foregroundStyle(ink)
            .fixedSize()
        } else if let font = theme.pixelFont {
            PixelText(text: text, font: font, scale: 1.5 * scale, ink: ink, fixedWidth: true).fixedSize()
        } else {
            Text(text).font(.system(size: 9 * scale, weight: .bold)).kerning(scale).foregroundStyle(ink).fixedSize()
        }
    }
}

/// The face on the frame's four sides only (the content covers the middle).
private struct FrameFace: View {
    let material: Style.Material
    let edge: CGFloat
    let top: CGFloat

    var body: some View {
        ZStack {
            VStack(spacing: 0) { MaterialFill(material: material).frame(height: top); Spacer(minLength: 0) }
            VStack(spacing: 0) { Spacer(minLength: 0); MaterialFill(material: material).frame(height: edge) }
            HStack(spacing: 0) { MaterialFill(material: material).frame(width: edge); Spacer(minLength: 0) }
            HStack(spacing: 0) { Spacer(minLength: 0); MaterialFill(material: material).frame(width: edge) }
        }
    }
}

/// A raised edge as four plain colour strips (light top and left, dark bottom and right): layers with a background
/// colour, no backing buffer, unlike `BevelEdges`' canvas.
struct EdgeBevel: View {
    let light: Color
    let dark: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            VStack(spacing: 0) { light.frame(height: width); Spacer(minLength: 0); dark.frame(height: width) }
            HStack(spacing: 0) { light.frame(width: width); Spacer(minLength: 0); dark.frame(width: width) }
        }
        .allowsHitTesting(false)
    }
}

/// Winamp's title bar in the toolbar's band: stripes either side of the name, or stripes alone.
private struct TitleBarStripes: View {
    @Environment(\.theme) private var theme
    let frame: Style.FrameSpec
    let band: TitleBarBand
    let label: String?

    var body: some View {
        HStack(spacing: 8) {
            TitleStripe(title: frame.title, band: 15)
            if let label {
                let band = (theme.style?.materials[.header] ?? frame.face).map(Self.average)
                TitleLabel(text: label, title: frame.title, scale: 4 / 3, ink: Color(Self.ink(frame.title?.text, on: band)))
                TitleStripe(title: frame.title, band: 15)
            }
        }
        .padding(.leading, band.leading).padding(.trailing, 12)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    /// The title strip's text colour when it reads on the band (made for the frame's face, it may not: Classified's
    /// navy on its dark-blue band), else white or black, whichever reads better.
    static func ink(_ text: ThemeColor?, on band: ThemeColor?) -> ThemeColor {
        guard let band else { return text ?? .white }
        if let text, text.contrast(with: band) >= 3 { return text }
        return band.contrast(with: .white) >= band.contrast(with: .black) ? .white : .black
    }

    /// A material's overall colour: a gradient's stops averaged (the steel band starts light but is mostly dark).
    static func average(_ material: Style.Material) -> ThemeColor {
        let colors: [ThemeColor] = switch material {
        case .gradient(_, let stops), .radial(_, _, _, let stops): stops.map(\.color)
        case .layers(let layers): layers.map(average)
        default: [material.base]
        }
        guard !colors.isEmpty else { return material.base }
        let n = Double(colors.count)
        return ThemeColor(r: colors.map(\.r).reduce(0, +) / n, g: colors.map(\.g).reduce(0, +) / n,
                          b: colors.map(\.b).reduce(0, +) / n, a: 1)
    }
}
