import CoreGraphics
import Foundation
import Testing
@testable import GreedifyKit

/// Repeating tiles for the textured materials (curated skins spec §3): built in code, tiny, stable per seed.
struct MaterialTileTests {
    func c(_ hex: String) -> ThemeColor { ThemeColor(hex: hex)! }
    func pixels(_ image: CGImage?) throws -> RGBAImage { try #require(image.flatMap(RGBAImage.init)) }
    func rgba(_ hex: String) -> UInt32 { UInt32(hex.dropFirst(), radix: 16)! << 8 | 0xFF }

    @Test func aDotGridRepeatsEveryPitch() throws {
        let tile = try pixels(MaterialTile.make(.dotGrid(base: c("#101C48"), dot: c("#24346A"), pitch: 3, size: 1), scale: 2))
        #expect(tile.width == 6 && tile.height == 6)
        #expect(tile[0, 0] == rgba("#24346A") && tile[1, 1] == rgba("#24346A"))   // a 1 pt dot at 2× is 2×2 px
        #expect(tile[2, 2] == rgba("#101C48") && tile[5, 5] == rgba("#101C48"))
    }

    @Test func aPatternReproducesItsMatrix() throws {
        let tile = try pixels(MaterialTile.make(.pattern(width: 2, height: 2, scale: 1, colors: [c("#000000"), c("#FFFFFF"), c("#FF0000"), c("#00FF00")]), scale: 1))
        #expect(tile.width == 2 && tile.pixels == [rgba("#000000"), rgba("#FFFFFF"), rgba("#FF0000"), rgba("#00FF00")])
    }

    @Test func noiseAndBrushedAreStablePerSeed() throws {
        for (a, b) in [(Style.Material.noise(base: c("#2B2420"), amount: 0.1, seed: 3), Style.Material.noise(base: c("#2B2420"), amount: 0.1, seed: 4)),
                       (.brushed(base: c("#B8BCC4"), streak: c("#9EA3AC"), density: 0.4, seed: 7), .brushed(base: c("#B8BCC4"), streak: c("#9EA3AC"), density: 0.4, seed: 8))] {
            let first = try pixels(MaterialTile.make(a, scale: 2)), again = try pixels(MaterialTile.make(a, scale: 2))
            #expect(first == again)
            #expect(first != (try pixels(MaterialTile.make(b, scale: 2))))
            #expect(first.width == MaterialTile.textureSide && first.height == MaterialTile.textureSide)
        }
    }

    @Test func flatMaterialsAndOversizeTilesHaveNoTile() {
        #expect(MaterialTile.make(.solid(c("#000000")), scale: 2) == nil)
        #expect(MaterialTile.make(.gradient(angle: 90, stops: [.init(color: c("#000000"), at: 0)]), scale: 2) == nil)
        #expect(MaterialTile.make(.pattern(width: 16, height: 16, scale: 8, colors: Array(repeating: c("#000000"), count: 256)), scale: 2) == nil)
    }
}
