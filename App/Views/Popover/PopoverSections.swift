import GreedifyKit
import SwiftUI

/// The popover's device section: every device as a row; a click moves playback there.
struct PopoverDevices: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        let player = model.player
        VStack(alignment: .leading, spacing: 2) {
            ForEach(player.devices) { device in
                Button {
                    Task { await player.transfer(to: device) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: device)).frame(width: 18)
                        Text(device.name).lineLimit(1)
                        Spacer(minLength: 0)
                        if device.isActive { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                    }
                    .padding(.horizontal, 6).padding(.vertical, theme.isPlaylistList ? 2 : 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(theme.isPlaylistList ? theme.listFont() : nil) // a playlist editor's dense lines
                .foregroundStyle(device.isActive ? theme.accent : theme.text)
                .accessibilityAddTraits(device.isActive ? [.isSelected] : [])
            }
            if player.devices.isEmpty { Text("No devices found").themed(.secondary).padding(.horizontal, 6) }
        }
        .task { await player.refreshDevices() }
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

/// The popover's lyrics section: a short window on the lyrics that follows the playing line, and the
/// menu-bar lyrics switch.
struct PopoverLyrics: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 8) {
            lyrics.frame(height: 120)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                             .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            Toggle("Lyrics in Menu Bar", isOn: $settings.lyricsInMenuBar)
                .toggleStyle(.checkbox).controlSize(.small).themed(.secondary)
                .onChange(of: settings.lyricsInMenuBar) { model.rescheduleLabel() }
        }
    }

    @ViewBuilder var lyrics: some View {
        switch model.lyrics {
        case .synced(let lines):
            // The current line comes from AppModel's label loop, like the window's lyrics panel: no timer here.
            let current = model.lyricIndex
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            Text(line.isGap ? "♪" : line.text)
                                // The skin's lyric style when it has one (a Winamp skin's small type), as in the window.
                                .font(theme.style?.text[.lyrics].map { LCDTitle.font($0, theme: theme) } ?? theme.font(14, weight: .semibold))
                                .foregroundStyle(i == current ? theme.accent : theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                                .contentShape(Rectangle())
                                .onTapGesture { Task { await model.player.seek(toMs: line.timeMs) } }
                        }
                    }
                    .padding(.vertical, 44) // lets the first and last lines reach the middle
                }
                .scrollIndicators(.never)
                .onChange(of: current) { _, i in
                    guard let i else { return }
                    withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(i, anchor: .center) }
                }
                .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            }
        case .plain(let text):
            ScrollView {
                Text(text).font(theme.font(13, weight: .medium)).themed(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .none:
            Text(model.player.track == nil ? "Nothing playing"
                 : model.player.track?.isEpisode == true ? "No lyrics for podcasts" : "No lyrics found")
                .themed(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
