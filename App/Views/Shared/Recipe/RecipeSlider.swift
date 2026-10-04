import GreedifyKit
import SwiftUI

/// A slider drawn from the recipe (curated skins spec §2.1): groove material and bevel, a fill (none, solid, or a
/// colour ramp across the filled part) and a thumb.
struct RecipeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let spec: Style.SliderSpec
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false

    var body: some View {
        let thumbSize = CGSize(width: spec.thumb?.width ?? 14, height: spec.thumb?.height ?? 12)
        let grooveHeight = CGFloat(spec.groove?.height ?? 6)
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
            let x = CGFloat(fraction) * max(0, geo.size.width - thumbSize.width)
            ZStack(alignment: .leading) {
                Color.clear
                    .frame(height: grooveHeight)
                    .recipeSurface(spec.groove?.material ?? .solid(.black), bevel: spec.groove?.bevel)
                fill
                    .frame(width: max(0, x + thumbSize.width / 2), height: max(1, grooveHeight - 2))
                    .padding(.leading, 1)
                thumb.frame(width: thumbSize.width, height: thumbSize.height).offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let f = min(max((drag.location.x - thumbSize.width / 2) / max(1, geo.size.width - thumbSize.width), 0), 1)
                        value = range.lowerBound + Double(f) * span
                    }
                    .onEnded { _ in dragging = false; onEditingChanged(false) }
            )
        }
        .frame(height: max(thumbSize.height, grooveHeight) + 2)
    }

    @ViewBuilder private var fill: some View {
        switch spec.fill?.kind {
        case .solid?: Color(spec.fill?.colors.first ?? .white)
        case .ramp?: LinearGradient(colors: (spec.fill?.colors ?? []).map { Color($0) }, startPoint: .leading, endPoint: .trailing)
        case .none?, nil: Color.clear
        }
    }

    @ViewBuilder private var thumb: some View {
        let shape = AnyShape(Self.shape(spec.thumb?.shape))
        shape.fill(Color.clear)
            .background { MaterialFill(material: spec.thumb?.face ?? .solid(.white)) }
            .overlay { if let bevel = spec.thumb?.bevel { BevelFrame(bevel: bevel, pressed: dragging) } }
            .clipShape(shape)
    }

    static func shape(_ s: Style.ThumbShape?) -> any Shape {
        switch s {
        case .circle: Ellipse()
        case .rounded: RoundedRectangle(cornerRadius: 3)
        case .rect, nil: Rectangle()
        }
    }
}
