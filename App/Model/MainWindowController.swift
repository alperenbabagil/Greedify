import AppKit
import Darwin
import GreedifyKit
import SwiftUI

/// Owns the main window in AppKit so closing it really frees it. A SwiftUI `Window` scene keeps the
/// closed window's view graph and backing store alive (188 MB measured after closing, vs 24 MB fresh).
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var model: AppModel?
    private var doubleClickMonitor: Any?

    override init() {
        super.init()
        // Test hooks so memory can be measured from a terminal: open/close the window without clicking.
        // Always on in Debug; in Release only with `defaults write com.alperen.greedify debugHooks -bool YES`.
        guard Self.debugHooksEnabled else { return }
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.alperen.greedify.debug.closeMain"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window?.performClose(nil) }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.resize"), object: nil, queue: .main) { [weak self] note in
            // object: "WIDTHxHEIGHT", e.g. "900x600"
            let parts = (note.object as? String)?.split(separator: "x").compactMap { Double($0) } ?? []
            MainActor.assumeIsolated {
                guard parts.count == 2, let w = self?.window else { return }
                w.setContentSize(NSSize(width: parts[0], height: parts[1]))
            }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.route"), object: nil, queue: .main) { [weak self] note in
            // object: "liked" | "albums" | "artists" | "shows" | "episodes" | "show:<index>" | "playlist:<index>" | "search:<query>"
            let arg = note.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let model = self?.model else { return }
                if arg.hasPrefix("playlist:"), let i = Int(arg.dropFirst(9)), model.library.playlists.indices.contains(i) {
                    model.route = .playlist(model.library.playlists[i])
                } else if arg.hasPrefix("search:") {
                    model.search.query = String(arg.dropFirst(7)); model.route = .search
                } else if arg == "nowplaying:album", let album = model.player.track.flatMap(Album.init(of:)) {
                    model.open(.album(album))    // what clicking the player bar's title does
                } else if arg == "nowplaying:artist", let artist = model.player.track?.artists.first.flatMap(Artist.init(ref:)) {
                    model.open(.artist(artist))
                } else if arg == "shows" { model.route = .shows
                } else if arg == "episodes" { model.route = .episodes
                } else if arg.hasPrefix("show:"), let i = Int(arg.dropFirst(5)), model.library.shows.indices.contains(i) {
                    model.route = .show(model.library.shows[i])
                } else if arg == "albums" { model.route = .albums
                } else if arg == "artists" { model.route = .artists
                } else { model.route = .liked }
            }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.lyrics"), object: nil, queue: .main) { [weak self] note in
            let on = (note.object as? String) != "off"
            MainActor.assumeIsolated { self?.model?.showLyrics = on }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.sidebar"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.toggleSidebar() } // the toolbar's sidebar button
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.lyricsWidth"), object: nil, queue: .main) { [weak self] note in
            // object: a width in points, as if the panel's edge were dragged there
            guard let width = (note.object as? String).flatMap(Double.init) else { return }
            MainActor.assumeIsolated { self?.model?.setLyricsWidth(width, save: true) }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.theme"), object: nil, queue: .main) { [weak self] note in
            // object: a theme id, e.g. "builtin.classic" or "Pinkies.greedifytheme"
            guard let id = note.object as? String else { return }
            MainActor.assumeIsolated { self?.model?.selectTheme(id) }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.play"), object: nil, queue: .main) { [weak self] note in
            // object: "<context uri>", "<context uri>|shuffle" (the header's Play and Shuffle buttons) or
            // "<context uri>|at:<track uri>" (a click on that song's row)
            let parts = (note.object as? String)?.split(separator: "|").map(String.init) ?? []
            MainActor.assumeIsolated {
                guard let uri = parts.first, let player = self?.model?.player else { return }
                let shuffled = parts.dropFirst().first == "shuffle"
                let start = parts.dropFirst().first { $0.hasPrefix("at:") }.map { String($0.dropFirst(3)) }
                Task { await player.play(.context(uri, startingAt: start), shuffled: shuffled ? true : nil) }
            }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.zoom"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window?.performZoom(nil) } // animated, like a title-bar double-click
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.snapshot"), object: nil, queue: .main) { [weak self] note in
            // object: a PNG path. The window draws itself, so no Screen Recording permission is needed.
            guard let path = note.object as? String else { return }
            MainActor.assumeIsolated {
                guard let view = self?.window?.contentView?.superview ?? self?.window?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.popoverSnapshot"), object: nil, queue: .main) { [weak self] note in
            // object: "PNG path|query" — draws the popover offscreen after the query's search has had time to finish.
            // A query opens the search section; "@device", "@volume" or "@lyrics" opens that section instead.
            let parts = (note.object as? String)?.split(separator: "|", maxSplits: 1).map(String.init) ?? []
            MainActor.assumeIsolated {
                guard let model = self?.model, let path = parts.first else { return }
                let query = parts.count > 1 ? parts[1] : ""
                let section: PopoverView.Section? = switch query {
                case "": nil
                case "@device": .device
                case "@volume": .volume
                case "@lyrics": .lyrics
                default: .search
                }
                model.quickSearch.query = section == .search ? query : ""
                let host = NSHostingView(rootView: Themed { PopoverView(section: section) }.environment(model))
                host.appearance = NSApp.effectiveAppearance // no window to take it from
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    host.frame = NSRect(origin: .zero, size: host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.focusSearch"), object: nil, queue: .main) { [weak self] _ in
            // Focuses the window's search field, as a click does (text input and AutoFill load on first focus).
            MainActor.assumeIsolated {
                guard let w = self?.window else { return }
                func field(in v: NSView) -> NSTextField? {
                    if let f = v as? NSSearchField { return f }
                    if let f = v as? NSTextField, f.isEditable { return f } // a framed skin's own field
                    for s in v.subviews { if let f = field(in: s) { return f } }
                    return nil
                }
                if let root = w.contentView?.superview, let f = field(in: root) { w.makeFirstResponder(f) }
            }
        }
        center.addObserver(forName: .init("com.alperen.greedify.debug.showMain"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let model = self?.model { self?.show(model: model) } }
        }
    }

    static var debugHooksEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "debugHooks")
        #endif
    }

    var isOpen: Bool { window != nil }

    func attach(_ model: AppModel) { self.model = model }

    func show(model: AppModel) {
        self.model = model
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: Themed { MainWindow() }.environment(model))
        // No hosting-driven size constraints: with NavigationSplitView they feed back into its column sizes and
        // AppKit aborts ("too many Update Constraints passes"); `.minSize` alone made the sidebar add to the window's
        // minimum (752 pt). The hosting view then keeps the window's `contentMinSize` at 0, so the minimum is
        // enforced in `windowWillResize` instead.
        host.sizingOptions = []
        let w = NSWindow(contentViewController: host)
        w.title = "Greedify"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.toolbar = NSToolbar(identifier: "GreedifyMain") // NavigationSplitView and the search field attach their items here
        w.toolbarStyle = .unifiedCompact
        w.isReleasedWhenClosed = false // we drop our reference in windowWillClose instead
        w.delegate = self
        w.setContentSize(NSSize(width: 1180, height: 720))
        if !w.setFrameUsingName("GreedifyMain") { w.center() }
        w.setFrameAutosaveName("GreedifyMain")
        // A saved frame from before the minimum was raised: a restore doesn't ask windowWillResize.
        if w.frame.width < Self.minContentSize.width || w.frame.height < Self.minContentSize.height {
            w.setContentSize(NSSize(width: max(w.frame.width, Self.minContentSize.width), height: max(w.frame.height, Self.minContentSize.height)))
        }
        window = w
        installTitleBarDoubleClick()
        w.makeKeyAndOrderFront(nil)
    }

    /// With a SwiftUI toolbar in a full-size-content window, AppKit minimized on a title-bar double-click
    /// even though the system default is zoom. Handle it here and follow the system setting.
    private func installTitleBarDoubleClick() {
        guard doubleClickMonitor == nil else { return }
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard event.clickCount == 2 else { return event }
            let location = event.locationInWindow
            let eventWindow = event.window
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let w = self.window, eventWindow === w,
                      location.y >= w.contentLayoutRect.maxY else { return false } // title bar / toolbar strip
                let hit = w.contentView?.hitTest(location)
                if hit is NSControl || hit is NSTextView { return false }            // a button or field
                switch TitleBarDoubleClick.current {
                case .zoom: w.performZoom(nil)
                case .minimize: w.performMiniaturize(nil)
                case .none: break
                }
                return true
            }
            return handled ? nil : event
        }
    }

    /// The window's minimum for a drag (AdaptiveLayout). `contentMinSize` can't hold it: the
    /// hosting view resets it to 0 on every resize, and the window then dragged down to ~100 pt.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimum = sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.minContentSize)).size // full-size content: the whole window
        return NSSize(width: max(frameSize.width, minimum.width), height: max(frameSize.height, minimum.height))
    }

    static let minContentSize = NSSize(width: AdaptiveLayout.windowMinWidth, height: AdaptiveLayout.windowMinHeight)

    func windowWillClose(_ notification: Notification) {
        guard let closing = window else { return }
        // Tear the SwiftUI hierarchy down now and drop the window, so its memory is returned.
        closing.contentViewController = nil
        closing.delegate = nil
        window = nil
        if let doubleClickMonitor { NSEvent.removeMonitor(doubleClickMonitor) }
        doubleClickMonitor = nil
        model?.images.clearMemory()
        // The window's objects are freed, but malloc keeps the emptied pages (measured ~38 MB of free
        // "Malloc Small" after closing). Once teardown has finished, hand them back to macOS.
        Task {
            try? await Task.sleep(for: .seconds(2))
            malloc_zone_pressure_relief(nil, 0)
        }
        // Settings belongs to the main window: it goes with it.
        NSApp.windows.filter { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" && $0.isVisible }.forEach { $0.close() }
        // Back to menu-bar-only unless another Greedify window (setup, settings) is still open.
        let others = NSApp.windows.filter { $0 !== closing && $0.isVisible && $0.canBecomeMain }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
