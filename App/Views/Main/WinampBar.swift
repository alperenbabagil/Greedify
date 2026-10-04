import GreedifyKit
import SwiftUI

/// A curated skin's player bar: a Winamp main window at our width (curated skins spec §2.3). An LCD block with the
/// time, a title strip with the scrolling title and the artist, a full-width seek bar, then the buttons.
struct WinampBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings
    @State private var showQueue = false
    /// Follows the bar's width (AdaptiveLayout): the volume folds into a button, then the bar becomes two rows.
    @State private var mode: AdaptiveLayout.BarMode = .wide
    /// The bar's width and its right-hand group's measured widths decide the mode (AdaptiveLayout.BarMetrics).
    @State private var width: CGFloat = 0
    @State private var metrics = AdaptiveLayout.BarMetrics(chrome: 348, wideExtras: 330, mediumExtras: 170) // 300 transport + 2 × 12 spacing + 2 × 12 padding
    /// Each group glides to its place when the bar switches between one row and two.
    @Namespace private var space

    var body: some View {
        let style = theme.style
        Group {
            if mode == .compact {
                // Two rows: the display and the extras, then the transport beside the seek bar.
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        display(maxWidth: .infinity).matchedGeometryEffect(id: "display", in: space)
                        measuredExtras.matchedGeometryEffect(id: "extras", in: space)
                    }
                    HStack(spacing: 12) {
                        controls.matchedGeometryEffect(id: "controls", in: space)
                        WinampSeek().matchedGeometryEffect(id: "seek", in: space)
                    }
                }
            } else {
                // One row: display on the left, controls at the exact centre (equal flexible sides), extras on the right.
                HStack(spacing: 12) {
                    display(maxWidth: 300).matchedGeometryEffect(id: "display", in: space)
                        .frame(minWidth: mode == .wide ? 180 : 140, maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 6) {
                        controls.matchedGeometryEffect(id: "controls", in: space)
                        WinampSeek().matchedGeometryEffect(id: "seek", in: space)
                    }
                    .frame(minWidth: 300, idealWidth: 440, maxWidth: 440)
                    .layoutPriority(1)
                    measuredExtras.matchedGeometryEffect(id: "extras", in: space)
                        .frame(minWidth: mode == .wide ? 180 : 140, maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(height: CGFloat(style?.bar?.height ?? 88) + (mode == .compact ? 40 : 0))
        .themedSurface(.bar)
        .overlay { if let bevel = style?.bevels[.bar] { BevelFrame(bevel: bevel) } }
        // Width only: the modes change the bar's height, never its width, so this can't feed back.
        .onGeometryChange(for: CGFloat.self) { $0.size.width.rounded() } action: { width = $0; updateMode() }
    }

    /// The cover and the LCD with the time and the title.
    private func display(maxWidth: CGFloat) -> some View {
        let player = model.player
        return HStack(spacing: 8) {
            if theme.style?.bar?.artwork ?? true {
                AlbumLink(track: player.track) {
                    ArtworkView(images: player.track?.album?.images ?? [], size: 56, corner: 2).accessibilityLabel(Text("Artwork"))
                }
            }
            LCDPanel {
                // Under ~1100 pt the display is too narrow for both, and the title keeps the room; the compact bar
                // gives the display a whole row. Only the LCD's content changes, never its width: no feedback.
                if let colors = theme.style?.bar?.analyser, width >= 1100 || mode == .compact {
                    // Winamp's left block: the time over the analyser; the title and readouts beside it.
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            WinampTime(height: 16)
                            WinampAnalyser(colors: colors).frame(height: 18)
                        }
                        .frame(width: 76)
                        titleColumn
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        WinampTime(height: 16)
                        titleColumn
                    }
                }
            }
            .frame(maxWidth: maxWidth)
        }
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            WinampTitle(placeholder: "")
            if theme.style?.bar?.readouts == true { WinampReadouts() }
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
        return HStack(spacing: 8) {
            Button { Task { await player.setShuffle(!(player.state?.shuffleState ?? false)) } } label: { Image(systemName: "shuffle") }
                .iconLabel("Shuffle", hint: player.state?.shuffleState == true ? "Turn shuffle off" : "Turn shuffle on")
                .accessibilityValue(Text(player.state?.shuffleState == true ? "On" : "Off"))
                .skinnedControl(.button, active: player.state?.shuffleState == true)
            // In the skin's recessed channel when it has one (Classified).
            if theme.style?.bar?.transport == .winamp {
                if theme.style?.bar?.transportWell != nil { WinampTransport().recessed(radius: 16) } else { WinampTransport() }
            } else {
                TransportControls()
            }
            Button { Task { await player.setRepeat(nextRepeat(player.state?.repeatState ?? .off)) } } label: {
                Image(systemName: player.state?.repeatState == .track ? "repeat.1" : "repeat")
            }
            .iconLabel("Repeat", hint: "Change repeat: off, all, one")
            .accessibilityValue(Text(repeatValue(player.state?.repeatState)))
            .skinnedControl(.button, active: (player.state?.repeatState ?? .off) != .off)
        }
    }

    /// Like, lyrics, queue, device, volume and settings; short of room, the volume is a button.
    private var extras: some View {
        @Bindable var model = model
        // Outlined buttons' halos reach past their frames: more room, or the device box touched its neighbours.
        return HStack(spacing: theme.style?.button?.outline != nil ? 12 : 8) {
            if let track = model.player.track { LikeButton(track: track, skinned: true) }
            Button { withAnimation(.layoutChange) { model.showLyrics.toggle() } } label: { Image(systemName: "quote.bubble") }
                .iconLabel("Lyrics", hint: lyricsHint(model)).skinnedControl(.small, active: model.showLyrics)
                .disabled(!model.windowFitsLyrics) // hidden in a narrow window; widen it to show them
            Button { showQueue.toggle() } label: { Image(systemName: "list.bullet") }
                .iconLabel("Queue", hint: "Show the queue").skinnedControl(.small)
                .popover(isPresented: $showQueue) { QueuePopover() }
            LCDPanel { DevicePicker(iconOnly: true).environment(\.theme, lcdTheme) }.frame(width: 44, height: 24)
            VolumeControl(collapsed: mode != .wide, width: 80)
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .iconLabel("Settings", hint: "Open Settings").skinnedControl(.small)
        }
    }

    /// The theme with the LCD's text as its accent, for text drawn inside an LCD panel.
    var lcdTheme: ResolvedTheme {
        var t = theme
        t.accent = Color(theme.style?.lcd?.text ?? .white)
        return t
    }

    func nextRepeat(_ m: RepeatMode) -> RepeatMode {
        switch m { case .off: .context; case .context: .track; case .track: .off }
    }
}

/// The LCD block: play state and the elapsed time in the skin's digits.
struct WinampTime: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var height: CGFloat = 24

    var body: some View {
        let player = model.player
        TimelineView(.playback(player.isPlaying)) { context in
            HStack(spacing: 8) {
                Image(systemName: player.isPlaying ? "play.fill" : player.track == nil ? "stop.fill" : "pause.fill")
                    .font(.system(size: height * 0.4))
                    .foregroundStyle(Color(theme.style?.lcd?.info ?? .white))
                LCDDigits(text: formatTime(player.positionMs(at: context.date)), height: height)
                Spacer(minLength: 0)
            }
        }
    }
}

/// The title strip: the scrolling title and, under it, the artist (or show) links.
struct WinampTitle: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let placeholder: String

    var body: some View {
        let player = model.player
        VStack(alignment: .leading, spacing: 3) {
            AlbumLink(track: player.track) { LCDTitle(text: player.track?.name ?? "Nothing playing") }
                .frame(height: 16)
            ArtistLinks(track: player.track, placeholder: placeholder)
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.style?.lcd?.info ?? .white))
        }
    }
}

/// The full-width seek bar; the time sits in the LCD block, as in Winamp.
struct WinampSeek: View {
    @Environment(AppModel.self) private var model
    @State private var dragMs: Double?

    var body: some View {
        let player = model.player
        let duration = Double(player.track?.durationMs ?? 1)
        TimelineView(.playback(player.isPlaying)) { context in
            let pos = dragMs ?? Double(player.positionMs(at: context.date))
            ThemedSlider(value: Binding(get: { pos }, set: { dragMs = $0 }), range: 0...max(1, duration), skin: .seek,
                         label: "Position", valueText: "\(formatTime(Int(pos))) of \(formatTime(Int(duration)))") { editing in
                if !editing, let ms = dragMs { Task { await player.seek(toMs: Int(ms)); dragMs = nil } }
            }
        }
        .disabled(player.track == nil || model.isOffline)
    }
}

/// The popover's player for a curated skin: a compact LCD, the seek bar and the transport.
struct WinampPopoverPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        let player = model.player
        let style = theme.style
        VStack(spacing: 8) {
            LCDPanel {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        WinampTime(height: 20)
                        if let colors = style?.bar?.analyser { WinampAnalyser(colors: colors).frame(width: 76, height: 16) }
                    }
                    WinampTitle(placeholder: "Press play to start")
                    if style?.bar?.readouts == true { WinampReadouts() }
                }
            }
            .frame(height: style?.bar?.readouts == true ? 94 : 84)
            WinampSeek()
            if style?.bar?.transport == .winamp {
                // As in the bar: shuffle, the transport in its channel when the skin has one, repeat.
                HStack(spacing: 6) {
                    Button { Task { await player.setShuffle(!(player.state?.shuffleState ?? false)) } } label: { Image(systemName: "shuffle") }
                        .iconLabel("Shuffle", hint: player.state?.shuffleState == true ? "Turn shuffle off" : "Turn shuffle on")
                        .accessibilityValue(Text(player.state?.shuffleState == true ? "On" : "Off"))
                        .skinnedControl(.small, active: player.state?.shuffleState == true)
                    if style?.bar?.transportWell != nil { WinampTransport().recessed(radius: 16) } else { WinampTransport() }
                    Button { Task { await player.setRepeat(nextRepeat(player.state?.repeatState ?? .off)) } } label: {
                        Image(systemName: player.state?.repeatState == .track ? "repeat.1" : "repeat")
                    }
                    .iconLabel("Repeat", hint: "Change repeat: off, all, one")
                    .accessibilityValue(Text(repeatValue(player.state?.repeatState)))
                    .skinnedControl(.small, active: (player.state?.repeatState ?? .off) != .off)
                }
                .buttonStyle(.plain)
                .disabled(model.isOffline)
                .frame(maxWidth: .infinity)
            } else {
                TransportControls(large: true).frame(maxWidth: .infinity)
            }
        }
    }

    func nextRepeat(_ m: RepeatMode) -> RepeatMode {
        switch m { case .off: .context; case .context: .track; case .track: .off }
    }
}

/// Winamp's button row: previous, play, pause, stop, next, together (winamp window spec). Play only plays and pause
/// toggles, as Winamp's do; stop pauses and goes back to the start. No eject: with no files to open it had no job.
struct WinampTransport: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var large = false

    var body: some View {
        let player = model.player
        // A skin with outlined buttons (Classified) has them a little apart and at its buttons' proportions.
        let outlined = theme.style?.button?.outline != nil
        let size: SkinControlSize = large ? .largeButton : outlined ? .button : .small
        HStack(spacing: CGFloat(theme.style?.button?.spacing ?? 0)) {
                if player.track?.isEpisode == true {
                    Button { Task { await player.skipBack() } } label: { Image(systemName: "gobackward.15") }
                        .iconLabel("Back 15 Seconds", hint: "Skip back 15 seconds").skinnedControl(size)
                }
                Button { Task { await player.previous() } } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel(Text("Previous")).skinnedControl(size)
                Button { Task { if !player.isPlaying { await player.togglePlayPause() } } } label: { Image(systemName: "play.fill") }
                    .accessibilityLabel(Text("Play")).skinnedControl(size, active: player.isPlaying)
                Button { Task { if player.track != nil { await player.togglePlayPause() } } } label: { Image(systemName: "pause.fill") }
                    .accessibilityLabel(Text("Pause")).skinnedControl(size, active: player.track != nil && !player.isPlaying)
                Button { Task { await stop() } } label: { Image(systemName: "stop.fill") }
                    .accessibilityLabel(Text("Stop")).skinnedControl(size)
                Button { Task { await player.next() } } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel(Text("Next")).skinnedControl(size)
                if player.track?.isEpisode == true {
                    Button { Task { await player.skipForward() } } label: { Image(systemName: "goforward.30") }
                        .iconLabel("Forward 30 Seconds", hint: "Skip forward 30 seconds").skinnedControl(size)
                }
        }
        .buttonStyle(.plain)
        .disabled(model.isOffline)
    }

    private func stop() async {
        let player = model.player
        if player.isPlaying { await player.togglePlayPause() }
        if player.track != nil { await player.seek(toMs: 0) }
    }
}

/// The analyser: a still spectrum per song (`Analyser.bars`), drawn once per song and play state, never per frame.
/// Dimmed when paused, empty when nothing is loaded.
struct WinampAnalyser: View {
    @Environment(AppModel.self) private var model
    /// Top to bottom.
    let colors: [ThemeColor]

    var body: some View {
        AnalyserBars(seed: model.player.track?.id, playing: model.player.isPlaying, colors: colors).equatable()
    }
}

/// The bars as plain colour layers: each bar is the ramp's bands, top to bottom, cut off at its height, as Winamp
/// colours its analyser by row. A `Canvas` here took ~50 MB for a moment every few seconds (whenever the scrolling
/// title beside it moved on), even when nothing in it changed. Compared by its inputs, so a poll doesn't rebuild it.
private struct AnalyserBars: View, Equatable {
    let seed: String?
    let playing: Bool
    let colors: [ThemeColor]
    static let count = 19

    var body: some View {
        let bars = seed.map { Analyser.bars(seed: $0, count: Self.count) } ?? []
        let peak = Color(colors.first ?? .white).opacity(0.75)
        GeometryReader { geo in
            let full = geo.size.height - 3 // room for the peaks
            let band = full / CGFloat(max(1, colors.count))
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                    let h = full * CGFloat(playing ? value : value * 0.35)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if playing { peak.frame(height: 1); Spacer().frame(height: 2) }
                        ForEach(Array(colors.enumerated()), id: \.offset) { i, color in
                            // Band i counts down from the top; it shows only the part under the bar's height.
                            let bottom = CGFloat(colors.count - 1 - i) * band
                            Color(color).frame(height: min(max(h - bottom, 0), band))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .opacity(playing ? 1 : 0.6)
        .accessibilityHidden(true)
    }
}

/// The LCD's small print: bitrate, sample rate and channels, lit while playing (Winamp's kbps / kHz / stereo).
/// The bitrate is the one librespot was given.
struct WinampReadouts: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        let ink = Color(theme.style?.lcd?.info ?? .white).opacity(model.player.isPlaying ? 1 : 0.35)
        // One line, so one drawing: each readout as its own pixel canvas cost a backing buffer apiece.
        readout("\(model.settings.bitrate) KBPS   44 KHZ   STEREO", ink)
        // Never wider than the LCD offers: fixed-width readouts pushed the display into the seek bar at 900 pt.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(model.settings.bitrate) kbps, 44 kHz, stereo"))
    }

    @ViewBuilder private func readout(_ text: String, _ ink: Color) -> some View {
        if let font = theme.pixelFont {
            PixelText(text: text, font: font, scale: 1, ink: ink, fixedWidth: true).fixedSize()
        } else {
            Text(text).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ink).fixedSize()
        }
    }
}

extension View {
    /// Set into the bar's recessed channel (`bar.transportWell`): darker steel with a shadowed top edge and a lit
    /// bottom one, as the original Classified's button row sits.
    func recessed(radius: CGFloat) -> some View { modifier(Recessed(radius: radius)) }
}

private struct Recessed: ViewModifier {
    @Environment(\.theme) private var theme
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let style = theme.style
        let fill = style?.bar?.transportWell ?? style?.materials[.bar]
        let dark = Color.black.opacity(0.45), light = Color.white.opacity(0.7)
        content
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background { if let fill { MaterialFill(material: fill).clipShape(shape) } }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [dark, light], startPoint: .top, endPoint: .bottom),
                                   lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
