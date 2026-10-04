import GreedifyKit
import SwiftUI

/// Right-click item that adds `item` to the menu-bar popover, or takes it out again.
struct MenuBarToggleButton: View {
    @Environment(AppModel.self) private var model
    let item: QuickPlayItem

    var body: some View {
        if model.settings.isInMenuBar(item.uri) {
            Button("Remove from Menu Bar", systemImage: "menubar.arrow.down.rectangle") { model.settings.removeFromMenuBar(item.uri) }
        } else {
            Button("Add to Menu Bar", systemImage: "menubar.arrow.up.rectangle") { model.settings.addToMenuBar(item) }
        }
    }
}

/// The popover's added lists and songs: a click plays one, a drag reorders them.
struct QuickPlayList: View {
    @Environment(AppModel.self) private var model
    /// The row being dragged; the others make way for it as it passes over them.
    @State private var dragging: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.settings.quickPlay.enumerated()), id: \.element.id) { index, item in
                QuickPlayRow(item: item, number: index + 1)
                    .onDrag {
                        dragging = item.uri
                        return NSItemProvider(object: item.uri as NSString)
                    }
                    .onDrop(of: [.text], delegate: QuickPlayDrop(target: item.uri, settings: model.settings, dragging: $dragging))
            }
        }
    }
}

/// Moves the dragged row to the row it enters, so the list shows the new order while dragging.
private struct QuickPlayDrop: DropDelegate {
    let target: String
    let settings: AppSettings
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, let index = settings.quickPlay.firstIndex(where: { $0.uri == target }) else { return }
        withAnimation(.snappy(duration: 0.2)) { settings.moveInMenuBar(dragging, to: index) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// A popover row: a click plays it. An added item's menu removes it; a search result's opens its page instead.
struct QuickPlayRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let item: QuickPlayItem
    /// A search result: "Show in Greedify" opens this page, and the item can be added to the menu bar.
    var route: Route?
    /// The row's number in a playlist-editor list (`1. Mix 2`); search results have none.
    var number: Int?

    var body: some View {
        Button { Task { await model.player.play(item.playRequest) } } label: {
            if theme.isPlaylistList { playlistLine } else { card }
        }
        .buttonStyle(.plain)
        .themedRow(selected: isPlaying && !theme.isPlaylistList, hovering: hovering)
        .onHover { hovering = $0 }
        .hoverHelp("Play \(name)")
        .contextMenu { menu }
    }

    /// Winamp's playlist editor: one dense line, `1. Mix 2`, a song as `Artist - Title`, what a result is (Artist,
    /// Album · …) dim on the right; the playing one in the playing colour.
    private var playlistLine: some View {
        let ink = isPlaying ? theme.accent : theme.text
        let title = item.isSong && !(item.subtitle ?? "").isEmpty ? "\(item.subtitle!) - \(name)" : name
        return HStack(spacing: 6) {
            if let number { Text("\(number).").monospacedDigit().frame(width: 22, alignment: .trailing) }
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if !item.isSong, let subtitle = item.subtitle { Text(subtitle).lineLimit(1).foregroundStyle(theme.textSecondary).fixedSize() }
        }
        .font(theme.listFont(weight: isPlaying ? .semibold : .regular))
        .foregroundStyle(ink)
        .padding(.horizontal, 4)
        .frame(height: theme.playlistRowHeight)
        .contentShape(Rectangle())
    }

    private var card: some View {
            HStack(spacing: 8) {
                if item.images.isEmpty {
                    Image(systemName: item.isSong ? "music.note" : item.uri.hasPrefix("spotify:artist:") ? "music.mic" : "music.note.list")
                        .frame(width: 22, height: 22)
                } else {
                    ArtworkView(images: item.images, size: 22, corner: 3)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).lineLimit(1)
                    if let subtitle = item.subtitle { Text(subtitle).themedFont(.caption).themed(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if isPlaying { Image(systemName: "speaker.wave.2.fill").themedFont(.caption).foregroundStyle(theme.accent) }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var menu: some View {
            if let route {
                Button("Show in Greedify", systemImage: "macwindow") { model.open(route) }
                MenuBarToggleButton(item: item)
            } else {
                let items = model.settings.quickPlay
                let index = items.firstIndex { $0.uri == item.uri } ?? 0
                Button("Move to Top", systemImage: "arrow.up.to.line") { move(to: 0) }.disabled(index == 0)
                Button("Move Up", systemImage: "arrow.up") { move(to: index - 1) }.disabled(index == 0)
                Button("Move Down", systemImage: "arrow.down") { move(to: index + 1) }.disabled(index == items.count - 1)
                Divider()
                Button("Remove from Menu Bar", systemImage: "minus.circle") { model.settings.removeFromMenuBar(item.uri) }
            }
    }

    func move(to index: Int) { withAnimation(.snappy(duration: 0.2)) { model.settings.moveInMenuBar(item.uri, to: index) } }

    /// A playlist renamed since it was added shows its current name.
    var name: String { model.library.playlists.first { $0.uri == item.uri }?.name ?? item.name }

    var isPlaying: Bool {
        let player = model.player
        guard let track = player.track else { return false }
        return item.isSong ? track.uri == item.uri : player.lastContextURI == item.uri
    }
}

/// The popover's search: a field, and while it holds a query, a few results in place of the added items.
struct QuickSearchField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    /// Focus the field as it appears (the popover's search button opens it).
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var search = model.quickSearch
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").themed(.secondary)
            TextField("Search Spotify", text: $search.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { search.query = "" }
            if search.isSearching {
                ProgressView().controlSize(.mini)
            } else if !search.query.isEmpty {
                Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).themed(.secondary).iconLabel("Clear Search")
            }
        }
        .modifier(QuickSearchLook())
        .background { Button("") { focused = true }.keyboardShortcut("f").hidden() }
        .onAppear { if autofocus { focused = true } }
    }
}

/// The search field's frame: a framed skin's sunken LCD, in its colours (as the window's sidebar field), else a soft
/// rounded box.
private struct QuickSearchLook: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        if theme.style?.frame != nil, let lcd = theme.style?.lcd {
            content
                .font(theme.listFont())
                .foregroundStyle(lcd.text.map { Color($0) } ?? theme.text)
                .tint(lcd.text.map { Color($0) } ?? theme.text)
                .padding(.horizontal, 7).frame(height: 22)
                .recipeSurface(lcd.material ?? .solid(.black), bevel: lcd.bevel, radius: CGFloat(lcd.radius ?? 0))
        } else {
            content
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.isSystem ? Color.primary.opacity(0.06) : theme.surface))
        }
    }
}

/// The popover's search results, scrolling past 320 pt so the popover never grows taller than that.
struct QuickSearchResults: View {
    @Environment(AppModel.self) private var model
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let search = model.quickSearch
        let results = search.quickResults
        if results.isEmpty {
            if !search.isSearching {
                Text(search.lastError == nil ? "No results" : "Search isn't available right now")
                    .themed(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { QuickPlayRow(item: $0.item, route: route(for: $0)) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(320, contentHeight))
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    func route(for result: QuickSearchResult) -> Route? {
        switch result {
        case .song(let track): Album(of: track).map(Route.album)
        case .artist(let artist): .artist(artist)
        case .album(let album): .album(album)
        case .playlist(let playlist): .playlist(playlist)
        }
    }
}
