import ImageIO
import AppKit
import GreedifyKit
import SwiftUI

/// Any recipe material as a fill (curated skins spec §3): solid and gradient natively, the textured kinds from a tiny
/// tile built in code and repeated with `ImagePaint`. Only ever used as a background, so it never sizes its parent.
struct MaterialFill: View {
    @Environment(\.displayScale) private var displayScale
    let material: Style.Material

    var body: some View {
        fill
            // A background never takes clicks. An `.image` fill is laid out larger than its strip and only clipped
            // when drawn: a skin's bar picture once caught clicks and scrolls ~200 pt above the bar, over the list.
            .allowsHitTesting(false)
    }

    @ViewBuilder private var fill: some View {
        switch material {
        case .solid(let color):
            Color(color)
        case .gradient(let angle, let stops):
            let radians = angle * .pi / 180
            let dx = cos(radians) / 2, dy = sin(radians) / 2
            LinearGradient(stops: stops.map { .init(color: Color($0.color), location: $0.at) },
                           startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
        case .radial(let x, let y, let radius, let stops):
            GeometryReader { geo in
                RadialGradient(stops: stops.map { .init(color: Color($0.color), location: $0.at) }, center: UnitPoint(x: x, y: y),
                               startRadius: 0, endRadius: CGFloat(radius) * max(geo.size.width, geo.size.height))
            }
        case .image(let name, let focusX, let focusY, let opacity):
            if let image = RecipeImageCache.shared.image(named: name) {
                // Aspect-fill, cropped so the focus point stays as close to the middle as the edges allow.
                GeometryReader { geo in
                    let iw = CGFloat(image.width), ih = CGFloat(image.height)
                    let scale = max(geo.size.width / max(iw, 1), geo.size.height / max(ih, 1))
                    let w = iw * scale, h = ih * scale
                    let x = min(0, max(geo.size.width - w, geo.size.width / 2 - w * focusX))
                    let y = min(0, max(geo.size.height - h, geo.size.height / 2 - h * focusY))
                    Image(decorative: image, scale: 1).resizable().interpolation(.high)
                        .frame(width: w, height: h).offset(x: x, y: y)
                }
                .clipped()
                .opacity(opacity)
            } else {
                Color.black
            }
        case .layers(let layers):
            ZStack { ForEach(Array(layers.enumerated()), id: \.offset) { MaterialFill(material: $0.element) } }
        default:
            if let tile = MaterialTileCache.shared.tile(material, scale: displayScale) {
                PatternLayer(tile: tile, scale: displayScale)
            } else {
                Color(material.base)
            }
        }
    }
}

/// Tiles per material and display scale: a handful per theme, a few KB each.
@MainActor
final class MaterialTileCache {
    static let shared = MaterialTileCache()
    private var tiles: [String: CGImage] = [:]

    func tile(_ material: Style.Material, scale: CGFloat) -> CGImage? {
        let key = "\(material)@\(scale)"
        if let tile = tiles[key] { return tile }
        guard let tile = MaterialTile.make(material, scale: scale) else { return nil }
        if tiles.count > 64 { tiles.removeAll() } // theme switches leave old tiles behind; they're cheap to rebuild
        tiles[key] = tile
        return tile
    }
}

/// A recipe bevel: raised, sunken, or double (a raised edge inside a sunken one).
struct BevelFrame: View {
    let bevel: Style.Bevel
    var pressed = false

    var body: some View {
        let light = Color(bevel.light), dark = Color(bevel.dark), width = CGFloat(bevel.width)
        let sunken = (bevel.kind == .sunken) != pressed
        ZStack {
            BevelEdges(pressed: sunken, width: width, light: light, dark: dark)
            if bevel.kind == .double { BevelEdges(pressed: !sunken, width: width, light: light, dark: dark).padding(width) }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// A recipe surface behind the view: its material, then its bevel on top.
    /// `radius` rounds the corners (Classified's LCDs): the bevel is clipped to the same shape.
    func recipeSurface(_ material: Style.Material?, bevel: Style.Bevel? = nil, radius: CGFloat = 0) -> some View {
        background { if let material { MaterialFill(material: material).clipShape(RoundedRectangle(cornerRadius: radius)) } }
            .overlay { if let bevel { BevelFrame(bevel: bevel).clipShape(RoundedRectangle(cornerRadius: radius)) } }
    }
}

/// A layer whose background is the tile as a pattern colour: Core Animation tiles it itself, with no full-size backing
/// store. (An `ImagePaint` fill rendered each textured surface into its own buffer, several MB per skin; a pattern
/// `Color` in SwiftUI rendered nothing.)
struct PatternLayer: NSViewRepresentable {
    let tile: CGImage
    let scale: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        view.wantsLayer = true
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { apply(to: view) }

    private func apply(to view: NSView) {
        let size = NSSize(width: CGFloat(tile.width) / scale, height: CGFloat(tile.height) / scale)
        view.layer?.backgroundColor = NSColor(patternImage: NSImage(cgImage: tile, size: size)).cgColor
    }

    /// A background never takes clicks.
    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Recipe pictures, decoded once at no more than 2048 px a side (curated skins: a skin's own art as a background).
@MainActor
final class RecipeImageCache {
    static let shared = RecipeImageCache()
    private var images: [String: CGImage] = [:]
    private var missing: Set<String> = []

    func image(named name: String) -> CGImage? {
        if let image = images[name] { return image }
        guard !missing.contains(name), let url = Theme.recipeImageURL(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else {
            missing.insert(name)
            return nil
        }
        images[name] = image
        return image
    }
}
