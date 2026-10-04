import Foundation

/// A Winamp `text.bmp` pixel font (theme images spec §4): 5×6 cells, 31 columns, up to 3 rows.
/// Glyphs are ink masks (the pixels that differ from the paper), so the app can tint them.
public final class PixelFont: Sendable {
    public static let cellWidth = 5
    public static let cellHeight = 6
    public static let columns = 31
    static let space = (row: 0, column: 30)

    private static let rows: [[Character]] = [
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ\"@"),
        Array("0123456789" + "….:()-'!_+\\/[]^&%,=$#"),
        Array("ÅÖÄ?*"),
    ]

    private let masks: [[Bool]] // index row * columns + column

    public init?(png: Data) {
        guard let bitmap = SkinBitmap(data: png),
              bitmap.width >= ThemeImage.pixelFontMinWidth, bitmap.height >= ThemeImage.pixelFontMinHeight,
              let paper = bitmap.color(x: Self.space.column * Self.cellWidth, y: 0) else { return nil }
        let rowCount = min(Self.rows.count, bitmap.height / Self.cellHeight)
        func distance(_ p: ThemeColor, _ q: ThemeColor) -> Double { abs(p.r - q.r) + abs(p.g - q.g) + abs(p.b - q.b) }
        // The ink: the colour farthest from the paper. A pixel is ink when it's closer to that than to the paper, so a
        // skin's dim shading around its glyphs stays paper instead of filling every cell.
        var ink = paper
        for y in 0..<(rowCount * Self.cellHeight) {
            for x in 0..<(Self.columns * Self.cellWidth) {
                if let p = bitmap.color(x: x, y: y), distance(p, paper) > distance(ink, paper) { ink = p }
            }
        }
        var masks: [[Bool]] = []
        for row in 0..<Self.rows.count {
            for column in 0..<Self.columns {
                var cell: [Bool] = []
                for y in 0..<Self.cellHeight {
                    for x in 0..<Self.cellWidth {
                        guard row < rowCount, let p = bitmap.color(x: column * Self.cellWidth + x, y: row * Self.cellHeight + y) else {
                            cell.append(false); continue
                        }
                        cell.append(distance(p, paper) > 0.1 && distance(p, paper) > distance(p, ink))
                    }
                }
                masks.append(cell)
            }
        }
        // A space with ink means patterned paper: every glyph would come out as a block.
        guard !masks[Self.space.row * Self.columns + Self.space.column].contains(true) else { return nil }
        self.masks = masks
    }

    /// 30 values, row-major (5 wide, 6 tall): `true` where the glyph has ink.
    public func mask(row: Int, column: Int) -> [Bool] {
        let i = row * Self.columns + column
        return masks.indices.contains(i) ? masks[i] : Array(repeating: false, count: Self.cellWidth * Self.cellHeight)
    }

    public static func glyphs(for text: String) -> [(row: Int, column: Int)] { text.map(cell(for:)) }

    /// Uppercase first; otherwise fold the diacritic; otherwise a space.
    public static func cell(for character: Character) -> (row: Int, column: Int) {
        if let c = lookup(String(character).uppercased()) { return c }
        let folded = String(character).folding(options: .diacriticInsensitive, locale: nil).uppercased()
        return lookup(folded) ?? space
    }

    private static func lookup(_ s: String) -> (row: Int, column: Int)? {
        guard s.count == 1, let ch = s.first else { return nil }
        if ch == " " { return space }
        for (row, characters) in rows.enumerated() {
            if let column = characters.firstIndex(of: ch) { return (row, column) }
        }
        return nil
    }
}
