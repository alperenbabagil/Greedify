import GreedifyKit
import SwiftUI

/// Menu-bar popover (approved mockup: docs/superpowers/specs/mockups/popover.html).
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.theme) private var theme
    @State private var restarting = false
    /// The section the action row has expanded, if any; one at a time keeps the popover short.
    @State private var section: Section?

    enum Section { case search, device, volume, lyrics }

    init(section: Section? = nil) { _section = State(initialValue: section) }

    /// A search with a query replaces the quick-play list, as before.
    var searching: Bool {
        section == .search && !model.quickSearch.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A framed skin's popover is the original's stacked windows: a main window, the button strip, a playlist window.
    var framed: Bool { theme.style?.frame != nil && !model.needsSetup }

    var body: some View {
        if framed { winampBody } else { plainBody }
    }

    /// Winamp's stacked windows in miniature: the `WINAMP` main window (LCD, seek bar, transport), the action buttons
    /// on the frame between, then the `WINAMP PLAYLIST` window with the section and the quick-play list (winamp
    /// window spec).
    private var winampBody: some View {
        VStack(spacing: 0) {
            WinampPopoverPlayer()
                .padding(8)
                .themedSurface(.bar)
                .winampFrame("")
            actionRow
                .padding(.horizontal, 10).padding(.vertical, 7)
            if section != nil || !model.settings.quickPlay.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if let section {
                        sectionContent(section)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if !searching, !model.settings.quickPlay.isEmpty {
                        if section != nil { ThemedDivider() }
                        QuickPlayList()
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .themedSurface(.content)
                .winampFrame("Playlist")
            }
        }
        .padding(6)
        .frame(width: 300)
        .background { if let face = theme.style?.frame?.face { MaterialFill(material: face) } else { theme.raised } }
        .modifier(BannerOverlay())
        .onAppear { model.player.surfaceAppeared("popover") }
        .onDisappear {
            model.player.surfaceDisappeared("popover"); model.quickSearch.query = ""
            if section == .search { section = nil }
        }
    }

    private var plainBody: some View {
        let player = model.player
        return VStack(alignment: .leading, spacing: 14) {
            if model.needsSetup {
                setupPrompt
            } else {
                if theme.isWinamp {
                    WinampPopoverPlayer()
                } else {
                    HStack(spacing: 12) {
                        AlbumLink(track: player.track) {
                            ArtworkView(images: player.track?.album?.images ?? [], size: 64, corner: theme.artworkRadius * 2).accessibilityLabel(Text("Artwork"))
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            AlbumLink(track: player.track) {
                                Text(player.track?.name ?? "Nothing playing").font(.headline).lineLimit(1)
                            }
                            ArtistLinks(track: player.track, placeholder: "Press play to start")
                                .themedFont(.subheadline).themed(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let track = player.track { LikeButton(track: track).font(.title3) }
                    }
                    ProgressBar()
                    TransportControls(large: true).frame(maxWidth: .infinity)
                }
                ThemedDivider()
                actionRow
                if let section {
                    sectionContent(section)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !searching, !model.settings.quickPlay.isEmpty {
                    ThemedDivider()
                    QuickPlayList()
                }
            }
            if model.needsSetup {
                ThemedDivider()
                HStack {
                    Button("Open Greedify") { model.showMainWindow() }
                        .buttonStyle(.plain).foregroundStyle(theme.accent).fontWeight(.medium)
                    Spacer()
                    quitButton.buttonStyle(.plain)
                }
                .themed(.secondary)
            }
        }
        .padding(16)
        .frame(width: 300)
        .themedSurface(.raised)
        .modifier(BannerOverlay())
        .onAppear { player.surfaceAppeared("popover") }
        // A closed popover drops its search and the results' artwork with it.
        .onDisappear {
            player.surfaceDisappeared("popover"); model.quickSearch.query = ""
            if section == .search { section = nil }
        }
    }

    /// Search, device, volume and lyrics expand their sections (a second click collapses); then the window and Quit.
    var actionRow: some View {
        let offline = model.player.isLocalDeviceOnline == false && !model.player.isConnectingSpeaker
        return HStack(spacing: framed ? 8 : 14) {
            actionButton(.search, symbol: "magnifyingglass", label: "Search", hint: "Search Spotify (⌘F)")
                .background {
                    // ⌘F opens the search; once open, the field's own ⌘F focuses it.
                    if section != .search {
                        Button("") { withAnimation(.snappy(duration: 0.2)) { section = .search } }
                            .keyboardShortcut("f").hidden()
                    }
                }
            actionButton(.device, symbol: offline ? "exclamationmark.triangle" : "laptopcomputer", label: "Device",
                         hint: "Playing on \(deviceName). Click to choose another device.")
            actionButton(.volume, symbol: model.player.state?.device?.volumePercent == 0 ? "speaker.slash" : "speaker.wave.2",
                         label: "Volume", hint: "Change the volume")
            actionButton(.lyrics, symbol: "quote.bubble", label: "Lyrics", hint: "Show the lyrics")
            Spacer()
            Button { model.showMainWindow() } label: { Image(systemName: "macwindow") }
                .modifier(ActionButtonLook(framed: framed, open: false))
                .iconLabel("Open Greedify", hint: "Open the Greedify window")
            quitButton.modifier(ActionButtonLook(framed: framed, open: false))
        }
        .font(.body)
    }

    func actionButton(_ s: Section, symbol: String, label: String, hint: String) -> some View {
        let open = section == s
        return Button {
            withAnimation(.snappy(duration: 0.2)) { section = open ? nil : s }
            if open, s == .search { model.quickSearch.query = "" }
        } label: {
            Image(systemName: symbol).frame(width: 22, height: 20).contentShape(Rectangle())
        }
        .modifier(ActionButtonLook(framed: framed, open: open))
        .iconLabel(label, hint: open ? "Hide" : hint)
        .accessibilityAddTraits(open ? [.isSelected] : [])
    }

    var quitButton: some View {
        Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
            .iconLabel("Quit Greedify")
    }

    var deviceName: String { model.player.activeDevice?.name ?? model.settings.deviceName }

    @ViewBuilder func sectionContent(_ s: Section) -> some View {
        switch s {
        case .search:
            VStack(alignment: .leading, spacing: 10) {
                QuickSearchField(autofocus: true)
                if searching { QuickSearchResults() }
            }
        case .device:
            PopoverDevices()
            if model.player.isLocalDeviceOnline == false && !model.player.isConnectingSpeaker { speakerOffline }
        case .volume:
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").themed(.secondary)
                VolumeControl(collapsed: false, width: 212)
                Image(systemName: "speaker.wave.3.fill").themed(.secondary)
            }
            .font(.caption)
        case .lyrics:
            PopoverLyrics()
        }
    }

    /// Spec §7: the librespot device is missing from the device list.
    var speakerOffline: some View {
        HStack {
            Label("Mac speaker offline", systemImage: "exclamationmark.triangle").themed(.secondary)
            Spacer()
            if model.librespot.hasCredentials {
                Button(restarting ? "Restarting…" : "Restart") { Task { await restartSpeaker() } }
                    .controlSize(.small).disabled(restarting)
            } else {
                Button("Connect Again") { openWindow(id: WindowID.setup) }.controlSize(.small)
            }
        }
        .font(.callout)
    }

    /// Restarts librespot, then re-checks the device list while it comes back.
    func restartSpeaker() async {
        restarting = true
        defer { restarting = false }
        await model.librespot.restart()
        for delay in [3, 5, 5] {
            try? await Task.sleep(for: .seconds(delay))
            await model.player.refreshDevices()
            if model.player.isLocalDeviceOnline == true { return }
        }
    }

    var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.needsReauth ? "Spotify login expired" : "Greedify isn't set up yet").font(.headline)
            Text(model.needsReauth ? "Log in again to keep listening." : "Connect your Spotify account to start.")
                .themed(.secondary)
            Button(model.needsReauth ? "Log In Again" : "Set Up Greedify") { openWindow(id: WindowID.setup) }
                .themedButton(.primary, capsule: false)
        }
    }
}

/// An action-row button: a skin button in a framed skin (lit while its section is open), else a plain glyph.
private struct ActionButtonLook: ViewModifier {
    @Environment(\.theme) private var theme
    let framed: Bool
    let open: Bool

    func body(content: Content) -> some View {
        if framed {
            content.skinnedControl(.small, active: open)
        } else {
            content.buttonStyle(.plain).foregroundStyle(open ? theme.accent : theme.textSecondary)
        }
    }
}

#Preview("Popover, light") { PopoverView().environment(AppModel()).preferredColorScheme(.light) }
#Preview("Popover, dark") { PopoverView().environment(AppModel()).preferredColorScheme(.dark) }

/// The status item. Its first appearance at launch starts the app (and opens setup if needed).
struct MenuBarItem: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabelView(label: model.menuBarLabel, rateLimited: model.player.isRateLimited)
            .task {
                await model.launch()
                if model.needsSetup { openWindow(id: WindowID.setup) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .greedifyReopen)) { _ in
                if model.needsSetup { openWindow(id: WindowID.setup) } else { model.showMainWindow() }
            }
    }
}

/// The menu-bar item: icon, plus the current lyric line when enabled.
struct MenuBarLabelView: View {
    let label: MenuBarLabel
    let rateLimited: Bool

    var body: some View {
        let symbol = rateLimited ? "exclamationmark.circle" : "g.circle"
        if case .text(let text) = label {
            // Icon and lyric drawn together (see MenuBarLabelImage): visible and on one baseline.
            Image(nsImage: MenuBarLabelImage.make(symbol: symbol, text: text))
        } else {
            Image(systemName: symbol)
        }
    }
}
