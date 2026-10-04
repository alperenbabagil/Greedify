import GreedifyKit
import SwiftUI

/// Bottom player bar (spec §4.1).
struct PlayerBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings
    @State private var showQueue = false
    /// Follows the bar's width (AdaptiveLayout): the volume folds into a button, then the bar becomes two rows.
    @State private var mode: AdaptiveLayout.BarMode = .wide
    /// The bar's width and its right-hand group's measured widths decide the mode (AdaptiveLayout.BarMetrics).
    @State private var width: CGFloat = 0
    @State private var metrics = AdaptiveLayout.BarMetrics(chrome: 372, wideExtras: 330, mediumExtras: 170) // 300 transport + 2 × 20 spacing + 2 × 16 padding
    /// Each group glides to its place when the bar switches between one row and two.
    @Namespace private var space

    var body: some View {
        if theme.isWinamp { WinampBar() } else { classic }
    }

    /// The bar every theme without a curated skin uses.
    private var classic: some View {
        Group {
            if mode == .compact {
                // Two rows: what's playing and the extras, then the transport beside the seek bar.
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        trackInfo(artwork: 40).matchedGeometryEffect(id: "info", in: space)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        measuredExtras.matchedGeometryEffect(id: "extras", in: space)
                    }
                    HStack(spacing: 18) {
                        controls.matchedGeometryEffect(id: "controls", in: space)
                        ProgressBar().matchedGeometryEffect(id: "progress", in: space)
                    }
                }
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 20) {
                    trackInfo(artwork: 48).matchedGeometryEffect(id: "info", in: space)
                        // Equal flexible sides keep the controls at the exact centre, whatever each side holds.
                        .frame(minWidth: mode == .wide ? 180 : 140, maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 6) {
                        controls.matchedGeometryEffect(id: "controls", in: space)
                        ProgressBar().frame(maxWidth: 480).matchedGeometryEffect(id: "progress", in: space)
                    }
                    .frame(minWidth: 300, idealWidth: 460, maxWidth: 460)
                    .layoutPriority(1)
                    measuredExtras.matchedGeometryEffect(id: "extras", in: space)
                        .frame(minWidth: mode == .wide ? 180 : 140, maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: mode == .compact ? theme.playerBarHeight + 34 : theme.playerBarHeight)
        .themedSurface(.bar)
        .overlay(alignment: .top) { ThemedDivider() }
        // Width only: the modes change the bar's height, never its width, so this can't feed back.
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { width = $0; updateMode() }
    }

    /// Cover, title and artist, and the like button.
    private func trackInfo(artwork: CGFloat) -> some View {
        let player = model.player
        return HStack(spacing: 10) {
            AlbumLink(track: player.track) {
                ArtworkView(images: player.track?.album?.images ?? [], size: artwork, corner: theme.artworkRadius + 1).accessibilityLabel(Text("Artwork"))
            }
            VStack(alignment: .leading, spacing: 1) {
                AlbumLink(track: player.track) {
                    if let pixelFont = theme.pixelFont {
                        PixelText(text: player.track?.name ?? "Nothing playing", font: pixelFont)
                    } else {
                        Text(player.track?.name ?? "Nothing playing").fontWeight(.semibold).lineLimit(1)
                    }
                }
                ArtistLinks(track: player.track, placeholder: "").themedFont(.caption).themed(.secondary)
            }
            if let track = player.track { LikeButton(track: track, skinned: true) }
        }
    }

    /// The right-hand group, measured: its width in the current layout feeds the mode.
    private var measuredExtras: some View {
        extras.onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { w in
            if mode == .wide { metrics.wideExtras = w } else { metrics.mediumExtras = w }
            updateMode()
        }
    }

    private func updateMode() {
        guard width > 0 else { return }
        let next = metrics.mode(width: width, current: mode)
        if next != mode { withAnimation(.layoutChange) { mode = next } }
    }

    /// Shuffle, the transport and repeat.
    private var controls: some View {
        let player = model.player
        return HStack(spacing: 22) {
            Button { Task { await player.setShuffle(!(player.state?.shuffleState ?? false)) } } label: { Image(systemName: "shuffle") }
                .foregroundStyle(player.state?.shuffleState == true ? theme.accent : theme.textSecondary)
                .iconLabel("Shuffle", hint: player.state?.shuffleState == true ? "Turn shuffle off" : "Turn shuffle on")
                .accessibilityValue(Text(player.state?.shuffleState == true ? "On" : "Off"))
                .skinnedControl(.button, active: player.state?.shuffleState == true)
            TransportControls()
            Button { Task { await player.setRepeat(nextRepeat(player.state?.repeatState ?? .off)) } } label: {
                Image(systemName: player.state?.repeatState == .track ? "repeat.1" : "repeat")
            }
            .foregroundStyle((player.state?.repeatState ?? .off) == .off ? theme.textSecondary : theme.accent)
            .iconLabel("Repeat", hint: "Change repeat: off, all, one")
            .accessibilityValue(Text(repeatValue(player.state?.repeatState)))
            .skinnedControl(.button, active: (player.state?.repeatState ?? .off) != .off)
        }
        .buttonStyle(.plain)
    }

    /// Lyrics, queue, device, volume and settings. Short of room, the device shows as an icon and the volume as a button.
    private var extras: some View {
        @Bindable var model = model
        let wide = mode == .wide
        // Skin buttons are wider than plain icons: tighter spacing keeps the group inside its side.
        return HStack(spacing: theme.style?.button == nil ? 14 : 10) {
            Button { withAnimation(.layoutChange) { model.showLyrics.toggle() } } label: { Image(systemName: "quote.bubble") }
                .foregroundStyle(model.showLyrics ? theme.accent : theme.textSecondary).iconLabel("Lyrics", hint: lyricsHint(model))
                .skinnedControl(.small, active: model.showLyrics)
                .disabled(!model.windowFitsLyrics) // hidden in a narrow window; widen it to show them
            Button { showQueue.toggle() } label: { Image(systemName: "list.bullet") }
                .themed(.secondary).iconLabel("Queue", hint: "Show the queue")
                .skinnedControl(.small)
                .popover(isPresented: $showQueue) { QueuePopover() }
            DevicePicker(iconOnly: !wide)
            if wide { Image(systemName: "speaker.wave.2").themed(.secondary).accessibilityHidden(true) }
            VolumeControl(collapsed: !wide)
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .themed(.secondary).iconLabel("Settings", hint: "Open Settings")
                .skinnedControl(.small)
        }
        .buttonStyle(.plain)
    }

    func nextRepeat(_ m: RepeatMode) -> RepeatMode {
        switch m { case .off: .context; case .context: .track; case .track: .off }
    }
}

struct QueuePopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next").font(.headline)
            if model.player.upNext.isEmpty { Text("The queue is empty.").themed(.secondary) }
            ForEach(Array(model.player.upNext.prefix(20).enumerated()), id: \.offset) { _, t in
                HStack(spacing: 10) {
                    ArtworkView(images: t.album?.images ?? [], size: 30)
                    VStack(alignment: .leading) {
                        Text(t.name).lineLimit(1)
                        Text(t.artistLine).themedFont(.caption).themed(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .themedSurface(.raised)
        .task { await model.player.refreshQueue() }
    }
}

/// Lyrics panel: blurred artwork background with white text, or a solid theme background with the theme's lyrics color; current line bright (spec §4.1, §5).
struct LyricsPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// White over the blurred artwork; the theme's lyrics color in `solid` mode (spec §5).
    var ink: Color { theme.lyrics == .artwork ? .white : theme.lyricsText }

    /// Plain and "No lyrics" text. Over skin art the plan checked `lyricsText` itself, so it isn't dimmed further.
    func bodyInk(_ opacity: Double) -> Color {
        ink.opacity(opacity)
    }

    var body: some View {
        let player = model.player
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped() // the content only: a clip after the background cut it off under the toolbar (a grey band)
            .background {
                if theme.lyrics == .artwork {
                    // A background never sizes its parent, so the 600 pt artwork can't pin the window size.
                    // Blurred at radius 50, so a 96 px decode looks the same as 640 px and costs ~2% of it.
                    // Sized to the panel's longer side, opaque blur and a black base: a fixed 600 pt square left the
                    // window's light background showing as faded bands above and below on a tall panel.
                    GeometryReader { geo in
                        ArtworkView(images: player.track?.album?.images ?? [], size: max(geo.size.width, geo.size.height),
                                    corner: 0, decodePixels: 96)
                            .blur(radius: 50, opaque: true).saturation(1.3).scaleEffect(1.3)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .overlay(Color.black.opacity(0.28))
                    .background(Color.black)
                    .clipped()
                    .ignoresSafeArea()
                } else {
                    // Under the toolbar too, like the rest of the window; otherwise the window's grey shows there.
                    Group { if let m = theme.style?.materials[.lyrics] { MaterialFill(material: m) } else { theme.background } }.ignoresSafeArea()
                }
            }
            .environment(\.colorScheme, theme.lyrics == .artwork ? .dark : colorScheme)
    }

    @ViewBuilder var content: some View {
        switch model.lyrics {
        case .synced(let lines):
            // The current line comes from AppModel's label loop, which wakes only when it changes: a timeline here
            // rebuilt the whole panel four times a second (~14% CPU with the panel open).
            let current = model.lyricIndex
            ScrollViewReader { proxy in
                PageScrollView {
                    VStack(alignment: .leading, spacing: lineSpacing) {
                        header
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line.isGap ? "♪" : line.text)
                                .font(lineFont(22, weight: .bold))
                                .foregroundStyle(lineColor(i, current))
                                .id(i)
                                .onTapGesture { Task { await model.player.seek(toMs: line.timeMs) } }
                        }
                        footer
                    }
                    .padding(24)
                }
                .onChange(of: current) { _, i in
                    guard let i else { return }
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(i, anchor: .center) }
                }
                .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            }
        case .plain(let text):
            PageScrollView {
                VStack(alignment: .leading, spacing: lineSpacing) {
                    header
                    Text(text).font(lineFont(18, weight: .semibold)).foregroundStyle(bodyInk(0.85))
                    footer
                }
                .padding(24)
            }
        case .none:
            VStack { header; Spacer(); Text(model.player.track?.isEpisode == true ? "No lyrics for podcasts" : "No lyrics found").foregroundStyle(bodyInk(0.7)); Spacer() }.padding(24)
        }
    }

    /// The skin's lyric style (`text.lyrics`), else big bold lines.
    func lineFont(_ size: CGFloat, weight: Font.Weight) -> Font {
        guard let spec = theme.style?.text[.lyrics] else { return theme.font(size, weight: weight) }
        return LCDTitle.font(spec, theme: theme)
    }

    /// Small lyric lines sit closer together.
    var lineSpacing: CGFloat { theme.style?.text[.lyrics] == nil ? 16 : 8 }

    /// Solid mode dims with the theme's own secondary color: fading a dark theme color with opacity
    /// (tuned for white over artwork) left the lines at ~1.6:1 on black.
    func lineColor(_ i: Int, _ current: Int?) -> Color {
        guard theme.lyrics == .solid else { return ink.opacity(opacity(i, current)) }
        return i == current ? theme.accent : theme.textSecondary
    }

    func opacity(_ i: Int, _ current: Int?) -> Double {
        guard let current else { return 0.38 }
        return i == current ? 1 : (i < current ? 0.22 : 0.38)
    }

    var header: some View {
        HStack {
            Label(model.player.track?.name ?? "Lyrics", systemImage: "quote.bubble").font(.caption)
            Spacer()
            if case .synced = model.lyrics {
                Text("Synced").font(.caption2).padding(.horizontal, 8).padding(.vertical, 1)
                    .overlay(Capsule().stroke(ink.opacity(0.5)))
            }
        }
        .foregroundStyle(ink.opacity(0.8))
    }

    var footer: some View { Text("Lyrics from LRCLIB").font(.caption2).foregroundStyle(ink.opacity(0.6)).padding(.top, 20) }
}
