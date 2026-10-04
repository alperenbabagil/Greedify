import AppKit
import GreedifyKit
import Network
import Observation
import os
import SwiftUI

/// Navigation targets in the main window.
enum Route: Hashable {
    case search, liked, albums, artists, shows, episodes
    case playlist(Playlist)
    case mix(MixLink)
    case album(Album)
    case artist(Artist)
    case show(Show)

    /// Which page this is, ignoring the payload's details (a playlist's name or song count can refresh while it shows).
    var page: String {
        switch self {
        case .search: "search"
        case .liked: "liked"
        case .albums: "albums"
        case .artists: "artists"
        case .shows: "shows"
        case .episodes: "episodes"
        case .playlist(let p): p.uri
        case .mix(let m): m.uri
        case .album(let a): a.uri
        case .artist(let a): a.uri
        case .show(let s): s.uri
        }
    }
}

/// Owns every service and store; injected into views with `.environment(model)`.
@MainActor @Observable
final class AppModel {
    let settings: AppSettings
    /// Keychain behind an in-memory cache: read once off the main thread (see CachedTokenStore).
    let tokens = CachedTokenStore(backing: KeychainTokenStore())
    let dataCache: DataCache
    let images: ImageCache
    let lyricsService: LyricsService
    let librespot = LibrespotService()
    let themes: ThemeStore
    private(set) var api: LiveSpotifyAPI
    private(set) var player: PlayerStore
    private(set) var library: LibraryStore
    private(set) var search: SearchStore
    /// The menu-bar popover's own search (QuickSearch), so typing there leaves the window's search page alone.
    private(set) var quickSearch: SearchStore

    var route: Route? = .liked
    var showLyrics = true
    /// What the main window shows at its width (lyrics panel, sidebar) and the panel's width; MainWindow feeds
    /// `layoutWindow(width:)`. Mirrored from `windowLayout` only when a value changes, so a resize redraws nothing.
    private(set) var windowFitsLyrics = true
    private(set) var windowShowsSidebar = true
    private(set) var lyricsWidth: CGFloat = 300
    @ObservationIgnored private var windowLayout = WindowLayout(
        lyricsWidth: CGFloat(UserDefaults.standard.object(forKey: "lyricsWidth") as? Double ?? 300))

    func layoutWindow(width: CGFloat) { windowLayout.resize(to: width); publishWindowLayout() }

    /// The toolbar's sidebar button (⌃⌘S).
    func toggleSidebar() { windowLayout.toggleSidebar(); publishWindowLayout() }

    /// The toolbar's Refresh button (⌘R): the library again, for edits made in another Spotify app.
    private(set) var refreshing = false
    func refreshLibrary() {
        guard !refreshing else { return }
        refreshing = true
        Task { await library.refresh(); refreshing = false }
    }

    /// Dragging the lyrics panel's edge; `save` when the drag ends.
    func setLyricsWidth(_ width: CGFloat, save: Bool = false) {
        windowLayout.setLyricsWidth(width)
        publishWindowLayout()
        if save { UserDefaults.standard.set(Double(windowLayout.lyricsWidth), forKey: "lyricsWidth") }
    }

    /// The lyrics panel and the sidebar come and go animated; the panel's width follows a drag directly.
    private func publishWindowLayout() {
        let l = windowLayout
        if lyricsWidth != l.lyricsWidth { lyricsWidth = l.lyricsWidth }
        guard windowFitsLyrics != l.showsLyrics || windowShowsSidebar != l.showsSidebar else { return }
        withAnimation(.layoutChange) {
            windowFitsLyrics = l.showsLyrics
            windowShowsSidebar = l.showsSidebar
        }
    }
    /// The selected theme as SwiftUI values; rebuilt only when the theme changes.
    private(set) var theme = ResolvedTheme.system
    private(set) var lyrics: Lyrics = .none
    private(set) var lyricsTrackID: String?
    /// The synced lyric line playing now; set by the label loop, so the lyrics panel needs no timer of its own.
    private(set) var lyricIndex: Int?
    private(set) var menuBarLabel: MenuBarLabel = .iconOnly
    private(set) var banner: String?
    private(set) var isOffline = false
    var needsSetup: Bool {
        settings.clientID.isEmpty || (tokens.isLoaded && tokens.load() == nil) || !librespot.hasCredentials
    }

    @ObservationIgnored private let diagnostics = Diagnostics()
    @ObservationIgnored private var mediaKeys: MediaKeyTap?
    @ObservationIgnored let mainWindow = MainWindowController()
    @ObservationIgnored private var musicBlocker: MusicBlocker?
    @ObservationIgnored private var nowPlaying: NowPlayingPublisher?
    @ObservationIgnored private var labelTask: Task<Void, Never>?
    /// A new song's "Artist – Song", shown in the menu bar until `announcementEnds`.
    @ObservationIgnored private var announcement: String?
    @ObservationIgnored private var announcementEnds = Date.distantPast
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var themeImagesTask: Task<Void, Never>?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var devRecipeWatcher: (any DispatchSourceFileSystemObject)?

    static let redirectURI = URL(string: "greedify://callback")!
    static let log = Logger(subsystem: "com.alperen.greedify", category: "app")

    init() {
        diagnostics.start() // first, so errors.log catches everything after it
        let settings = AppSettings()
        self.settings = settings
        themes = ThemeStore(settings: settings, devFolder: Self.devRecipes,
                            legacyFolder: DiskThemeFolder(directory: GreedifyPaths.themes))
        theme = ResolvedTheme(themes.current) // image-free: launch never waits on image decoding
        let transport = URLSessionTransport()
        dataCache = DataCache(directory: GreedifyPaths.appCache, limitBytes: settings.appCacheMB * 1_048_576)
        images = ImageCache(disk: dataCache, transport: transport, memoryLimitBytes: settings.artworkMemoryMB * 1_048_576)
        lyricsService = LyricsService(transport: transport, cache: dataCache)
        let api = Self.makeAPI(clientID: settings.clientID, tokens: tokens, transport: transport)
        self.api = api
        player = PlayerStore(api: api, localDeviceName: settings.deviceName, defaults: .standard)
        library = LibraryStore(api: api, cache: dataCache)
        search = SearchStore(api: api)
        quickSearch = SearchStore.quick(api: api)
        // The player queues an episode's successor from the show's episode list, through the library's cache.
        player.episodesOfShow = { [weak self] show, id in await self?.library.episodes(of: show, containing: id) ?? [] }
        mainWindow.attach(self)
        Scripting.model = self
        loadThemeImages(themes.current)
        watchDevRecipes()
    }

    static func makeAPI(clientID: String, tokens: TokenStore, transport: HTTPTransport) -> LiveSpotifyAPI {
        let auth = AuthService(config: AuthConfig(clientID: clientID, redirectURI: redirectURI), transport: transport)
        return LiveSpotifyAPI(auth: auth, tokens: tokens, transport: transport)
    }

    var authService: AuthService {
        AuthService(config: AuthConfig(clientID: settings.clientID, redirectURI: Self.redirectURI), transport: URLSessionTransport())
    }

    /// Rebuilds the API client and stores after the client ID changes (setup step 1).
    func rebuildClients() {
        player.stopPolling()
        api = Self.makeAPI(clientID: settings.clientID, tokens: tokens, transport: URLSessionTransport())
        player = PlayerStore(api: api, localDeviceName: settings.deviceName, defaults: .standard)
        library = LibraryStore(api: api, cache: dataCache)
        // The player queues an episode's successor from the show's episode list, through the library's cache.
        player.episodesOfShow = { [weak self] show, id in await self?.library.episodes(of: show, containing: id) ?? [] }
        search = SearchStore(api: api)
        quickSearch = SearchStore.quick(api: api)
        // Logging in again after the app already started: the new stores need the same startup.
        if started {
            player.startPolling()
            Task { await library.load() }
            observePlayer()
            observeErrors()
        }
    }

    /// Opens (or brings forward) the main window. It's created fresh and fully released on close.
    func showMainWindow() { mainWindow.show(model: self) }

    /// Shows a page in the main window, opening the window if it's closed (e.g. from the popover).
    func open(_ route: Route) {
        self.route = route
        showMainWindow()
    }

    // MARK: Lifecycle

    /// Launch: read the Keychain in the background first, so a pending Keychain prompt can't freeze the UI.
    func launch() async {
        await tokens.preload()
        start()
    }

    /// Called once at launch (after the Keychain read) and again when setup finishes.
    func start() {
        applyAppearance()
        guard !needsSetup, !started else { return }
        started = true
        // The speaker is Greedify's child process: it starts here and stops when Greedify quits (spec §3).
        Task { await LibrespotService.removeLegacyAgent() } // earlier builds ran it as a LaunchAgent
        do { try librespot.start(settings.librespotConfig) }
        catch { ErrorLog.shared.record("can't start the speaker: \(error.localizedDescription)", category: "librespot") }
        // A speaker missing from Spotify's devices is restarted on the next play (a stale librespot connection).
        player.restartSpeaker = { [weak self] in await self?.librespot.restart() }
        // The Mac speaker reports its own playback: no Web API quota spent while it plays.
        Task { [weak self, events = librespot.events] in
            for await event in events { await self?.player.apply(event) }
        }
        player.startPolling()
        Task { await library.load() }
        startMediaKeys()
        nowPlaying = NowPlayingPublisher(player: { [unowned self] in self.player }, images: images)
        nowPlaying?.start()
        musicBlocker = MusicBlocker(isEnabled: settings.blockAppleMusic)
        musicBlocker?.start()
        startNetworkMonitor()
        observeSystemEvents()
        observePlayer()
        observeErrors()
    }

    /// Wake from sleep: re-sync at once (the local clock and tokens may be stale).
    /// Accessibility granted later: start the media-key tap without a relaunch.
    private func observeSystemEvents() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.saveLastPlayed() // shown, paused where it stopped, on the next launch
                self?.librespot.stopNow() // quitting Greedify stops the music
            }
        })
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // librespot's connection timed out during sleep, silently, and librespot 0.8 won't notice until
                // something wakes it: until then Spotify doesn't list the Mac. A fresh speaker registers at once.
                Task { await self.librespot.restart() }
                Task { await self.player.refresh(); self.rescheduleLabel() }
                self.reloadLibraryIfNeeded()
            }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The trust flag updates shortly after the notification.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.startMediaKeys()
            }
        })
    }

    func startMediaKeys() {
        guard mediaKeys == nil, MediaKeyTap.hasPermission else { return }
        let tap = MediaKeyTap { [weak self] action in
            guard let self else { return }
            Task {
                switch action {
                case .playPause: await self.player.togglePlayPause()
                case .next: await self.player.next()
                case .previous: await self.player.previous()
                }
            }
        }
        if tap.start() { mediaKeys = tap }
    }

    var mediaKeysActive: Bool { mediaKeys?.isRunning ?? false }

    func setBlockAppleMusic(_ on: Bool) {
        settings.blockAppleMusic = on
        musicBlocker?.isEnabled = on
    }

    /// System follows the Appearance setting; any other theme sets light or dark from its `base` (spec §5).
    func applyAppearance() {
        if let theme = themes.current.theme, !themes.current.isSystem {
            NSApp.appearance = NSAppearance(named: theme.base == .dark ? .darkAqua : .aqua)
            return
        }
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Themes

    func selectTheme(_ id: String) {
        themes.select(id)
        themeDidChange()
    }

    func reloadThemes() {
        themes.reload()
        themeDidChange()
    }

    /// Recipes being tuned (curated skins spec §5): Debug builds only.
    static var devRecipes: (any ThemeFolder)? {
        #if DEBUG
        DiskThemeFolder(directory: GreedifyPaths.recipes)
        #else
        nil
        #endif
    }

    func showRecipesFolder() {
        guard let dir = themes.devFolderURL else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// Reloads the dev recipes whenever their folder changes (editors save by replacing the file).
    func watchDevRecipes() {
        guard devRecipeWatcher == nil, let dir = themes.devFolderURL else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .global())
        // Runs on a background queue: @Sendable, then hop to the main actor (CLAUDE.md).
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.reloadThemes() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        devRecipeWatcher = source
    }

    private func themeDidChange() {
        theme = ResolvedTheme(themes.current)
        applyAppearance()
        loadThemeImages(themes.current)
    }

    /// Decodes the theme's images and plans the backdrop off the main actor, then publishes the theme with them.
    /// A newer theme change cancels an older load, so a slow decode never overwrites the current theme.
    private func loadThemeImages(_ entry: ThemeEntry) {
        themeImagesTask?.cancel()
        themeImagesTask = nil
        guard !entry.isSystem, let t = entry.theme, !t.images.isEmpty else { return }
        themeImagesTask = Task { [weak self] in
            let images = await Task.detached(priority: .userInitiated) { ThemeImages(t) }.value
            guard !Task.isCancelled, let self, self.themes.current == entry else { return }
            self.theme = ResolvedTheme(entry, images: images)
        }
    }

    private func startNetworkMonitor() {
        // Called on the monitor's background queue: @Sendable keeps it off the main actor.
        pathMonitor.pathUpdateHandler = { @Sendable [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.setOnline(online) }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    private func setOnline(_ online: Bool) {
        guard online == isOffline else { return }
        isOffline = !online
        if online {
            player.startPolling()
            reloadLibraryIfNeeded()
        } else {
            player.stopPolling()
        }
    }

    /// The first library load failed (e.g. launched at login before Wi-Fi connected): try again.
    private func reloadLibraryIfNeeded() {
        guard library.user == nil else { return }
        Task { await library.load() }
    }

    // MARK: Lyrics and menu-bar label

    /// Re-runs whenever the player state changes (poll, seek, track change).
    private func observePlayer() {
        withObservationTracking {
            _ = player.state
            _ = player.clock
            _ = settings.lyricsInMenuBar
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.nowPlaying?.update()
                await self.trackChanged()
                self.rescheduleLabel()
                self.observePlayer()
            }
        }
        Task { await trackChanged(); rescheduleLabel() }
    }

    private func trackChanged() async {
        guard let track = player.track else { lyrics = .none; lyricsTrackID = nil; return }
        guard track.id != lyricsTrackID else { return }
        lyricsTrackID = track.id
        lyrics = .none
        announcement = MenuBarLabel.announcement(for: track)
        announcementEnds = Date().addingTimeInterval(MenuBarLabel.announcementSeconds)
        rescheduleLabel()
        Task { await captureMixSongs() }
        // Popover, player bar and track rows all read library.likedIDs; keep it current for the new track.
        Task { await library.refreshLikes(for: [track]) }
        guard !track.isEpisode else { rescheduleLabel(); return } // LRCLIB has songs only
        let fetched = await lyricsService.lyrics(for: track)
        if lyricsTrackID == track.id { lyrics = fetched; rescheduleLabel() }
    }

    /// Spotify won't list a mix's songs, or those of someone else's playlist, but the queue shows them while it plays:
    /// save what's there.
    func captureMixSongs() async {
        guard let uri = player.state?.context?.uri else { return }
        let isMix = settings.mixes.contains { $0.uri == uri }
        guard isMix || library.wantsQueueSongs(contextURI: uri),
              let queue = try? await api.queue(), player.state?.context?.uri == uri else { return }
        let seen = [queue.currentlyPlaying].compactMap { $0 } + queue.queue
        if isMix { settings.recordMixTracks(uri: uri, tracks: seen) } else { await library.recordQueueSongs(contextURI: uri, tracks: seen) }
    }

    private func setLyricIndex(_ index: Int?) {
        if lyricIndex != index { lyricIndex = index }
    }

    /// Sets the label and the current lyric line now, then sleeps until the next synced line (or the end of a new
    /// song's announcement) and repeats (one timer, no polling).
    func rescheduleLabel() {
        labelTask?.cancel()
        labelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                let pos = self.player.positionMs(at: now)
                let announcementLeftMs = Int(self.announcementEnds.timeIntervalSince(now) * 1000)
                self.menuBarLabel = MenuBarLabel.make(enabled: self.settings.lyricsInMenuBar, isPlaying: self.player.isPlaying,
                                                      trackName: self.player.track?.name, lyrics: self.lyrics, positionMs: pos,
                                                      announcement: announcementLeftMs > 0 ? self.announcement : nil)
                var wakeMs = announcementLeftMs > 0 ? announcementLeftMs : nil
                if case .synced(let lines) = self.lyrics {
                    self.setLyricIndex(LRCParser.currentIndex(in: lines, at: pos))
                    if self.player.isPlaying, let next = LRCParser.nextChangeMs(in: lines, after: pos) {
                        wakeMs = min(wakeMs ?? .max, next - pos)
                    }
                } else {
                    self.setLyricIndex(nil)
                }
                guard self.player.isPlaying, let wakeMs else { return }
                try? await Task.sleep(for: .milliseconds(max(50, wakeMs)))
            }
        }
    }

    // MARK: Banners

    private func observeErrors() {
        withObservationTracking {
            _ = player.lastError
            _ = library.lastError
            _ = search.lastError
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let e = self.player.lastError ?? self.library.lastError ?? self.search.lastError { self.show(e) }
                self.observeErrors()
            }
        }
    }

    func show(_ error: SpotifyError) {
        Self.log.error("\(String(describing: error), privacy: .public)")
        if case .rateLimited = error { return } // shown as the menu-bar status icon instead
        showBanner(error.bannerText)
        player.clearError(); library.clearError()
    }

    /// Rewrites librespot's arguments and restarts it (Settings changes).
    func applySpeakerSettings() {
        let config = settings.librespotConfig
        Task {
            do { try await librespot.apply(config) }
            catch { ErrorLog.shared.record("can't apply speaker settings: \(error.localizedDescription)", category: "librespot") }
        }
    }

    func showBanner(_ text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.banner = nil }
        }
    }

    var needsReauth: Bool { tokens.isLoaded && tokens.load() == nil && !settings.clientID.isEmpty }

    // MARK: Account

    func logOut() {
        player.stopPolling()
        tokens.clear()
        started = false
        settings.onboardingDone = false
    }

    func reset() async {
        logOut()
        await librespot.stop()
        await dataCache.clear()
        images.clearMemory()
        try? FileManager.default.removeItem(at: GreedifyPaths.appSupport)
        try? FileManager.default.removeItem(at: GreedifyPaths.caches)
        settings.reset()
    }
}
