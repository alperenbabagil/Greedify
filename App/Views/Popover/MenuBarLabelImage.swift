import AppKit

/// Draws the icon and the lyric line into one template image. The status item drops the symbol from a
/// label with an inline image, and lays out an HStack's image and title separately (misaligned), so
/// drawing both together is the only way to get a visible, baseline-aligned icon next to the text.
///
/// Drawn with AppKit, not SwiftUI's `ImageRenderer`: ImageRenderer renders through the GPU and keeps
/// its buffers, which measured +101 MB (60 MB GPU) after 150 lyric lines; AppKit drawing measured +1.5 MB.
@MainActor
enum MenuBarLabelImage {
    static let maxWidth: CGFloat = 280
    static let spacing: CGFloat = 4

    static func make(symbol: String, text: String) -> NSImage {
        let font = NSFont.menuBarFont(ofSize: 0)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular))
        let iconSize = icon?.size ?? .zero

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph,
        ])
        let lineHeight = ceil(font.ascender - font.descender)
        let textWidth = min(ceil(string.size().width), maxWidth - iconSize.width - spacing)
        let height = max(lineHeight, ceil(iconSize.height))
        let size = NSSize(width: ceil(iconSize.width) + spacing + textWidth, height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            let textY = (rect.height - lineHeight) / 2
            // Centre the symbol on the text's cap height, so it sits on the same visual line.
            let baseline = textY - font.descender
            let iconY = baseline + font.capHeight / 2 - iconSize.height / 2
            icon?.draw(in: NSRect(x: 0, y: iconY, width: iconSize.width, height: iconSize.height))
            string.draw(with: NSRect(x: ceil(iconSize.width) + spacing, y: textY, width: textWidth, height: lineHeight),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
        image.isTemplate = true // only the alpha matters; macOS tints it for the menu bar
        image.accessibilityDescription = text
        return image
    }
}
