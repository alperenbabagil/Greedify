import GreedifyKit
import SwiftUI

/// Your Shows (podcasts spec §8.2).
struct ShowsGrid: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let library = model.library
        PageScrollView {
            PodcastNotice().padding(.horizontal, 24).padding(.top, 16)
            CoverGrid(items: library.shows, images: \.images, title: \.name,
                      subtitle: { $0.totalEpisodes.map { "\($0) episodes" } ?? "Podcast" }, circle: false,
                      onOpen: { model.route = .show($0) }, onReachEnd: { Task { await library.loadMoreShows() } })
        }
        .navigationTitle("Your Shows")
        .task { if library.shows.isEmpty { await library.loadMoreShows() } }
    }
}

/// A show's page: its episodes, newest first (podcasts spec §8.3).
struct ShowView: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let show: Show

    var body: some View {
        let library = model.library
        let episodes = library.showEpisodes[show.id] ?? []
        PageScrollView {
            PodcastNotice().padding(.horizontal, 28).padding(.top, 16)
            AdaptiveHeader { size in
                ArtworkView(images: show.images, size: size, corner: theme.artworkRadius * 2)
                    .shadow(color: .black.opacity(0.25), radius: 15, y: 10)
            } info: {
                Text("Podcast").themedFont(.caption).themed(.secondary)
                HeaderTitle(text: show.name)
                if let total = show.totalEpisodes { Text("\(total) episodes").themed(.secondary) }
                if let description = show.description, !description.isEmpty {
                    Text(description).themedFont(.callout).themed(.secondary).lineLimit(1)
                }
                HStack(spacing: 10) {
                    Button {
                        // The newest episode not played to the end, from where it stopped.
                        guard let i = episodes.firstIndex(where: { !($0.resumePoint?.fullyPlayed ?? false) }) ?? episodes.indices.first else { return }
                        let next = episodes[i], newer = i > 0 ? episodes[i - 1].uri : nil
                        Task { await model.player.play(.episode(next.uri, at: model.player.startPosition(for: next), then: newer)) }
                    } label: { Label("Play", systemImage: "play.fill") }
                        .themedButton(.primary)
                        .disabled(episodes.isEmpty)
                    let following = library.isFollowing(show)
                    Button { Task { await library.toggleFollow(show) } } label: {
                        Label(following ? "Following" : "Follow", systemImage: following ? "checkmark" : "plus")
                    }
                    .themedButton(.secondary)
                }
                .padding(.top, 10)
            }
            EpisodeTable(episodes: episodes, showShowName: false, newestFirst: true) { Task { await library.loadMoreEpisodes(of: show.ref) } }
                .padding(.horizontal, 20)
        }
        .task(id: show.id) {
            _ = await library.episodes(of: show.ref)
            await library.refreshFollow(show)
        }
    }
}

/// Your Episodes (podcasts spec §8.5).
struct SavedEpisodesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let library = model.library
        PageScrollView {
            PodcastNotice().padding(.horizontal, 28).padding(.top, 16)
            DetailHeader(images: [], kind: "Podcasts", title: "Your Episodes", meta: "\(library.savedEpisodes.count) episodes", playURI: nil)
            EpisodeTable(episodes: library.savedEpisodes, showShowName: true) { Task { await library.loadMoreSavedEpisodes() } }
                .padding(.horizontal, 20)
        }
        .task { if library.savedEpisodes.isEmpty { await library.loadMoreSavedEpisodes() } }
    }
}

struct EpisodeTable: View {
    @Environment(AppModel.self) private var model
    let episodes: [Track]
    let showShowName: Bool
    /// The show's own list, newest first: each row's follower is the row above it.
    var newestFirst = false
    var onReachEnd: (() -> Void)?

    var body: some View {
        LazyVStack(spacing: 0) {
            ThemedDivider()
            ForEach(Array(episodes.enumerated()), id: \.offset) { index, episode in
                EpisodeRow(episode: episode, showShowName: showShowName, newer: newestFirst && index > 0 ? episodes[index - 1] : nil)
                    .onAppear { if index == episodes.count - 1 { onReachEnd?() } }
            }
        }
        .task(id: episodes.map(\.id)) { await model.library.refreshLikes(for: Array(episodes.prefix(40))) }
    }
}

/// An episode: cover, title, date and length, and how far it's been listened to (podcasts spec §8.4).
struct EpisodeRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var model
    let episode: Track
    let showShowName: Bool
    /// The next newer episode, sent with the play so it follows without queueing.
    var newer: Track?
    @State private var hovering = false

    var isCurrent: Bool { model.player.track?.id == episode.id }
    var played: Bool { episode.resumePoint?.fullyPlayed ?? false }

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(images: episode.album?.images ?? [], size: theme.rowArtworkSize, corner: theme.artworkRadius)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.name).font(theme.font(14, weight: .medium))
                    .foregroundStyle(isCurrent ? theme.accent : theme.text).lineLimit(1)
                Text(meta).font(theme.font(12)).themed(.secondary).lineLimit(1)
            }
            .opacity(played ? 0.6 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            status
            LikeButton(track: episode).opacity(hovering || model.library.isLiked(episode) ? 1 : 0).frame(width: 28)
        }
        .padding(.horizontal, 8)
        .frame(height: theme.rowHeight)
        .opacity(episode.isPlayable == false ? 0.5 : 1)
        .themedRow(selected: false, hovering: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { play(from: model.player.startPosition(for: episode)) } // a single click plays, as in Spotify
        .contextMenu {
            Button("Play", systemImage: "play.fill") { play(from: model.player.startPosition(for: episode)) }
            Button("Play from Start", systemImage: "backward.end.fill") { play(from: 0) }
            Button("Add to Queue", systemImage: "text.badge.plus") { Task { await model.player.addToQueue(uri: episode.uri) } }
            let saved = model.library.isLiked(episode)
            Button(saved ? "Remove from Your Episodes" : "Save to Your Episodes", systemImage: saved ? "minus.circle" : "plus.circle") {
                Task { await model.library.toggleLike(episode) }
            }
            if let show = episode.show.flatMap(Show.init(ref:)) {
                Divider()
                Button("Go to Show", systemImage: "mic") { model.open(.show(show)) }
            }
        }
    }

    /// "The Show · 28 Sep · 54 min"
    var meta: String {
        var parts: [String] = []
        if showShowName, let name = episode.show?.name { parts.append(name) }
        if let date = episode.releaseDate.flatMap(Self.date) { parts.append(date) }
        parts.append("\(max(1, episode.durationMs / 60_000)) min")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder var status: some View {
        if played {
            Image(systemName: "checkmark").themed(.secondary).frame(width: 90, alignment: .trailing)
        } else if let position = model.player.episodeProgress[episode.id] ?? episode.resumePoint?.resumePositionMs,
                  position > 0, episode.durationMs > 0 {
            let fraction = min(1, Double(position) / Double(episode.durationMs))
            HStack(spacing: 6) {
                Capsule().fill(theme.divider).frame(width: 40, height: 3)
                    .overlay(alignment: .leading) { Capsule().fill(theme.accent).frame(width: 40 * fraction, height: 3) }
                Text("\(max(1, (episode.durationMs - position) / 60_000)) min left")
                    .themedFont(.caption).themed(.secondary)
            }
            .frame(width: 90, alignment: .trailing)
        } else {
            Color.clear.frame(width: 90)
        }
    }

    func play(from ms: Int?) { Task { await model.player.play(.episode(episode.uri, at: ms, then: newer?.uri)) } }

    /// `2026-09-28` → "28 Sep"; a year other than this one is added ("28 Sep 2024"); shorter precisions pass through.
    static func date(_ raw: String) -> String? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return raw }
        let thisYear = Calendar.current.component(.year, from: Date()) == parts[0]
        return date.formatted(thisYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year())
    }
}

/// "Log in again for podcast progress": resume points need a scope older logins didn't ask for (podcasts spec §5).
struct PodcastNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = model.settings
        if let tokens = model.tokens.load(), !tokens.hasScope(AuthConfig.playbackPositionScope), !settings.podcastNoticeDismissed {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Log in to Spotify again to see where you stopped in each episode.")
                Spacer()
                Button("Log In…") {
                    model.tokens.clear() // the setup window's login step replaces the token with one that has the scope
                    openWindow(id: WindowID.setup)
                }
                .themedButton(.primary, capsule: false)
                Button { settings.podcastNoticeDismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).iconLabel("Dismiss", hint: "Don't show again")
            }
            .themedFont(.callout)
            .padding(10)
            .themedSurface(.raised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
