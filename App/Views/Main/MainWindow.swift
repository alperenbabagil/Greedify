import GreedifyKit
import SwiftUI

/// Main window (approved mockup: docs/superpowers/specs/mockups/main-window.html).
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        @Bindable var search = model.search
        // Every column gets a constant minimum size (`.fixedMinimum`). When a column's minimum changed with
        // its content (a page loading, the player bar updating) during a resize or zoom, NavigationSplitView re-laid
        // out in a loop and AppKit aborted ("too many Update Constraints passes"). The visible columns must also fit
        // the window: as it narrows the lyrics hide first, then the sidebar collapses (WindowLayout), each before its
        // minimum stops fitting; the sidebar fits beside the page even at the window's minimum, for the toggle. The lyrics are drawn inside the detail column (DetailColumn): as an AppKit inspector,
        // opening them anywhere the page had to shrink aborted the same way.
        // The player bar sits below the split view, so it spans the sidebar and the lyrics panel too.
        // Read-only: the width decides, and AppKit's write-back of what it was given changes nothing.
        let sidebar = Binding<NavigationSplitViewVisibility>(get: { model.windowShowsSidebar ? .all : .detailOnly }, set: { _ in })
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: sidebar) {
                Sidebar(searchFocus: $searchFocused)
                    .winampFrame("Library", titleBar: TitleBarBand(leading: 84))
                    .fixedMinimum(width: AdaptiveLayout.sidebarMinWidth, height: 300)
                    .navigationSplitViewColumnWidth(min: AdaptiveLayout.sidebarMinWidth, ideal: AdaptiveLayout.sidebarWidth,
                                                    max: AdaptiveLayout.sidebarMaxWidth)
            } detail: {
                // 360 pt high: the window's minimum height (720) also holds the toolbar and a two-row compact player bar.
                DetailColumn()
                    .fixedMinimum(width: AdaptiveLayout.detailMinWidth, height: 360)
                    .toolbar {
                        // A skin's own button in a Winamp window, without the glass platter macOS 26 puts round a
                        // toolbar item (it made the square button look round); native otherwise.
                        if #available(macOS 26.0, *) {
                            sidebarButton.sharedBackgroundVisibility(theme.style?.button != nil ? .hidden : .automatic)
                            refreshButton.sharedBackgroundVisibility(theme.style?.button != nil ? .hidden : .automatic)
                        } else {
                            sidebarButton
                            refreshButton
                        }
                    }
            }
            // A framed skin draws its own search field (in the sidebar) and title bar (WinampFrame): AppKit's
            // `.searchable` field and the window title can't be restyled. Switching between the two rebuilds the columns.
            .modifier(WindowSearch(query: $search.query, focus: $searchFocused, native: theme.style?.frame == nil))
            .onChange(of: search.query) { if !search.query.isEmpty { model.route = .search } }
            PlayerBar().proposedWidth()
        }
        // The window's minimum width for programmatic resizes; a drag is held by MainWindowController.windowWillResize.
        // No minimum height here: it applies below the title bar, so at the window's minimum the content was taller
        // than its space and the player bar was cut off at the bottom.
        .frame(minWidth: AdaptiveLayout.windowMinWidth)
        // The window's width alone (a proposal), so nothing shown here can feed back into it. Rounded: the model
        // only republishes what changes.
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { model.layoutWindow(width: $0) }
        .background { Button("") { searchFocused = true }.keyboardShortcut("k").hidden() }
        .modifier(BannerOverlay())
        .onAppear { model.player.surfaceAppeared("window") }
        .onDisappear { model.player.surfaceDisappeared("window"); model.images.clearMemory() }
    }
}

extension MainWindow {
    var sidebarButton: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .iconLabel(model.windowShowsSidebar ? "Hide Sidebar" : "Show Sidebar")
                .keyboardShortcut("s", modifiers: [.command, .control])
                .skinnedControl(.small, square: true) // a rectangle in every skin
        }
    }

    /// Reloads the library: playlists and lists edited in another Spotify app.
    var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.refreshLibrary() } label: { Image(systemName: "arrow.clockwise") }
                .iconLabel("Refresh")
                .keyboardShortcut("r")
                .disabled(model.refreshing)
                .skinnedControl(.small, square: true)
        }
    }
}

/// Makes the window's title bar transparent while it's in the view tree, and restores it when it leaves (a theme
/// switch to a skin without frames).
private struct TransparentTitlebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowHook() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class WindowHook: NSView {
        private weak var hooked: NSWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { hooked = window; window.titlebarAppearsTransparent = true }
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { hooked?.titlebarAppearsTransparent = false }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}

/// AppKit's sidebar search field and the window title, or (a framed skin) neither: the skin draws both.
private struct WindowSearch: ViewModifier {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    let native: Bool

    func body(content: Content) -> some View {
        if native {
            content.searchable(text: $query, placement: .sidebar, prompt: "Search").searchFocused(focus)
        } else {
            // The title bar's own backdrop (NSTitlebarBackgroundView) sits above the content: it covered the skin's
            // title bar band, and the name drawn in it couldn't be seen.
            content.toolbar(removing: .title)
                // The title bar's backdrop over the page column drew plain dark grey on screen (offscreen snapshots
                // leave it out): transparent, the skin's band shows across every column.
                .background { TransparentTitlebar() }
        }
    }
}

extension View {
    /// A minimum size that doesn't depend on the content. A `frame(minWidth:maxWidth:)` still reported the content's
    /// own width when that was wider (the track table's fixed columns made the detail column's minimum ~640 pt), and
    /// with the lyrics inspector open SwiftUI passed that minimum on to AppKit, so the window couldn't narrow and a
    /// change in the content during a resize looped the constraint passes.
    func fixedMinimum(width: CGFloat, height: CGFloat) -> some View {
        FixedMinimumLayout(minWidth: width, minHeight: height) { self }
    }
}

/// Takes the width it's offered, whatever its content's minimum, so it never sets the window's minimum width.
private struct ProposedWidthLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

extension View {
    func proposedWidth() -> some View { ProposedWidthLayout { self } }
}

/// Sizes itself from the proposal alone, never smaller than the minimum, and gives its content exactly that size.
private struct FixedMinimumLayout: Layout {
    let minWidth: CGFloat
    let minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: max(minWidth, proposal.width ?? minWidth), height: max(minHeight, proposal.height ?? minHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

/// The page, and the lyrics beside it while the window is wide enough for them (WindowLayout). The panel's left
/// edge drags to resize it.
struct DetailColumn: View {
    @Environment(AppModel.self) private var model
    @State private var dragStart: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            DetailView(route: model.route)
                // A page per list: opening another playlist gets a fresh scroll view and table, not the last
                // list's. Reused, a short list opened after scrolling far down a long one once drew no rows.
                .id(model.route?.page)
                .themedSurface(.content)
                // With the sidebar hidden the traffic lights sit here too, beside the sidebar and refresh buttons (44 pt each).
                .winampFrame("Playlist", titleBar: TitleBarBand(label: "Greedify", leading: model.windowShowsSidebar ? 100 : 184))
            if model.showLyrics && model.windowFitsLyrics {
                LyricsPanel()
                    .winampFrame("Lyrics", titleBar: TitleBarBand(leading: 12))
                    .frame(width: model.lyricsWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .overlay(alignment: .leading) {
                        Color.clear
                            .frame(width: 7) // the grab area, wider than the line
                            .contentShape(Rectangle())
                            .overlay(alignment: .leading) { ThemedDivider(vertical: true) }
                            .pointerStyle(.frameResize(position: .leading))
                            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { drag in
                                    let start = dragStart ?? model.lyricsWidth
                                    dragStart = start
                                    model.setLyricsWidth(start - drag.translation.width)
                                }
                                .onEnded { _ in
                                    dragStart = nil
                                    model.setLyricsWidth(model.lyricsWidth, save: true)
                                })
                    }
            }
        }
    }
}

struct DetailView: View {
    let route: Route?
    var body: some View {
        switch route {
        case .search: SearchResultsView()
        case .liked, nil: LikedSongsView()
        case .albums: AlbumsGrid()
        case .artists: ArtistsGrid()
        case .playlist(let p): PlaylistView(playlist: p)
        case .mix(let m): MixView(mix: m)
        case .album(let a): AlbumView(album: a)
        case .artist(let a): ArtistView(artist: a)
        case .shows: ShowsGrid()
        case .episodes: SavedEpisodesView()
        case .show(let s): ShowView(show: s)
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    /// The window's search focus, for the skin's own search field.
    var searchFocus: FocusState<Bool>.Binding
    @State private var addingMix = false
    @State private var creatingPlaylist = false

    var body: some View {
        let library = model.library
        // No `selection:` binding: the native highlight can't be themed, so rows draw their own (spec §5).
        List {
            Section {
                row(.liked) {
                    Label {
                        HStack {
                            Text("Liked Songs")
                            Spacer()
                            Text(library.likedTotal > 0 ? "\(library.likedTotal)" : "").themed(.tertiary).themedFont(.caption)
                        }
                    } icon: { Image(systemName: "heart") }
                }
                .contextMenu {
                    if let user = library.user {
                        MenuBarToggleButton(item: QuickPlayItem(uri: "spotify:user:\(user.id):collection", name: "Liked Songs"))
                    }
                }
                row(.albums) { Label("Albums", systemImage: "square.stack") }
                row(.artists) { Label("Artists", systemImage: "music.mic") }
            } header: { SectionHeader(title: "Library") }
            .listItemTint(sidebarTint)
            Section {
                row(.shows) { Label("Your Shows", systemImage: "mic") }
                row(.episodes) { Label("Your Episodes", systemImage: "bookmark") }
            } header: { SectionHeader(title: "Podcasts") }
            .listItemTint(sidebarTint)
            Section {
                ForEach(model.settings.mixes) { mix in
                    let cover = model.settings.mixCover(mix.uri)
                    row(.mix(mix)) {
                        Label {
                            Text(mix.name).lineLimit(1)
                        } icon: {
                            if cover.isEmpty { Image(systemName: "music.note.list") } else { ArtworkView(images: cover, size: 18, corner: 3) }
                        }
                    }
                    .contextMenu {
                        MenuBarToggleButton(item: QuickPlayItem(uri: mix.uri, name: mix.name, images: cover))
                        Button("Remove Mix") { model.settings.removeMix(mix) }
                    }
                }
                Button { addingMix = true } label: { Label("Paste a mix link", systemImage: "plus") }
                    .buttonStyle(.plain).themed(.secondary)
            } header: { SectionHeader(title: "Mixes") }
            .listItemTint(sidebarTint)
            Section {
                ForEach(library.playlists) { p in
                    row(.playlist(p)) { Label { Text(p.name).lineLimit(1) } icon: { ArtworkView(images: p.images, size: 18, corner: 3) } }
                        .contextMenu { MenuBarToggleButton(item: QuickPlayItem(uri: p.uri, name: p.name, images: p.images)) }
                }
            } header: { SectionHeader(title: "Playlists") }
            .listItemTint(sidebarTint)
        }
        .font(theme.isSystem ? nil : theme.isPlaylistList ? theme.listFont() : theme.font(.body)) // System keeps the user's sidebar size preference
        .modifier(DenseSidebarRows(dense: theme.isPlaylistList))
        .scrollContentBackground(theme.isSystem ? .automatic : .hidden)
        .tint(theme.isSystem ? nil : theme.accent) // sidebar icons follow the theme, not the app's accent colour
        .background {
            if !theme.isSystem {
                Group {
                    // The column sits on an AppKit vibrancy view: an opaque fill keeps the skin's look intact.
                    if let material = theme.style?.materials[.sidebar] { MaterialFill(material: material) } else { theme.surface }
                }
                .ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .top) {
            if theme.style?.frame != nil { SkinSearchField(focus: searchFocus).padding(.horizontal, 8).padding(.vertical, 6) }
        }
        .safeAreaInset(edge: .bottom) {
            Button { creatingPlaylist = true } label: { Label("New Playlist", systemImage: "plus") }
                .buttonStyle(.plain).themed(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .themedSurface(.inset) // already on the sidebar's fill: no second tint over a backdrop
                // Rows scroll under this bar: with a recipe it's the sidebar's own fill, so they don't show through.
                .background { if let m = theme.style?.materials[.sidebar] { MaterialFill(material: m) } }
                .overlay(alignment: .top) { ThemedDivider() }
        }
        .sheet(isPresented: $addingMix) { AddMixSheet() }
        .sheet(isPresented: $creatingPlaylist) { NewPlaylistSheet(track: nil) }
    }

    /// Sidebar icons follow the theme's accent: a sidebar colours them with its own item tint, not `.tint`.
    var sidebarTint: ListItemTint? { theme.isSystem ? nil : .fixed(theme.accent) }

    /// A sidebar row: a button that opens `route`, highlighted by the theme when selected.
    func row<Content: View>(_ route: Route, @ViewBuilder label: () -> Content) -> some View {
        Button { model.route = route } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SidebarRowText()) // System keeps the native sidebar icon tint
        .accessibilityAddTraits(model.route == route ? .isSelected : [])
        .themedRow(selected: model.route == route, hovering: false)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
    }
}

/// A Winamp library's rows are as dense as its playlist; otherwise the user's sidebar size preference stands.
private struct DenseSidebarRows: ViewModifier {
    let dense: Bool
    func body(content: Content) -> some View {
        if dense { content.environment(\.sidebarRowSize, .small) } else { content }
    }
}

/// Theme text color for sidebar rows; nothing on System.
private struct SidebarRowText: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        if theme.isSystem { content } else { content.foregroundStyle(theme.text) }
    }
}

struct AddMixSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var name = ""
    @State private var invalid = false

    var body: some View {
        Form {
            Text("In Spotify, open a Daily Mix, choose Share → Copy link, and paste it here.")
                .themed(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Link", text: $link, prompt: Text("https://open.spotify.com/playlist/…"))
            TextField("Name", text: $name, prompt: Text("Daily Mix 1"))
            if invalid { Text("That isn't a Spotify playlist link.").foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(theme.isSystem ? .automatic : .hidden)
        .themedSurface(.raised)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add Mix") { if model.settings.addMix(link: link, name: name) { dismiss() } else { invalid = true } }
            }
        }
    }
}

struct NewPlaylistSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let track: Track?
    @State private var name = ""

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("My playlist"))
            if let track { Text("“\(track.name)” will be added.").themed(.secondary) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(theme.isSystem ? .automatic : .hidden)
        .themedSurface(.raised)
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Playlist") {
                    let name = name.trimmingCharacters(in: .whitespaces)
                    Task {
                        if let p = await model.library.createPlaylist(named: name, adding: track) { model.route = .playlist(p) }
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

#Preview("Main window, light") { MainWindow().environment(AppModel()).frame(width: 1180, height: 720).preferredColorScheme(.light) }
#Preview("Main window, dark") { MainWindow().environment(AppModel()).frame(width: 1180, height: 720).preferredColorScheme(.dark) }
