import Foundation

/// Widths at which the main window rearranges itself as it narrows.
public enum AdaptiveLayout {
    /// The window's narrowest content width.
    /// The window's narrowest width and lowest height, title bar included (the content runs under it).
    public static let windowMinWidth: CGFloat = 520
    public static let windowMinHeight: CGFloat = 720
    /// The sidebar's ideal, minimum and maximum widths and the detail column's minimum. Each column's minimum is
    /// constant: one that followed its content looped AppKit's constraint passes during a resize or zoom ("too many
    /// Update Constraints"). The sidebar fits beside the page even at the window's minimum, so the toggle always can.
    public static let sidebarWidth: CGFloat = 232
    public static let sidebarMinWidth: CGFloat = 200
    public static let sidebarMaxWidth: CGFloat = 300
    public static let detailMinWidth: CGFloat = 300
    /// Below this the sidebar collapses by itself, and the lyrics stay hidden.
    public static let sidebarAutoWidth: CGFloat = 720
    /// The lyrics panel's width range (drag its edge), and the page width it leaves at least. The panel is drawn
    /// inside the detail column, not as an AppKit inspector: opening an inspector anywhere the page had to shrink for
    /// it aborted the app the same way.
    public static let lyricsMinWidth: CGFloat = 260
    public static let lyricsMaxWidth: CGFloat = 400
    public static let pageWidthBesideLyrics: CGFloat = 340

    /// The player bar: one row with everything (wide), one row with the volume in a popover (medium), or two rows
    /// with the transport and the seek bar below (compact).
    public enum BarMode: Sendable { case wide, medium, compact }

    /// What the bar's mode depends on: its fixed parts (the transport's minimum, spacing and padding) and the
    /// measured width of its right-hand group in the wide and medium layouts. The transport stays centred between
    /// two equal sides, so each side needs room for that group; a fixed threshold let a long device name overlap it.
    public struct BarMetrics: Equatable, Sendable {
        public var chrome: CGFloat
        public var wideExtras: CGFloat
        public var mediumExtras: CGFloat

        public init(chrome: CGFloat, wideExtras: CGFloat, mediumExtras: CGFloat) {
            self.chrome = chrome
            self.wideExtras = wideExtras
            self.mediumExtras = mediumExtras
        }

        public func mode(width: CGFloat, current: BarMode) -> BarMode {
            let wideFrom = chrome + 2 * max(wideExtras, 180) + (current == .wide ? 0 : hysteresis)
            let mediumFrom = chrome + 2 * max(mediumExtras, 140) + (current == .compact ? hysteresis : 0)
            return width >= wideFrom ? .wide : width >= mediumFrom ? .medium : .compact
        }
    }

    /// Song tables drop their Album column when narrower than this.
    public static func showsAlbumColumn(tableWidth: CGFloat, wasShown: Bool = true) -> Bool {
        tableWidth >= 560 + (wasShown ? 0 : hysteresis)
    }

    /// A page header puts its cover above the title when narrower than this.
    public static func stacksHeader(width: CGFloat, wasStacked: Bool = false) -> Bool {
        width < 520 + (wasStacked ? hysteresis : 0)
    }

    /// Every switch flips at its threshold but only flips back once the width is this far past it, so a drag
    /// wobbling at a threshold doesn't toggle the layout (and its animation) back and forth.
    public static let hysteresis: CGFloat = 40
}

/// What the main window shows at its width: as it narrows the lyrics hide first, then the sidebar collapses; the
/// sidebar toggle overrides the width until the window crosses the collapse width again.
public struct WindowLayout: Equatable, Sendable {
    public private(set) var width: CGFloat = 0
    public private(set) var lyricsWidth: CGFloat
    public private(set) var showsSidebar = true
    public private(set) var showsLyrics = true
    private var sidebarOverride: Bool?
    /// Room for the sidebar, with the hysteresis margin: collapses under 720, comes back from 760.
    private var sidebarFits = true

    public init(lyricsWidth: CGFloat) {
        self.lyricsWidth = min(max(lyricsWidth, AdaptiveLayout.lyricsMinWidth), AdaptiveLayout.lyricsMaxWidth)
    }

    /// The space the lyrics may take: what the sidebar (at its widest) and the page leave.
    private var roomForLyrics: CGFloat {
        width - (showsSidebar ? AdaptiveLayout.sidebarMaxWidth : 0) - AdaptiveLayout.pageWidthBesideLyrics
    }

    public mutating func resize(to newWidth: CGFloat) {
        width = newWidth
        let fits = width >= AdaptiveLayout.sidebarAutoWidth + (sidebarFits ? 0 : AdaptiveLayout.hysteresis)
        if fits != sidebarFits { sidebarFits = fits; sidebarOverride = nil } // crossed the collapse width: automatic again
        update()
    }

    public mutating func toggleSidebar() {
        sidebarOverride = !showsSidebar
        update()
    }

    /// Dragging the panel's edge: kept in range, and never so wide that the page goes under its width beside them.
    public mutating func setLyricsWidth(_ proposed: CGFloat) {
        let upper = min(AdaptiveLayout.lyricsMaxWidth, max(AdaptiveLayout.lyricsMinWidth, roomForLyrics))
        lyricsWidth = min(max(proposed, AdaptiveLayout.lyricsMinWidth), upper)
        update()
    }

    private mutating func update() {
        showsSidebar = sidebarOverride ?? sidebarFits
        showsLyrics = sidebarFits && roomForLyrics >= lyricsWidth + (showsLyrics ? 0 : AdaptiveLayout.hysteresis)
    }
}
