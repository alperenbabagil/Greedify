import GreedifyKit
import SwiftUI

/// Album art loaded through the shared `ImageCache`.
struct ArtworkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let images: [SpotifyImage]
    var size: CGFloat
    var corner: CGFloat = 4
    /// Longest side to decode to, in pixels; defaults to the on-screen size. Blurred backgrounds need far less.
    var decodePixels: Int?
    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?

    var body: some View {
        let pixels = decodePixels ?? Int((size * displayScale).rounded(.up))
        let url = images.best(minSide: pixels)?.url
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "music.note").themed(.secondary).font(.system(size: size * 0.35))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = model.images.cached(url, maxPixelSize: pixels)
            if image == nil { image = await model.images.image(for: url, maxPixelSize: pixels) }
        }
    }
}

func formatTime(_ ms: Int) -> String {
    let s = max(0, ms / 1000)
    return String(format: "%d:%02d", s / 60, s % 60)
}

func formatDuration(_ ms: Int) -> String {
    let minutes = ms / 60_000
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
}

/// Seek bar that follows the locally advanced position.
struct ProgressBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var dragMs: Double?

    var body: some View {
        let player = model.player
        let duration = Double(player.track?.durationMs ?? 1)
        TimelineView(.playback(player.isPlaying)) { context in
            let pos = dragMs ?? Double(player.positionMs(at: context.date))
            HStack(spacing: 8) {
                time(Int(pos))
                ThemedSlider(value: Binding(get: { pos }, set: { dragMs = $0 }), range: 0...max(1, duration), skin: .seek,
                             label: "Position", valueText: "\(formatTime(Int(pos))) of \(formatTime(Int(duration)))") { editing in
                    if !editing, let ms = dragMs {
                        Task { await player.seek(toMs: Int(ms)); dragMs = nil }
                    }
                }
                time(Int(duration))
            }
            .themedFont(.caption2)
            .themed(.secondary)
        }
        .disabled(player.track == nil || model.isOffline)
    }

    @ViewBuilder func time(_ ms: Int) -> some View {
        Text(formatTime(ms)).monospacedDigit()
    }
}

/// Previous / play-pause / next.
struct TransportControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var large = false

    var body: some View {
        let player = model.player
        // Five buttons while an episode plays: tighter, so the popover's 268 pt still fits (skin buttons are wider).
        let fiveButtons = player.track?.isEpisode == true
        HStack(spacing: fiveButtons ? (large ? (theme.style?.button != nil ? 10 : 20) : 14) : (large ? 40 : 22)) {
            if player.track?.isEpisode == true {
                Button { Task { await player.skipBack() } } label: { Image(systemName: "gobackward.15") }
                    .iconLabel("Back 15 Seconds", hint: "Skip back 15 seconds")
                    .skinnedControl(large ? .largeButton : .button)
            }
            Button { Task { await player.previous() } } label: { Image(systemName: "backward.fill") }
                .accessibilityLabel(Text("Previous")) // self-explanatory: no hover text
                .skinnedControl(large ? .largeButton : .button)
            Button { Task { await player.togglePlayPause() } } label: { playLabel(player.isPlaying) }
                .accessibilityLabel(Text(player.isPlaying ? "Pause" : "Play"))
                .skinnedControl(large ? .largePlay : .play)
            Button { Task { await player.next() } } label: { Image(systemName: "forward.fill") }
                .accessibilityLabel(Text("Next"))
                .skinnedControl(large ? .largeButton : .button)
            if player.track?.isEpisode == true {
                Button { Task { await player.skipForward() } } label: { Image(systemName: "goforward.30") }
                    .iconLabel("Forward 30 Seconds", hint: "Skip forward 30 seconds")
                    .skinnedControl(large ? .largeButton : .button)
            }
        }
        .font(.system(size: large ? 22 : 15))
        .buttonStyle(.plain)
        .disabled(model.isOffline)
    }

    /// A skin button draws its own face, so the label is just the glyph; otherwise the filled round (or bevel square) button.
    @ViewBuilder func playLabel(_ playing: Bool) -> some View {
        if theme.style?.button != nil {
            Image(systemName: playing ? "pause.fill" : "play.fill")
        } else {
            // Explicit colours: `.fill(.primary)` next to `.foregroundStyle(...)` resolved to the
            // same colour as the icon, making the button invisible.
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: large ? 20 : 14))
                .foregroundStyle(theme.isSystem ? Color(nsColor: .windowBackgroundColor) : theme.background)
                .frame(width: large ? 48 : 34, height: large ? 48 : 34)
                .background(playShape.fill(theme.isSystem ? Color(nsColor: .labelColor) : theme.text))
                .overlay { if theme.buttonStyle == .bevel && !theme.isSystem { BevelEdges(pressed: false, width: 1) } }
                .clipShape(playShape)
        }
    }

    /// Round, except on bevel themes, where it's a Winamp-style square.
    var playShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.buttonStyle == .bevel && !theme.isSystem ? theme.buttonRadius : 100)
    }
}

struct LikeButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let track: Track
    /// In the player bar the like button is a skin button; in song rows it stays a plain heart.
    var skinned = false
    /// The heart's colour, liked or not (a playlist-editor row draws it in the row's text colour).
    var ink: Color? = nil

    var body: some View {
        let liked = model.library.isLiked(track)
        let button = Button { Task { await model.library.toggleLike(track) } } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
        }
        .foregroundStyle(ink ?? (liked ? theme.accent : theme.textSecondary))
        .iconLabel(liked ? "Remove from Liked Songs" : "Save to Liked Songs")
        // A button style set on the button itself outranks one set outside it, so `.plain` only when not skinned.
        // With outlined buttons (Classified) it's the size of the bar's other extras, not a size bigger.
        if skinned, let spec = theme.style?.button { button.skinnedControl(spec.outline != nil ? .small : .button, active: liked) } else { button.buttonStyle(.plain) }
    }
}

/// Device list; picking one moves playback there.
struct DevicePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var prefix = ""
    /// Just the icon (a tight bar); the menu still names every device.
    var iconOnly = false

    var body: some View {
        let player = model.player
        Menu {
            ForEach(player.devices) { device in
                Button {
                    Task { await player.transfer(to: device) }
                } label: {
                    Label(device.name, systemImage: device.isActive ? "checkmark" : icon(for: device))
                }
            }
            if player.devices.isEmpty { Text("No devices found") }
        } label: {
            Group {
                if iconOnly { Image(systemName: "laptopcomputer") }
                else { Label(prefix + (player.activeDevice?.name ?? model.settings.deviceName), systemImage: "laptopcomputer") }
            }
            .foregroundStyle(theme.accent)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("Device"))
        .accessibilityValue(Text(player.activeDevice?.name ?? model.settings.deviceName))
        .hoverHelp("Playing on \(player.activeDevice?.name ?? model.settings.deviceName). Click to choose another device.")
        .fixedSize()
        .onAppear { Task { await player.refreshDevices() } }
    }

    func icon(for d: Device) -> String {
        switch d.type.lowercased() {
        case "smartphone": "iphone"
        case "speaker": "hifispeaker"
        case "tv": "tv"
        default: "laptopcomputer"
        }
    }
}

/// Non-blocking error banner (spec §7).
struct BannerOverlay: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if model.player.isConnectingSpeaker || model.banner != nil {
                HStack(spacing: 8) {
                    if model.player.isConnectingSpeaker {
                        ProgressView().controlSize(.small)
                        Text("Connecting to the Mac speaker…")
                    } else if let text = model.banner {
                        Text(text)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background {
                    if theme.isSystem { Capsule().fill(.regularMaterial) }
                    else { RoundedRectangle(cornerRadius: theme.buttonRadius).fill(theme.raised) }
                }
                .foregroundStyle(theme.text)
                .shadow(radius: 6, y: 2)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.banner)
        .animation(.snappy, value: model.player.isConnectingSpeaker)
    }
}

extension Date {
    /// A fixed start for periodic timelines. `.periodic(from: .now, …)` builds a new schedule on every body
    /// evaluation, which fires at once and re-evaluates the body again: the timelines ran ~190 times a second.
    static let timelineStart = Date()
}

/// The playing position's timeline: every half second while playing, a single fixed entry otherwise (a paused
/// position doesn't depend on the time), so nothing redraws while paused.
struct PlaybackSchedule: TimelineSchedule {
    var playing: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard playing else { return AnyIterator([Date.timelineStart].makeIterator()) }
        return AnyIterator(PeriodicTimelineSchedule(from: .timelineStart, by: 0.5).entries(from: startDate, mode: mode).makeIterator())
    }
}

extension TimelineSchedule where Self == PlaybackSchedule {
    static func playback(_ playing: Bool) -> PlaybackSchedule { PlaybackSchedule(playing: playing) }
}

/// The volume slider, or, when the player bar is short of room, a speaker button that opens it in a popover.
struct VolumeControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    var collapsed: Bool
    var width: CGFloat = 84
    @State private var volume: Double = 50
    @State private var open = false

    var body: some View {
        Group {
            if collapsed {
                Button { open.toggle() } label: { Image(systemName: volume == 0 ? "speaker.slash" : "speaker.wave.2") }
                    .themed(.secondary).iconLabel("Volume", hint: "Show the volume slider")
                    .skinnedControl(.small)
                    .popover(isPresented: $open) { slider.frame(width: 160).padding(14).themedSurface(.raised) }
            } else {
                slider.frame(width: width)
            }
        }
        .onChange(of: model.player.state?.device?.volumePercent, initial: true) { _, v in if let v { volume = Double(v) } }
    }

    var slider: some View {
        ThemedSlider(value: $volume, range: 0...100, skin: .volume, label: "Volume") { editing in
            if !editing { Task { await model.player.setVolume(Int(volume)) } }
        }
    }
}

extension View {
    /// An icon-only control: `label` names it for VoiceOver, and `hint` (shown on hover, and VoiceOver's hint)
    /// says what a click does. Without a hint the hover text is the label.
    func iconLabel(_ label: String, hint: String? = nil) -> some View {
        accessibilityLabel(Text(label)).hoverHelp(hint ?? label)
    }
}

/// The repeat button's state, as VoiceOver reads it.
func repeatValue(_ mode: RepeatMode?) -> String {
    switch mode ?? .off { case .off: "Off"; case .context: "All"; case .track: "One" }
}

/// The player bars' lyrics button: what a click does, or why it can't.
@MainActor func lyricsHint(_ model: AppModel) -> String {
    model.windowFitsLyrics ? (model.showLyrics ? "Hide the lyrics" : "Show the lyrics") : "Widen the window to show the lyrics"
}

extension Animation {
    /// Every adaptive-layout change (a column coming or going, the player bar or a page rearranging): short, so a
    /// resize past a threshold doesn't lag behind the pointer.
    static let layoutChange = Animation.smooth(duration: 0.28)
}
