import GreedifyKit
import SwiftUI

// MARK: Text

extension View {
    func themed(_ role: TextRole) -> some View { modifier(ThemedText(role: role)) }
    func themedFont(_ style: ThemeFontStyle) -> some View { modifier(ThemedFont(style: style)) }
    func themedSurface(_ kind: SurfaceKind) -> some View { modifier(ThemedSurface(kind: kind)) }
    func themedButton(_ role: ThemedButtonRole, capsule: Bool = true) -> some View { modifier(ThemedButton(role: role, capsule: capsule)) }
    /// Hover and selection highlight for sidebar and track rows.
    func themedRow(selected: Bool, hovering: Bool) -> some View { modifier(ThemedRow(selected: selected, hovering: hovering)) }
}

private struct ThemedText: ViewModifier {
    @Environment(\.theme) private var theme
    let role: TextRole
    func body(content: Content) -> some View { content.foregroundStyle(theme.color(role)) }
}

private struct ThemedFont: ViewModifier {
    @Environment(\.theme) private var theme
    let style: ThemeFontStyle
    func body(content: Content) -> some View { content.font(theme.font(style)) }
}

// MARK: Surfaces

/// `inset` is a region that already sits on a sidebar or bar fill: over a backdrop it adds no second tint.
enum SurfaceKind { case content, surface, raised, bar, inset }

/// Background, default text color, tint and font for a region. On System only `.surface` changes anything (`.bar`).
private struct ThemedSurface: ViewModifier {
    @Environment(\.theme) private var theme
    let kind: SurfaceKind

    func body(content: Content) -> some View {
        if theme.isSystem {
            if kind == .surface || kind == .bar || kind == .inset { content.background(.bar) } else { content }
        } else {
            content
                .background { fill.ignoresSafeArea() }
                .foregroundStyle(theme.text)
                .tint(theme.accent)
                .font(theme.font(.body))
        }
    }

    /// A curated skin's material for the region (curated skins spec §3), else the theme's flat colour.
    @ViewBuilder private var fill: some View {
        if let material = recipeMaterial { MaterialFill(material: material) } else { flat }
    }

    private var recipeMaterial: Style.Material? {
        guard let style = theme.style else { return nil }
        switch kind {
        case .content: return style.materials[.window]
        case .surface: return style.materials[.sidebar]
        case .raised: return style.materials[.popover]
        case .bar: return style.materials[.bar]
        case .inset: return nil
        }
    }

    private var flat: Color {
        switch kind {
        case .content: theme.background
        case .surface, .bar: theme.surface
        case .inset: .clear
        case .raised: theme.raised
        }
    }
}

struct ThemedDivider: View {
    @Environment(\.theme) private var theme
    /// A vertical line, for an edge drawn outside a stack (a `Divider` there is always horizontal).
    var vertical = false
    var body: some View {
        if vertical {
            Rectangle().fill(theme.isSystem ? Color(nsColor: .separatorColor) : theme.divider).frame(width: max(1, theme.borderWidth))
        } else if theme.isSystem { Divider() }
        else { Rectangle().fill(theme.divider).frame(height: max(1, theme.borderWidth)) }
    }
}

// MARK: Rows

private struct ThemedRow: ViewModifier {
    @Environment(\.theme) private var theme
    let selected: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        content.background {
            let rows = theme.style?.rows
            if let fill = selected ? rows?.selected?.fill : hovering ? rows?.hover?.fill : nil {
                MaterialFill(material: fill).clipShape(RoundedRectangle(cornerRadius: theme.rowRadius))
            } else {
                RoundedRectangle(cornerRadius: theme.rowRadius)
                    .fill(selected ? theme.selection : hovering ? theme.text.opacity(0.05) : .clear)
            }
        }
    }
}

// MARK: Buttons

enum ThemedButtonRole { case primary, secondary }

/// System keeps the native capsule buttons; every other theme draws its own `buttonStyle`.
private struct ThemedButton: ViewModifier {
    @Environment(\.theme) private var theme
    let role: ThemedButtonRole
    let capsule: Bool

    func body(content: Content) -> some View {
        if theme.isSystem {
            if role == .primary {
                if capsule { content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) } else { content.buttonStyle(.borderedProminent) }
            } else {
                if capsule { content.buttonStyle(.bordered).buttonBorderShape(.capsule) } else { content.buttonStyle(.bordered) }
            }
        } else if theme.isStripHeader, let spec = theme.style?.button {
            // A Winamp window's buttons are the skin's grey bevel buttons, labels included (winamp window spec).
            content.buttonStyle(RecipeLabelButtonStyle(spec: spec, fallbackGlyph: theme.text))
        } else {
            content.buttonStyle(ThemedButtonStyle(role: role, theme: theme))
        }
    }
}

struct ThemedButtonStyle: ButtonStyle {
    let role: ThemedButtonRole
    let theme: ResolvedTheme

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: theme.buttonRadius)
        let primary = role == .primary
        configuration.label
            .font(theme.font(13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, theme.density == .compact ? 4 : 6)
            .foregroundStyle(foreground(primary))
            .background { shape.fill(fill(primary, pressed: pressed)) }
            .overlay {
                switch theme.buttonStyle {
                case .outlined: shape.strokeBorder(primary ? theme.accent : theme.divider, lineWidth: max(1, theme.borderWidth))
                case .bevel: BevelEdges(pressed: pressed, width: max(1, theme.borderWidth))
                case .flat, .filled: EmptyView()
                }
            }
            .offset(x: theme.buttonStyle == .bevel && pressed ? 1 : 0, y: theme.buttonStyle == .bevel && pressed ? 1 : 0)
            .opacity(theme.buttonStyle == .flat && pressed ? 0.6 : 1)
            .contentShape(shape)
    }

    private func foreground(_ primary: Bool) -> Color {
        switch theme.buttonStyle {
        case .flat, .outlined: primary ? theme.accent : theme.text
        case .filled, .bevel: primary ? theme.onAccent : theme.text
        }
    }

    private func fill(_ primary: Bool, pressed: Bool) -> Color {
        switch theme.buttonStyle {
        case .flat: .clear
        case .outlined: pressed ? theme.selection : .clear
        case .filled, .bevel: (primary ? theme.accent : theme.raised).opacity(pressed && theme.buttonStyle == .filled ? 0.8 : 1)
        }
    }
}

/// Winamp-style 3D edge: light top-left, dark bottom-right, swapped while pressed. Four plain colour strips (layers
/// with a background colour, no backing buffer): as a `Canvas`, every LCD, slider, scroller and button edge had a
/// buffer of its own (+3.5 MB on a skin). Dark is drawn last, so it takes the top-right and bottom-left corners.
struct BevelEdges: View {
    let pressed: Bool
    let width: CGFloat
    var light: Color = .white.opacity(0.55)
    var dark: Color = .black.opacity(0.55)

    var body: some View {
        let top = pressed ? dark : light, bottom = pressed ? light : dark
        ZStack {
            VStack(spacing: 0) { top.frame(height: width); Spacer(minLength: 0) }
            HStack(spacing: 0) { top.frame(width: width); Spacer(minLength: 0) }
            VStack(spacing: 0) { Spacer(minLength: 0); bottom.frame(height: width) }
            HStack(spacing: 0) { Spacer(minLength: 0); bottom.frame(width: width) }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Slider

enum SliderSkin { case plain, seek, volume }

/// A slider drawn from the theme; System keeps the native mini `Slider`. With skin controls, `.seek` draws the
/// skin's groove and handle and `.volume` its fill frames (skinned controls spec §5.4–§5.5).
struct ThemedSlider: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    var skin: SliderSkin = .plain
    /// VoiceOver's name for it, and its value as spoken (a percentage unless given).
    var label = ""
    var valueText: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false


    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
    }

    var body: some View {
        if theme.isSystem {
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged).controlSize(.mini)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(spokenValue))
        } else if let spec = recipeSpec {
            RecipeSlider(value: $value, range: range, spec: spec, onEditingChanged: onEditingChanged)
                .modifier(adjustable)
        } else {
            plain.modifier(adjustable)
        }
    }

    private var spokenValue: String { valueText ?? "\(Int((fraction * 100).rounded())) percent" }

    /// A drawn slider is one adjustable element for VoiceOver: each step moves 5% and commits, like the end of a drag.
    private var adjustable: AccessibleSlider {
        AccessibleSlider(label: label, value: spokenValue) { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: return
            }
            onEditingChanged(false)
        }
    }

    /// The recipe's seek or volume slider; volume falls back to the seek slider's look.
    private var recipeSpec: Style.SliderSpec? {
        switch skin {
        case .seek: theme.style?.slider
        case .volume: theme.style?.volume ?? theme.style?.slider
        case .plain: nil
        }
    }

    private var plain: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let knob: CGFloat = 10
            let x = CGFloat(fraction) * max(0, geo.size.width - knob)
            let bevel = theme.buttonStyle == .bevel
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: bevel ? 0 : 2).fill(theme.divider).frame(height: 4)
                RoundedRectangle(cornerRadius: bevel ? 0 : 2).fill(theme.accent).frame(width: x + knob / 2, height: 4)
                Group {
                    if bevel {
                        Rectangle().fill(theme.raised).overlay(BevelEdges(pressed: dragging, width: 1)).frame(width: knob, height: 12)
                    } else {
                        Circle().fill(theme.text).frame(width: knob, height: knob)
                    }
                }
                .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let f = min(max((drag.location.x - knob / 2) / max(1, geo.size.width - knob), 0), 1)
                        value = range.lowerBound + Double(f) * span
                    }
                    .onEnded { _ in dragging = false; onEditingChanged(false) }
            )
        }
        .frame(height: 14)
    }
}

private struct AccessibleSlider: ViewModifier {
    let label: String
    let value: String
    let adjust: (AccessibilityAdjustmentDirection) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement()
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value))
            .accessibilityAdjustableAction(adjust)
    }
}

// MARK: Containers

/// A raised tile. On System it adds nothing, so grids look as before.
struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        if theme.isSystem {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: theme.cardRadius)
            content
                .padding(8)
                .background(shape.fill(theme.raised))
                .overlay {
                    if theme.buttonStyle == .bevel { BevelEdges(pressed: false, width: max(1, theme.borderWidth)) }
                    else if theme.borderWidth > 0 { shape.strokeBorder(theme.divider, lineWidth: theme.borderWidth) }
                }
        }
    }
}

struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String

    var body: some View {
        if theme.isSystem {
            Text(title)
        } else {
            Text(theme.buttonStyle == .bevel ? title.uppercased() : title)
                .font(theme.font(11, weight: .semibold))
                .foregroundStyle(theme.style?.text[.header]?.color.map { Color($0) } ?? theme.textSecondary)
        }
    }
}

/// A line in the skin's pixel font, tinted with the theme's text color (theme images spec §6). Drawn once into a
/// small cached bitmap and shown as an image: as a `Canvas`, each one had its own backing buffer, and the scrolling
/// title's canvas made the GPU take ~50 MB for a moment every few seconds. Clipped at a glyph boundary; VoiceOver
/// reads the real text.
struct PixelText: View {
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.self) private var environment
    let text: String
    let font: PixelFont
    var scale: CGFloat = 2
    /// The glyphs' colour; the theme's text colour when nil.
    var ink: Color? = nil
    /// A soft glow drawn in the same pass (a wider, faint copy of each dot), never a blur: a blurred shadow on moving
    /// text costs an offscreen pass per frame.
    var halo: CGFloat = 0
    /// Exactly as wide as its text (inside a scroller, which needs a natural width); otherwise clipped at a glyph.
    var fixedWidth = false

    var body: some View {
        let count = PixelFont.glyphs(for: text).count
        let cellWidth = CGFloat(PixelFont.cellWidth) * scale
        let color = (ink ?? theme.text).resolve(in: environment)
        let image = PixelTextImages.shared.image(text: text, font: font, scale: scale, color: color, halo: halo, displayScale: displayScale)
        // Shows whole glyphs only: the width offered, rounded down to a cell.
        PixelTextLayout(cellWidth: cellWidth, count: count, fixedWidth: fixedWidth) {
            if let image { Image(decorative: image, scale: displayScale).interpolation(.none) }
        }
        .frame(height: CGFloat(PixelFont.cellHeight) * scale)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// As wide as its glyphs, or as many whole glyphs as the proposal holds; the image is placed at the leading edge.
private struct PixelTextLayout: Layout {
    let cellWidth: CGFloat
    let count: Int
    let fixedWidth: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let full = CGFloat(count) * cellWidth
        let height = proposal.height ?? 0
        guard !fixedWidth, let offered = proposal.width, offered < full else { return CGSize(width: full, height: height) }
        return CGSize(width: (offered / cellWidth).rounded(.down) * cellWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: .unspecified) }
    }
}

/// The pixel texts' bitmaps, drawn on first use. Small (a 30-character title at 2× is ~70 KB), and dropped wholesale
/// past 64, since a theme switch leaves old ones behind.
@MainActor
final class PixelTextImages {
    static let shared = PixelTextImages()
    private var images: [String: CGImage] = [:]

    func image(text: String, font: PixelFont, scale: CGFloat, color: Color.Resolved, halo: CGFloat, displayScale: CGFloat) -> CGImage? {
        let key = "\(ObjectIdentifier(font).hashValue)|\(text)|\(scale)|\(color.red),\(color.green),\(color.blue),\(color.opacity)|\(halo)|\(displayScale)"
        if let image = images[key] { return image }
        guard let image = Self.draw(text: text, font: font, scale: scale, color: color, halo: halo, displayScale: displayScale) else { return nil }
        if images.count > 64 { images.removeAll() }
        images[key] = image
        return image
    }

    private static func draw(text: String, font: PixelFont, scale: CGFloat, color: Color.Resolved, halo: CGFloat, displayScale: CGFloat) -> CGImage? {
        let glyphs = PixelFont.glyphs(for: text)
        let cellWidth = CGFloat(PixelFont.cellWidth) * scale
        let width = Int((CGFloat(glyphs.count) * cellWidth * displayScale).rounded(.up))
        let height = Int((CGFloat(PixelFont.cellHeight) * scale * displayScale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Top-left origin in points, like the canvas this replaced.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: displayScale, y: -displayScale)
        let ink = CGMutablePath()
        for (i, glyph) in glyphs.enumerated() {
            let mask = font.mask(row: glyph.row, column: glyph.column)
            for y in 0..<PixelFont.cellHeight {
                for x in 0..<PixelFont.cellWidth where mask[y * PixelFont.cellWidth + x] {
                    ink.addRect(CGRect(x: CGFloat(i) * cellWidth + CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale))
                }
            }
        }
        let cg = CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.opacity))
        if halo > 0 {
            context.saveGState()
            context.setAlpha(0.3)
            context.setFillColor(cg); context.addPath(ink); context.fillPath()
            context.setStrokeColor(cg); context.setLineWidth(halo); context.addPath(ink); context.strokePath()
            context.restoreGState()
        }
        context.setFillColor(cg)
        context.addPath(ink)
        context.fillPath()
        return context.makeImage()
    }
}
