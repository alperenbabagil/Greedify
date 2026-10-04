import GreedifyKit
import SwiftUI

extension View {
    /// A skin's own scroller beside a scroll view (`list.scroller`; winamp window spec): a silver track and a ridged
    /// thumb in place of the system's overlay scroller. Apply it to the `ScrollView` itself. Without a scroller in the
    /// recipe the view is left as it is.
    func skinScroller() -> some View { modifier(SkinScrollerModifier()) }
}

/// The scroll view's extent, as the thumb needs it: rounded, so the state changes only when the thumb would move.
private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var visible: CGFloat = 0
}

private struct SkinScrollerModifier: ViewModifier {
    @Environment(\.theme) private var theme
    @State private var metrics = ScrollMetrics()
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        if let spec = theme.style?.list?.scroller {
            content
                .scrollIndicators(.hidden)
                .scrollPosition($position)
                // Only while scrolling, and only by whole points.
                .onScrollGeometryChange(for: ScrollMetrics.self) { g in
                    ScrollMetrics(offset: (g.contentOffset.y + g.contentInsets.top).rounded(), content: g.contentSize.height.rounded(),
                                  visible: (g.containerSize.height - g.contentInsets.top - g.contentInsets.bottom).rounded())
                } action: { _, new in metrics = new }
                .safeAreaInset(edge: .trailing, spacing: 0) {
                    SkinScrollerTrack(spec: spec, metrics: metrics) { y in position.scrollTo(y: y) }
                }
        } else {
            content
        }
    }
}

/// The track and its thumb. Dragging the thumb scrolls with it; a click on the track jumps a page toward the click.
private struct SkinScrollerTrack: View {
    let spec: Style.ScrollerSpec
    let metrics: ScrollMetrics
    let scrollTo: (CGFloat) -> Void
    @State private var dragStart: CGFloat?

    var body: some View {
        let width = CGFloat(spec.width ?? 12)
        GeometryReader { geo in
            let track = geo.size.height
            let range = max(0, metrics.content - metrics.visible)
            let thumb = range > 0 ? max(24, track * metrics.visible / max(metrics.content, 1)) : 0
            let travel = max(0, track - thumb)
            let y = range > 0 ? travel * min(max(metrics.offset / range, 0), 1) : 0
            ZStack(alignment: .top) {
                Group { if let material = spec.track { MaterialFill(material: material) } else { Color.black.opacity(0.2) } }
                    .overlay { if let bevel = spec.bevel { BevelFrame(bevel: Style.Bevel(kind: .sunken, light: bevel.light, dark: bevel.dark, width: 1)) } }
                if thumb > 0 {
                    thumbView(width: width)
                        .frame(height: thumb)
                        .offset(y: y)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard range > 0, travel > 0 else { return }
                    if dragStart == nil {
                        // On the thumb: drag it from where it was grabbed; on the track: page toward the click.
                        if drag.startLocation.y >= y && drag.startLocation.y <= y + thumb {
                            dragStart = metrics.offset
                        } else {
                            let page = metrics.visible * 0.9
                            scrollTo(min(max(metrics.offset + (drag.startLocation.y < y ? -page : page), 0), range))
                            dragStart = .infinity // a click on the track doesn't then drag
                            return
                        }
                    }
                    guard let start = dragStart, start.isFinite else { return }
                    scrollTo(min(max(start + drag.translation.height / travel * range, 0), range))
                }
                .onEnded { _ in dragStart = nil })
        }
        .frame(width: width)
        .accessibilityHidden(true) // the scroll view itself stays scrollable for VoiceOver
    }

    /// A raised thumb with three ridges across its middle.
    private func thumbView(width: CGFloat) -> some View {
        let bevel = spec.bevel
        return Group { if let material = spec.thumb { MaterialFill(material: material) } else { Color.gray } }
            .overlay { if let bevel { BevelFrame(bevel: bevel) } }
            .overlay {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Color(bevel?.dark ?? .black).frame(height: 1)
                            Color(bevel?.light ?? .white).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 3)
            }
            .frame(width: width)
    }
}

/// A page's vertical scroll view, with the skin's scroller when it has one.
struct PageScrollView<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { content }.skinScroller() }
}
