import GreedifyKit
import SwiftUI

/// Button sizes in points; the popover uses the large ones.
enum SkinControlSize {
    case play, button, small, largePlay, largeButton

    var size: CGSize {
        switch self {
        case .play: CGSize(width: 40, height: 28)
        case .button: CGSize(width: 30, height: 24)
        case .small: CGSize(width: 26, height: 22)
        case .largePlay: CGSize(width: 52, height: 38)
        case .largeButton: CGSize(width: 38, height: 30)
        }
    }

    var glyphSize: CGFloat {
        switch self {
        case .play: 13
        case .button: 11
        case .small: 10
        case .largePlay: 17
        case .largeButton: 14
        }
    }
}

/// A button drawn from the recipe (curated skins spec §2.1): shape, face material, bevel, glyph colours, with
/// pressed and active variants; dimmed when disabled.
struct RecipeButtonStyle: ButtonStyle {
    let spec: Style.ButtonSpec
    let size: SkinControlSize
    let active: Bool
    let fallbackGlyph: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let face = (pressed ? spec.pressed?.face : nil) ?? spec.face
        let normal = (pressed ? spec.pressed?.glyph : nil) ?? spec.glyph
        let glyph = (active ? spec.active : nil) ?? normal
        configuration.label
            .font(.system(size: size.glyphSize, weight: Self.weight(spec.glyphWeight)))
            .foregroundStyle(glyph.map { Color($0) } ?? fallbackGlyph)
            .frame(width: (Self.diameter(spec, size) ?? size.size).width, height: (Self.diameter(spec, size) ?? size.size).height)
            .background { RecipeShape(spec: spec).fill(Color.clear).background { if let face { MaterialFill(material: face) } }.clipShape(RecipeShape(spec: spec)) }
            .modifier(ButtonEdge(spec: spec, shape: RecipeShape(spec: spec), pressed: pressed))
            .modifier(DimWhenDisabled())
            .contentShape(RecipeShape(spec: spec))
    }

    /// Outlined round buttons (Classified's) are circles: as ellipses wider than tall, with their halo, they looked fat.
    /// The bar's small extras are as tall as they were; the transport and shuffle / repeat as wide as they were.
    static func diameter(_ spec: Style.ButtonSpec, _ size: SkinControlSize) -> CGSize? {
        guard spec.shape == .circle, spec.outline != nil else { return nil }
        let d = size == .small ? size.size.height : size.size.width
        return CGSize(width: d, height: d)
    }

    static func weight(_ w: ThemeFontWeight?) -> Font.Weight {
        switch w {
        case .regular: .regular
        case .bold: .bold
        case .heavy: .heavy
        case .semibold, nil: .semibold
        }
    }
}

/// A recipe button with a text label (Play, Shuffle, Follow): the same face, bevel and glyph colours as the
/// transport, sized to its label.
struct RecipeLabelButtonStyle: ButtonStyle {
    let spec: Style.ButtonSpec
    let fallbackGlyph: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let face = (pressed ? spec.pressed?.face : nil) ?? spec.face
        let glyph = (pressed ? spec.pressed?.glyph : nil) ?? spec.glyph
        let shape = RecipeShape(spec: Self.labelled(spec))
        configuration.label
            .font(.system(size: 11, weight: RecipeButtonStyle.weight(spec.glyphWeight)))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(glyph.map { Color($0) } ?? fallbackGlyph)
            .padding(.horizontal, 10).frame(height: 22)
            .background { if let face { MaterialFill(material: face).clipShape(shape) } }
            .modifier(ButtonEdge(spec: spec, shape: shape, pressed: pressed))
            .modifier(DimWhenDisabled())
            .contentShape(shape)
    }

    /// The shape for a button with a label: the recipe's `labelShape`, else its shape, except that a label never sits
    /// in a circle (an ellipse round "Shuffle" reads as a pill).
    static func labelled(_ spec: Style.ButtonSpec) -> Style.ButtonSpec {
        var s = spec
        if let shape = spec.labelShape { s.shape = shape }
        else if spec.shape == .circle { s.shape = .rounded; s.radius = 6 }
        return s
    }
}

/// A recipe button's edge: the original Classified's dark outline with a light halo ring outside it when the recipe
/// gives them (no bevel then: a square bevel clipped to an ellipse drew stray shading lines), else the bevel.
struct ButtonEdge: ViewModifier {
    let spec: Style.ButtonSpec
    let shape: RecipeShape
    let pressed: Bool

    func body(content: Content) -> some View {
        if spec.outline != nil || spec.halo != nil {
            content
                .overlay { if let outline = spec.outline { shape.stroke(Color(outline), lineWidth: 1).allowsHitTesting(false) } }
                .background { if let halo = spec.halo { shape.stroke(Color(halo), lineWidth: 1.5).padding(-1.25).allowsHitTesting(false) } }
        } else {
            content.overlay { if let bevel = spec.bevel { BevelFrame(bevel: bevel, pressed: pressed).clipShape(shape) } }
        }
    }
}

/// The recipe's button outline.
struct RecipeShape: Shape {
    let spec: Style.ButtonSpec
    func path(in rect: CGRect) -> Path {
        switch spec.shape ?? .rect {
        case .rect: Rectangle().path(in: rect)
        case .rounded: RoundedRectangle(cornerRadius: CGFloat(spec.radius ?? 3)).path(in: rect)
        case .circle: Ellipse().path(in: rect)
        case .pill: Capsule().path(in: rect)
        }
    }
}

/// A custom button style isn't dimmed by `.disabled` on its own (the plain style is).
struct DimWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View { content.opacity(isEnabled ? 1 : 0.4) }
}

extension View {
    /// With a recipe, the button becomes a recipe button; otherwise the view is left as it is.
    /// `square`: a rectangle with slightly rounded corners whatever the skin's shape (the sidebar button).
    func skinnedControl(_ size: SkinControlSize, active: Bool = false, square: Bool = false) -> some View {
        modifier(SkinnedControl(size: size, active: active, square: square))
    }
}

private struct SkinnedControl: ViewModifier {
    @Environment(\.theme) private var theme
    let size: SkinControlSize
    let active: Bool
    let square: Bool

    func body(content: Content) -> some View {
        if let spec = theme.style?.button {
            content.buttonStyle(RecipeButtonStyle(spec: square ? Self.square(spec) : spec, size: size, active: active, fallbackGlyph: theme.text))
        } else {
            content
        }
    }

    static func square(_ spec: Style.ButtonSpec) -> Style.ButtonSpec {
        var s = spec
        s.shape = .rounded
        s.radius = 3
        return s
    }
}
