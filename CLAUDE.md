# Greedify

Personal macOS Spotify client: a SwiftUI menu-bar app plus main window. Playback control goes through the Spotify Web API; audio comes from a bundled librespot. The goal is a much smaller memory footprint than the official Spotify app. One user, not distributed.

- Spec: `docs/superpowers/specs/2026-09-29-greedify-design.md` (binding). Approved mockups are in `docs/superpowers/specs/mockups/`.
- Original plan: `docs/superpowers/plans/2026-09-29-greedify.md`. It's historical: the code has moved on (see "Changes since the plan" below).
- Verification results (checks C1–C4, manual checklist): `docs/verification.md`.

## Build, test, install

Prerequisites: `brew install librespot xcodegen`.

```bash
# Unit tests (all logic lives in the package)
cd Packages/GreedifyKit && swift test
```

```bash
# Debug build (the Xcode project is generated; never edit Greedify.xcodeproj)
xcodegen generate && xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Debug -derivedDataPath build build
```

```bash
# Release build → /Applications (always run the installed copy: the login item and the greedify:// handler are tied to it)
scripts/install.sh
```

```bash
# Memory: Greedify + librespot physical footprint
scripts/measure-memory.sh
```

```bash
# Downloadable zip for GitHub Releases → build/release/Greedify-<version>.zip
# Ad-hoc signed whatever Local.xcconfig says (no Developer ID, no name in the signature) and arm64 only (Homebrew's librespot is).
scripts/package.sh
```

## Layout

- `Packages/GreedifyKit/` holds everything testable, with Swift Testing tests. That covers:
  - the Web API client (`LiveSpotifyAPI`, an actor handling PKCE refresh, 401 retry and 429 back-off);
  - the stores (`PlayerStore`, `LibraryStore`, `SearchStore`, all `@MainActor @Observable`);
  - the caches, the LRCLIB lyrics, the menu-bar label logic, and the media-key tap;
  - `SpeakerProcess` / `LibrespotService` and `AppSettings`;
  - the themes (Theme, ThemeStore, the Winamp .wsz importer).
  Stores depend on the `SpotifyAPI` protocol; tests use `FakeSpotifyAPI` and `StubTransport`.
- `App/` holds only SwiftUI views and wiring:
  - `AppModel` owns every service and store; `MainWindowController` owns the main window.
  - Scenes: `MenuBarExtra` (popover), setup `Window`, `Settings`.
- `App/Resources/greedify-speaker` is the librespot launcher, and `scripts/bundle-librespot.sh` copies Homebrew's librespot into the bundle and signs it.

## Things that were learned the hard way (don't regress)

- **librespot is a child process of Greedify, not a LaunchAgent.** The user wants the music to stop when the app is gone.
  - The launcher's watchdog (`GREEDIFY_PARENT_PID`) stops librespot even if Greedify crashes.
  - `SpeakerProcess` restarts librespot with back-off if it exits on its own.
  - `LibrespotService.removeLegacyAgent()` cleans up the agent that old builds registered.
- **The main window is AppKit-owned (`MainWindowController`), not a SwiftUI `Window` scene.** The scene kept the closed window's graph and backing store alive (188 MB after closing). The controller tears the content down on close.
- **NavigationSplitView constraint-loop crash.** If a column's minimum size changes with its content during a resize or zoom, or the visible columns' minimums add up to more than the window, AppKit aborts with "too many Update Constraints passes".
  - Every column uses `.fixedMinimum(width:height:)`, a `Layout` that sizes from the proposal only. A `frame(minWidth:maxWidth: .infinity)` is not enough: it still reports the content's width when that is wider (the track table made the detail column ~640 pt), and with the lyrics inspector open SwiftUI passed it on to the window.
  - The player bar takes the width it's offered (`.proposedWidth()`); its wide layout's ~940 pt otherwise became the window's minimum whenever the columns changed.
  - The lyrics panel is drawn inside the detail column (`DetailColumn`), not as an `.inspector`: with an inspector open AppKit pinned the page's minimum to its current width, so opening the lyrics anywhere the page had to shrink for them aborted (the original 860 pt build too, e.g. lyrics off at 975 pt → on), and big resizes were refused.
  - Visible columns must fit the window (`WindowLayout` in the package, tested): the lyrics show only where the sidebar at its widest, a 340 pt page and the panel fit; the sidebar collapses under 720 pt; and sidebar (200) + page (300) fit the 520 pt minimum, so the toggle can always show it. The sidebar's visibility binding is read-only (the model decides).
  - The hosting controller uses `sizingOptions = []`, which keeps the window's `contentMinSize` at 0 (reset on every resize), so a drag is held at the minimum (520 × 720, title bar included) by `MainWindowController.windowWillResize`, and programmatic resizes by a constant `.frame(minWidth:)` on `MainWindow`'s root. No `minHeight` there: SwiftUI applies it below the title bar, so at the window's minimum the content overflowed and the player bar was cut off. `.minSize` was tried: the shown sidebar then added to the minimum (752 pt), so dragging could never reach the 720 pt collapse.
- **librespot volume runs `--volume-ctrl linear`.** Its default log scale over 60 dB took 18 dB off at 70%, so 70% sounded like 30%. Greedify sends the slider's percentage to Spotify unchanged; librespot's scale decides how loud it is.
- **Title-bar double-click** is handled by `MainWindowController`, following `AppleActionOnDoubleClick` (zoom by default). The SwiftUI toolbar area minimized instead.
- **Menu-bar label:**
  - An inline symbol in a `Text` label disappears in the status item, and an `HStack` misaligns, so icon and lyric are drawn into one template `NSImage` (`MenuBarLabelImage`).
  - Draw it with AppKit, never `ImageRenderer`: ImageRenderer keeps GPU buffers (+101 MB for 150 lyric lines).
- **Swift 6 and callbacks:** a closure written inside a `@MainActor` type but invoked on a background queue crashes at runtime (`dispatch_assert_queue`). Mark such closures `@Sendable` and hop to the main actor inside. This applies to:
  - `ASWebAuthenticationSession` completion,
  - `FileHandle.readabilityHandler`,
  - `NWPathMonitor`,
  - `Process.terminationHandler`.
- **Keychain:** never read it on the main thread. A pending Keychain prompt blocked the main thread and froze the app. Tokens go through `CachedTokenStore` (read once in `AppModel.launch()`, off the main thread).
- **Signing:** `Config/Signing.xcconfig` signs ad-hoc unless a git-ignored `Local.xcconfig` (copy `Local.xcconfig.example`) names an Apple Development team. Develop with your own team: ad-hoc signing changes the identity every build, which resets the Keychain "Always Allow" and the Accessibility grant.
- **Spotify Web API (development mode, 2026):**
  - Search `limit` is at most 10, and so is `/artists/{id}/albums` (more is a 400).
  - `/artists/{id}/top-tracks` is gone: the artist page's popular songs come from one `artist:"…"` search (`LibraryStore.popularTracks`, cached a day). The name filter is fuzzy, so other artists are dropped by id; features are kept, or a page often left only 5.
  - librespot 0.8 loads a Web API play in list order even with shuffle on, so `PlayerStore.play` re-sends shuffle once the new track loads.
  - The `/me/library` endpoints take `uris` as a query parameter, at most 40.
  - Playlist tracks are at `/playlists/{id}/items`, and items may use `item` or `track`, so decode both.
  - `POST /me/playlists` creates a playlist.
  - Daily Mixes and radio can't be read, only played by URI. A mix's songs are collected from `/me/player/queue` while it plays (`AppModel.captureMixSongs`, `MixTracks`).
  - Use our own client ID only.
  - A 429 with `reason: QUOTA_EXCEEDED` is a daily quota **per endpoint** (`Retry-After` ~20 h). On 2026-09-29, `/me` and `/me/library/contains` ran out while `/me/player/*` kept working. `LiveSpotifyAPI` backs off per path for quota and app-wide only for the short rate limit; a global quota back-off once blocked playback for a day.
  - Podcasts: `/me/shows`, `/me/episodes`, `/shows/{id}/episodes` (≤ 50); following/saving goes through `/me/library` with show/episode URIs. `/me/player` needs `additional_types=episode` or an episode comes back as `item: null`. An episode plays only as `uris` + `position_ms` (a show context always starts its oldest unplayed episode). Resume points need `user-read-playback-position`. Search returns episodes without their show.
  - Every request is logged (`com.alperen.greedify` / `api`). Read the logs with `/usr/bin/log show --info --predicate 'subsystem == "com.alperen.greedify"'`: in zsh, a bare `log` is a builtin.
- **Memory profile** (don't chase it further without a new idea): fresh launch about 23 MB; window open 56–74 MB; after closing about 52–59 MB.
  - The ~30 MB retained is one-time framework initialisation plus the allocator's high-water mark, and doesn't depend on the page shown.
  - The only big lever left is a two-process split (window in its own process). It was discussed and declined for now.
  - **`MallocSpaceEfficient=1` (`LSEnvironment` in `project.yml`) is what keeps these numbers.** Without it, macOS's default allocator kept the window's freed memory (live heap 22 MB in 60 MB of pages, `malloc_zone_pressure_relief` returns 0): fresh 32, closed 66–85 MB, and 73 MB after a day's use. It applies only when LaunchServices starts the app (`open`, Finder, login item), so measure that way, not by exec'ing the binary. Check with `ps eww -p $(pgrep -x Greedify) | grep -o MallocSpaceEfficient=1`.

## Debug hooks

`MainWindowController` listens for distributed notifications, which is useful for scripted memory and crash tests:

| Notification | Object |
|---|---|
| `com.alperen.greedify.debug.showMain` | none |
| `com.alperen.greedify.debug.closeMain` | none |
| `com.alperen.greedify.debug.resize` | `"WxH"` |
| `com.alperen.greedify.debug.zoom` | none |
| `com.alperen.greedify.debug.route` | `liked`, `albums`, `artists`, `playlist:N`, `search:q`, `shows`, `episodes`, `show:N`, `nowplaying:album`, `nowplaying:artist` |
| `com.alperen.greedify.debug.play` | a context URI, optionally `\|shuffle` (the header's Shuffle button) or `\|at:<track URI>` (a click on that row) |
| `com.alperen.greedify.debug.lyrics` | `on` / `off` |
| `com.alperen.greedify.debug.theme` | a theme id: `builtin.system`, `builtin.winamp-classic`, `dev.<file>.greedifytheme` |
| `com.alperen.greedify.debug.sidebar` | none (the toolbar's sidebar button) |
| `com.alperen.greedify.debug.lyricsWidth` | a width in points, as if the panel's edge were dragged |
| `com.alperen.greedify.debug.popoverSnapshot` | `"PNG path\|query"`: draws the popover offscreen with that search typed, or with `@device` / `@volume` / `@lyrics` that section open (transparent background: composite it on a dark one) |
| `com.alperen.greedify.debug.snapshot` | a PNG path: the window draws itself into it (no Screen Recording permission needed; vibrancy such as the System sidebar renders blank, toolbar items don't render) |

The hooks are always on in Debug builds. In Release they're on only after:

```bash
defaults write com.alperen.greedify debugHooks -bool YES
```

Switch them off again afterwards with `defaults delete com.alperen.greedify debugHooks`.

## Changes since the plan

- **Speaker:** a child process instead of a LaunchAgent.
- **Main window:** AppKit-owned.
- **Setup:** "Copy Link" buttons for both logins; the Spotify login also completes through `greedify://callback` from any browser (handled in `SetupView.onOpenURL`).
- **Speaker events:** the launcher runs librespot with `--onevent greedify-event`. That script prints each player event as a `GREEDIFY-EVENT` line on stdout, and `SpeakerProcess.events` parses them (`LibrespotEvent`).
  - While the Mac is the speaker (`PlayerStore.isLocalActive`), the events are the truth: play state and position come from them. Polling drops to 5 min, and commands skip their follow-up poll.
  - One delayed poll per track fills in the artist/album ids and the context. A poll showing an older track, or a 204, is ignored as API lag.
  - librespot 0.8's events and variables: `track_changed` (NAME, ARTISTS, ALBUM, COVERS, DURATION_MS, URI), `playing`/`paused`/`seeked` (POSITION_MS), `stopped`, `volume_changed` (VOLUME 0–65535), `shuffle_changed`, `repeat_changed`.
- **Quota savers:** the user (`/me`) is cached for 7 days and like flags for 1 day, on disk (`LibraryStore`). With nothing playing, polling slows to 10 s (window open) or 60 s (closed).
- **Artwork:** decoded at its on-screen pixel size, with a 15 MB memory default.
- **Reopen:** opening Greedify again shows a window (`AppDelegate.applicationShouldHandleReopen`).
- **AppleScript:** Greedify speaks Spotify's dictionary and codes (`App/Resources/Greedify.sdef`, `App/Model/Scripting.swift`): `player state`, `current track`, `playpause`/`play`/`pause`/`next track`/`previous track`. Terminalo's now-playing chip uses it. Each read keeps polling fast for 10 s (`PlayerStore.scriptDidRead`), except while the Mac speaker is active.
- **macOS Now Playing:** `NowPlayingPublisher` (app) publishes `NowPlayingInfo` (package) to `MPNowPlayingInfoCenter` and handles `MPRemoteCommandCenter` commands (play/pause, skip, scrub). The media-key tap swallows the keys when it runs, so they're never handled twice. Since macOS 15.4 only Apple-signed processes can read Now Playing, so checking it from a script means loading the query into `/usr/bin/perl`.
- **Winamp window:** the recipe can make the whole window Winamp: `list` (playlist-editor rows), `pageHeader` (strip), `frame` (panel frames with a striped title, `WinampFrame`), `bar.analyser` / `readouts` / `transport` (previous, play, pause, stop, next; the eject button was removed at the user's request) and `text.lyrics`. Both Winamp skins use them. Classified follows its `.wsz` (sampled from `titlebar.bmp`, `main.bmp`, `viscolor.txt`): steel title bars with one silver groove and heavy lettering (`frame.title.background`, `stripeHeight`, `rounded`, `font`), rounded LCDs (`lcd.radius`), round transport buttons and pill labelled ones (`button.labelShape`); the sidebar button is square in every skin (`skinnedControl(square:)`). Its panels are set into the silver body (`frame.radius`, `frame.outline`), its player bar uses the same layout as Classic's (a main-window layout was tried and removed at the user's request, as was a playlist footer), its buttons are the original's glossy faces as circles (ellipses looked fat) with a dark outline and a light halo, a little apart (`button.outline` / `halo` / `spacing`; no bevel then) in a recessed channel (`bar.transportWell`), and pages and lyrics use a silver scroller (`list.scroller`; pages scroll in `PageScrollView`, whose `.skinScroller()` hides the system scroller, reads `onScrollGeometryChange` and scrolls through `ScrollPosition`). A framed skin also replaces AppKit's chrome, which can't be restyled: `.searchable` gives way to `SkinSearchField` at the top of the sidebar (⌘K and the `focusSearch` hook focus it), the window title is removed (`.toolbar(removing: .title)`) for a striped `GREEDIFY` title bar drawn under the toolbar (`TitleBarBand`), and the sidebar button is a skin button. Switching between a framed skin and another theme rebuilds the columns. The popover of a framed skin (`PopoverView.winampBody`) is the original's stacked windows in miniature: a `WINAMP` main window (`WinampPopoverPlayer`: LCD with time, analyser, title and readouts, the seek bar, shuffle / transport in its channel / repeat), the action buttons as skin buttons on the frame, then a `WINAMP PLAYLIST` window holding the open section and the quick-play list as playlist lines (`QuickPlayRow.playlistLine`); the search field is the LCD style. `winampFrame` draws no toolbar band without a `titleBar`, and a frame with an empty name is titled with the prefix alone. Measured: ten popover renders grow the app as much as on System (+1 MB).
  - **Toolbar on macOS 26:** AppKit puts a round glass platter (`NSToolbarPlatterView`) behind every toolbar item, so a skin button needs `.sharedBackgroundVisibility(.hidden)`. Don't use `.toolbarBackground(.hidden, for: .windowToolbar)`: it added a blur backdrop over the page column's title-bar band. The split view's `NSTitlebarBackgroundView` sits above the page column (below the sidebar) and drew plain dark grey there on screen, so framed skins make the title bar transparent (`TransparentTitlebar`). The `snapshot` hook draws offscreen and leaves out this chrome (platters, vibrancy), so check title-bar work on screen or by walking the view tree (`NSThemeFrame` down, layers included). The analyser is a still shape per song (`Analyser.bars`), never animated. Spec: `docs/superpowers/specs/2026-10-03-winamp-window-design.md`.
- **Themes:** built-in only; the user can't import. `ThemeStore` (package) lists System, the four plain built-ins and the curated skins (Winamp Classic, Winamp5 Classified). Debug builds also load live `dev.` recipes from `~/Library/Application Support/Greedify/Recipes/`, which reload on save. A selection left from the import era maps to its curated theme. The app reads `ResolvedTheme` from `@Environment(\.theme)` and styles views through `App/Views/Shared/ThemeComponents.swift`: use `.themed(...)`, `.themedFont(...)`, `.themedSurface(...)`, `.themedButton(...)`, `ThemedSlider` and `.skinnedControl(...)` instead of `.secondary`, `.bar`, `.borderedProminent` or `Slider`. The sidebar has no `List(selection:)`: rows are buttons so the theme can draw the highlight.
  - **Curated skins** are recipes (`Theme.style`, package `Style`): native materials (`solid`, `gradient`, `dotGrid`, `brushed`, `noise`, `pattern`, `radial`, `image`, `layers`), bevels, an LCD, buttons, sliders, row colours and text, drawn by `App/Views/Shared/Recipe/`. With `bar.layout == .winamp`, `WinampBar` / `WinampPopoverPlayer` replace the plain bar. Themes carry `credits` (Settings → Credits). How to add one: `docs/adding-a-skin.md` (the `skin-recipe` tool drafts a recipe from a `.wsz`). Spec: `docs/superpowers/specs/2026-09-30-curated-skins-design.md`.
  - **Memory lessons (don't regress):** textured materials are a layer whose background is a pattern colour (`PatternLayer`). `ImagePaint` gave every surface its own full-size buffer (+9 MB), and a pattern `NSColor` inside a SwiftUI `Color` draws nothing. Glows are drawn in the same pass (`halo`), never as a blurred `.shadow` on moving text: that allocated an offscreen buffer every frame (footprint swung up to 189 MB). Liquid Glass is off (`UIDesignRequiresCompatibility`). Measured with the window open: System 70 MB, Classic 76, Classified 75. A skin with two background pictures (since removed) measured 87.
    - Since the whole-window Winamp look, with the window open (fresh launch, Liked Songs, 1280 × 800): Classified 84 MB, Classic 83, System 72; closed, all three 50. The rest over System is mostly the dense playlist rows (~2.5× as many on screen) and the frames.
    - `BevelEdges` is four colour strips, not a `Canvas`: as a canvas every LCD, slider, scroller and button edge had a backing buffer (+3.5 MB on a skin). Song rows draw a plain heart and swap in the real `LikeButton` only under the pointer (−2 MB).
    - Measuring: a single reading can be off by 5 MB or more (what the list has loaded, decoded artwork). Compare variants from fresh launches, twice each, before believing a difference.
    - Never draw panel-sized decoration as a `Canvas` or one full-size material: each got a full-size backing buffer (+27 MB for the three frames). Frames are colour strips (`EdgeBevel`, `FrameFace`).
    - `PixelText` is a cached bitmap (`PixelTextImages`), not a `Canvas`: the scrolling title's canvas made the GPU take ~50 MB for a second every few seconds. Watch for spikes with `footprint -p` once a second, not a single reading.
  - **Backgrounds never take clicks:** `MaterialFill` is `.allowsHitTesting(false)`. An `.image` fill is laid out larger than its strip and only clipped when drawn; a skin's bar picture once caught clicks and scrolls ~290 pt above the bar, so lower rows wouldn't play and the list wouldn't scroll (hover still worked).
  - **CPU lessons (don't regress):** nothing may redraw every frame while a song plays. The skins' scrolling title once re-evaluated its pixel text in a 24 fps `TimelineView` and an endless `symbolEffect` ran on the playing row: the main thread sat at ~78% and on a skin with background pictures (slow to composite) clicks and scrolls were dropped. Move drawn content by its offset, keep symbols still. `Marquee` steps like Winamp's title (4 pt eight times a second, no animation): a 60 fps offset animation still cost ~10% CPU while a long title scrolled, and `drawingGroup` didn't help. Never write `TimelineView(.periodic(from: .now, …))`: a new schedule every body evaluation fires at once and loops (~190 Hz); start from `.timelineStart`. Lyric-line timing comes from `AppModel.lyricIndex`, not a timer. Window open and playing should be ~1–2% CPU (lyrics panel included); check with `top -pid` and `sample` after the UI settles (a theme switch costs a few seconds of work).
  - The older theme specs (`2026-09-30-themes-design.md`, `-theme-images-design.md`, `-skinned-controls-design.md`) describe the import era; the curated-skins spec replaces their import, backdrop and sprite parts.

- **Error log:** `ErrorLog` (package) writes errors to the unified log and to `~/Library/Logs/Greedify/errors.log`. The file rotates at 512 KB, keeping one `errors.1.log`, and a message repeated within 5 min is counted rather than rewritten.
  - **What's recorded:** failed API requests (status, transport, decoding), speaker exits and librespot `ERROR` lines, Keychain, cache-write and login-item failures, and player command errors.
  - **Launch (`Diagnostics`):** opens the log, scans `~/Library/Logs/DiagnosticReports` and `/Library/Logs/DiagnosticReports` (where macOS 27 writes them) for new Greedify and librespot reports, and subscribes to MetricKit.
  - **Settings → Diagnostics** shows and copies the tail.
  - Package code records to `ErrorLog.shared`, which writes to disk only after the app opens it, so tests never touch `~/Library/Logs`.
- **Podcasts:** an episode is a `Track` with `kind: .episode` (the show stands in for artist and album; `inShow`), so every surface shows it. `LibraryStore` has shows, saved episodes and a show's episodes (first page cached until midnight; the next-episode lookup pages on up to 4 pages). `PlayerStore` resumes episodes (`startPosition(for:)`: where it stopped this session, else the resume point, else Spotify's own), sends the follower with a play started from a show page, otherwise queues the next newer one once (claimed before any await, checked against Spotify's queue, never while restored), and skips 15/30 s. Spec: `docs/superpowers/specs/2026-09-30-podcasts-design.md`.

- **Adaptive layout:** the window narrows to 520 pt (and 720 pt high). `WindowLayout` (package) decides what shows; `MainWindow` feeds it the width and `AppModel` mirrors `windowFitsLyrics` / `windowShowsSidebar` / `lyricsWidth` only when they change.
  - Narrowing hides the lyrics first (under ~940 pt with a 300 pt panel; the lyrics button is disabled then and the user's choice returns on widening), then collapses the sidebar (< 720 pt).
  - The toolbar's sidebar button (⌃⌘S) overrides the width until the window crosses 720 pt again; hiding the sidebar gives the lyrics its room.
  - The lyrics panel's left edge drags its width (260–400 pt, saved as `lyricsWidth` in UserDefaults), never past what leaves the page 340 pt.
  - The player bars (classic and Winamp) have three modes: wide, medium (the volume becomes a button with a popover, the device an icon) and compact (two rows: what's playing and the extras, then the transport beside the seek bar). The mode comes from the bar's width and its right-hand group's measured width (`AdaptiveLayout.BarMetrics`): the transport is centred between equal sides, so each needs room for that group. A fixed 960 pt threshold let a long device name ("Someone's MacBook Air") overlap repeat and the lyrics button; wide now starts around 1190 pt with that name.
  - Song tables drop the Album column under 560 pt; page headers (`AdaptiveHeader`) put a 120 pt cover above the title under 520 pt.
  - Views measure with `onGeometryChange(for: <mode>)`, so they update only when a mode flips, and a mode changes only height, never the measured width.
  - Every flip animates (`Animation.layoutChange`, 0.28 s): the lyrics slide, the sidebar collapses, and the player bars' groups and the page header glide between arrangements (`matchedGeometryEffect`). Nothing animates while no mode changes, so CPU stays flat.
  - Every switch has a 40 pt hysteresis (`AdaptiveLayout.hysteresis`): it flips at its threshold and flips back only 40 pt past it. Without it a drag wobbling at 720 pt toggled the sidebar, and with it the page header, back and forth.

- **Popover action row:** under the transport, search, device, volume and lyrics buttons each expand their section (one at a time, a second click collapses), then Open Greedify and Quit. No settings button (⌘, in the app). The lyrics section is a 120 pt window following `lyricIndex`, with the menu-bar lyrics switch.
- **Popover search:** a field in the search section (⌘F opens it). It has its own store (`AppModel.quickSearch`, `SearchStore.quick`: songs, artists, albums and playlists, limit 5) so the window's search page is untouched. While it holds a query, `QuickSearchResults` (5 songs, then 3 of each kind; `quickResults`) replaces the device picker and the quick-play list, scrolling past 320 pt. A click plays (a song alone, the rest as a context); right-click offers "Show in Greedify" and "Add to Menu Bar". Closing the popover clears the query, so the results and their artwork go. Measured: about +2 MB with results, +1 MB per further search (artwork cache, capped).

- **Menu-bar quick play:** right-clicking a playlist, mix, Liked Songs or a song offers "Add to Menu Bar". `AppSettings.quickPlay` (`QuickPlayItem`: URI, name and cover copied when added) lists them in the popover (`App/Views/Popover/QuickPlay.swift`), and a click plays one: a song alone (`.tracks`), anything else as a context. Rows reorder by dragging (`QuickPlayDrop` moves the row live as it passes others) or from the context menu (Move to Top / Up / Down), through `AppSettings.moveInMenuBar(_:to:)`. The app already has a `MenuBarItem` view, hence the model's name.

## Conventions

- **TDD for package code:** watch the test fail, then pass. App-target changes are verified by building and a real run, because there's no app test target.
- **Commits:** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **The user's global preferences apply:** copyable content goes in fenced code blocks, never blockquotes, and never nested in lists.
