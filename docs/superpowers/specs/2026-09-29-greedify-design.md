# Greedify — design spec

Date: 2026-09-29
Status: draft, awaiting review

## 1. Goal

A native macOS Spotify client that replaces the official Spotify desktop app, whose Chromium-based UI uses roughly 300–600 MB of RAM.

**Success criteria**

- Total memory ≤ 70 MB while playing with the window closed (Greedify + librespot, measured with `footprint`).
- Day-to-day listening never needs the official Spotify app on the Mac.
- Media keys control Spotify, and pressing Play never launches Apple Music.
- Playback stays in sync with the user's other Spotify devices (phone, speakers).

**Audience:** one user (the author), on their own Mac with their own Spotify Premium account. Not distributed and not on the App Store.

**Accepted risk:** audio comes from librespot, an unofficial, reverse-engineered Spotify Connect client. It goes against Spotify's terms, can break when Spotify changes its protocol, and carries some account risk. The user accepted this knowingly.

## 2. Constraints from the Spotify Web API (development mode, Sep 2026)

- The app owner needs Premium; at most 5 allow-listed users; quota is shared across the account's client IDs; `429` responses can carry the reason `QUOTA_EXCEEDED`.
- Refresh tokens expire 6 months after the first authorization; refreshing does not extend this.
- Search returns at most 10 results per type per request.
- Not available: recommendations, related artists, audio features, preview URLs, reading Spotify-owned or algorithmic playlists (Daily Mixes, song radio), batch fetches, browse and new releases, artist top tracks.
- Greedify uses **its own client ID only**. It does not borrow other apps' client IDs (as spotify_player does with ncspot's).

## 3. Architecture

Two processes:

| Process | Runs as | Job |
|---|---|---|
| **Greedify.app** | Login item, menu-bar-only (`LSUIElement`); shows a Dock icon only while the main window is open | All UI; all control goes through the Web API |
| **librespot** (bundled binary) | Child process of Greedify, started through the `greedify-speaker` launcher; restarted with back-off if it exits | Spotify Connect device "Studio Mac"; plays audio through CoreAudio; **stops when Greedify quits**. The launcher's watchdog also stops it if Greedify crashes or is force-quit |

All control (play/pause, skip, seek, volume, queue, transfer) goes through the Web API, the same way for the Mac and for remote devices. Syncing across devices comes from Spotify Connect.

### Modules (Greedify.app)

| Module | Responsibility | Depends on |
|---|---|---|
| `SpotifyAPI` (protocol + live implementation) | REST calls, PKCE auth, token refresh, paging, 429/`Retry-After` back-off, typed errors | `TokenStore`, `URLSession` |
| `TokenStore` | Access/refresh tokens in the Keychain | Security framework |
| `PlayerStore` (`@Observable`) | Current track, playback state, devices, local progress between polls | `SpotifyAPI` |
| `LibraryStore` | Playlists, liked songs, albums, artists, pasted mixes; snapshot-aware disk cache | `SpotifyAPI`, `DataCache` |
| `LyricsService` | Fetch from LRCLIB, parse synced lyrics, find the current line | `DataCache` |
| `ImageCache` | Artwork: RAM (`NSCache`, cost = decoded bytes) + disk LRU | — |
| `DataCache` | Disk JSON/text cache with a size cap and LRU eviction | — |
| `MediaKeyTap` | `CGEventTap` for media keys; swallows them | Accessibility permission |
| `MusicBlocker` | Quits Apple Music (`com.apple.Music`) when it launches, if enabled | `NSWorkspace` notifications |
| `LibrespotService` | Registers/unregisters/restarts the agent, writes its arguments, checks it appears in `/me/player/devices` | `SMAppService`, `SpotifyAPI` |
| `LoginItems` | Registers Greedify with `SMAppService.mainApp` | — |
| `Settings` | User preferences (`UserDefaults`) | — |

Views depend only on the stores. Stores depend on `SpotifyAPI` through a protocol, so tests can use a fake.

### Polling

- `/me/player`: every 3 s while the popover or window is open, every 15 s otherwise, and once right after every command.
- Between polls, progress advances locally from `progress_ms` plus the elapsed time.
- While quota back-off is active: every 60 s until a request succeeds.

## 4. Features

### 4.1 Main window

Mockup: `mockups/main-window.html` (approved).

- **Sidebar** (translucent material): Search field (⌘K) · Library: Liked Songs (count), Albums, Artists · Mixes: pasted mixes + "Paste a mix link" · Playlists (owned and followed) · "New Playlist" pinned at the bottom.
- **Content:** a header with artwork, title, song count and duration, and Play / Shuffle / More buttons; a track table (#, title + artist + small artwork, album, like, time). The playing row is accent-coloured with animated equaliser bars (static when Reduce Motion is on).
- **Lyrics panel** (right, 300 pt, toggled from the player bar): background is the current track's artwork, heavily blurred and darkened; past lines faint, current line bright, future lines dimmed; auto-scrolls; footer "Lyrics from LRCLIB".
- **Player bar** (bottom): artwork, title, artist, like · shuffle, previous, play/pause, next, repeat, seek bar with times · lyrics toggle, queue, device picker, volume.

### 4.2 Track right-click menu

Play · Add to Queue · Start Song Radio · Add to Playlist ▸ (New Playlist…, then playlists the user owns or collaborates on) · Remove from This Playlist (only on owned playlists) · Like / Unlike.

### 4.3 Library and playlists

| Action | Endpoint |
|---|---|
| Playlists | `GET /me/playlists` |
| Playlist tracks | `GET /playlists/{id}/items` (paged; refetched only when `snapshot_id` changes) |
| Liked songs / albums / followed artists | `GET /me/tracks`, `GET /me/albums`, `GET /me/following?type=artist` |
| Like / unlike | `PUT` / `DELETE /me/library` with URIs |
| Liked-state check | `GET /me/library/contains` |
| Add / remove tracks | `POST` / `DELETE /playlists/{id}/items` |
| Create playlist | `POST /me/playlists` |
| Add to queue | `POST /me/player/queue` |

### 4.4 Search

- `GET /search`, results grouped into Songs, Albums, Artists and Playlists.
- 10 per group, with "Show more" (offset paging) per group.
- Waits 300 ms after the last keystroke before searching.

### 4.5 Daily Mixes

- The user pastes a mix link (Share → Copy link) and names it. Saved in `Settings`.
- Shown under Mixes. Opening one shows a Play button, and a note that Spotify doesn't let apps show this list's songs.
- Played with `PUT /me/player/play` and `context_uri`.
- The link stays the same while the contents change daily.
- **Must be verified first** (see §8, check C1).

### 4.6 Song radio

- `PUT /me/player/play` with `uris: [track]` only.
- librespot runs with `--autoplay on`, so similar tracks continue after the seed track ends. On remote devices this depends on that device's Autoplay setting.
- This is an approximation; no radio playlist is fetched.

### 4.7 Lyrics

- LRCLIB `GET /api/get?track_name&artist_name&album_name&duration`; fallback `GET /api/search` if there is no exact match.
- Synced lyrics are parsed from LRC timestamps; plain lyrics are shown without highlighting; otherwise "No lyrics found".
- Results cached by Spotify track ID in `DataCache`, including "not found" results for 7 days.

### 4.8 Menu-bar item and popover

Mockup: `mockups/popover.html` (approved; option B simplified).

- **Popover** (`MenuBarExtra`, `.window` style, 300 pt wide): artwork (64 pt), title, artist, like · seek bar · large previous / play-pause / next · device row "Playing on …" ▾ (device list, transfer on click) · "Lyrics in menu bar" switch · "Open Greedify" · gear (Settings).
- **Not in the popover:** search, Up next, volume, shuffle, repeat.

**Menu-bar item:** a template-image icon. With "Lyrics in menu bar" on (switch in the popover and in Settings, one shared setting):

| State | Label |
|---|---|
| Playing, synced lyrics, on a line | Icon + current line, cut off with "…" at about 280 pt |
| Playing, in a gap or instrumental part | Icon + "♪" |
| Playing, only plain lyrics | Icon + song title |
| Paused, no track, or option off | Icon only |

- Line changes are timed from the synced lyrics against the locally advanced position.
- A single timer is scheduled for the next line's timestamp; it's rescheduled after every poll, seek or track change.
- Known limitation: on notched MacBooks, macOS may hide a wide item when the menu bar is crowded.

### 4.9 Window and Dock behaviour

- Opening the main window (from the popover, or from the Dock while it's open): `NSApp.setActivationPolicy(.regular)`, activate, show the window.
- Clicking ×: the window closes and its view tree is released; the policy goes back to `.accessory`, so the Dock icon disappears. The menu-bar item stays.
- ⌘Q quits Greedify and stops librespot, so the music stops. While Greedify isn't running, the Mac isn't a Spotify device. (Changed on 2026-09-29 at the user's request: the music must not outlive the menu-bar app.)

### 4.10 Media keys and Apple Music

- `MediaKeyTap`: a session event tap for `NSEvent.EventType.systemDefined`, subtype 8. It decodes play/pause (16), next (17) and previous (18) on key-down and swallows both key-down and key-up.
  - Play with no active device: transfer playback to the librespot device, then resume the last context.
  - If macOS disables the tap (timeout or user input), re-enable it.
- `MusicBlocker`: on `NSWorkspace.didLaunchApplicationNotification` for `com.apple.Music`, quit it right away. Setting "Block Apple Music", default on. This covers AirPods and headphone buttons, which the event tap can't catch.
- Try `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`. Control Center and AirPods support is **not guaranteed**, because Greedify outputs no audio itself.

### 4.11 First-run setup

Shown once, in a setup window. The steps run in order.

1. **Create a Spotify developer app:** instructions, redirect URI `greedify://callback`, add the user's email to the app's user list; paste the client ID.
2. **Log in:** `ASWebAuthenticationSession`, PKCE, scopes: `user-read-playback-state user-modify-playback-state user-read-currently-playing user-library-read user-library-modify playlist-read-private playlist-read-collaborative playlist-modify-private playlist-modify-public user-follow-read`.
3. **Connect the Mac speaker:** run librespot once with `--enable-oauth` (opens the browser); its credentials are saved under `--system-cache`; then register the agent.
4. **Media keys:** request Accessibility (`AXIsProcessTrustedWithOptions`). This step can be skipped.
5. **Launch at login:** on by default.

If Spotify rejects the custom scheme, step 2 uses a loopback redirect `http://127.0.0.1:<port>/callback` served by a temporary local listener (§8, check C2).

### 4.12 Settings

- **General:** Launch at login · Block Apple Music · Lyrics in menu bar · Appearance (System / Light / Dark).
- **Playback:** device name · audio quality (96 / 160 / 320 kbps) · volume normalisation.
- **Storage:** see §5.
- **Account:** Log out · Reset Greedify (clears tokens, caches, librespot credentials; unregisters the agent).

## 5. Caching

| Cache | Location | Holds | Default | Options |
|---|---|---|---|---|
| Artwork in memory | `NSCache` | Decoded images, decoded at their on-screen pixel size (blurred lyrics background: 96 px) | 15 MB | 15 / 30 / 60 MB |
| App cache | `~/Library/Caches/Greedify/` | Artwork files, lyrics, library and playlist JSON | 300 MB | 100 MB / 300 MB / 1 GB / 2 GB |
| Audio cache | `~/Library/Caches/Greedify/librespot-audio/` (`--cache`) | librespot audio files | Off (`--disable-audio-cache`) | Off / 1 / 2 / 5 GB (`--cache-size-limit`) |

- **Eviction:** least recently used; disk caches are checked at launch and after writes.
- **librespot credentials** live in `~/Library/Application Support/Greedify/librespot/` (`--system-cache`), separate from the audio cache, so clearing never logs out.
- **Settings → Storage:** current size per cache (recomputed when shown), a limit picker, Clear per cache, and Clear All.
- Clearing the audio cache, or changing its limit, restarts the librespot agent (about 1 s of silence).

## 6. Appearance

- Follows the system by default; the override sets `NSApp.appearance`.
- System semantic colours and materials only, plus SF Symbols (the mockup icons are stand-ins).
- One accent colour in the asset catalogue: light `#17A058`, dark `#34D17C`. Used for play buttons, likes, the playing row, the device label and switches.
- The menu-bar icon is a template image.
- The lyrics panel always uses white text over darkened artwork, so it looks the same in both appearances.

## 7. Error handling

Errors appear as small banners that don't block the UI (no modal alerts); they're logged with `os.Logger`, subsystem `com.alperen.greedify`.

| Situation | Behaviour |
|---|---|
| Access token expired | Refresh without asking, retry once |
| Refresh token expired or revoked | "Log in again" banner in the popover and window; one notification if triggered by a media key |
| `429` / `QUOTA_EXCEEDED` | Wait for `Retry-After`; polling at 60 s until recovery; amber status dot |
| `NO_ACTIVE_DEVICE` | Transfer to the librespot device, retry |
| librespot device missing | Popover: "Mac speaker offline" + Restart; if its credentials are invalid, link to setup step 3 |
| Offline (`NWPathMonitor`) | Pause polling, disable controls, resume automatically |
| `403` editing a playlist | Banner: "You can only change playlists you own" |
| Lyrics not found / LRCLIB down | "No lyrics found", no error |
| Event tap disabled / Accessibility revoked | Re-enable the tap; if the permission is gone, show a hint in Settings |

## 8. Verification checks (first implementation step)

These must pass before building on them. Each has a fallback.

| # | Check | Fallback |
|---|---|---|
| C1 | `PUT /me/player/play` with a Daily Mix `context_uri` plays in development mode | Drop Mixes from the sidebar; document the gap |
| C2 | Spotify accepts the `greedify://callback` redirect | Loopback redirect (§4.11) |
| C3 | The Homebrew `librespot` 0.8.0 binary runs when copied into the app bundle (check with `otool -L`: only system libraries) | Build librespot from source with `cargo` and bundle that |
| C4 | librespot `--enable-oauth` + `--system-cache` gives a login that survives restarts | Run the OAuth step whenever librespot reports invalid credentials |

## 9. Testing

**Automated tests** (Swift Testing, no network):

- `SpotifyAPI` with a `URLProtocol` stub: request building, token refresh, 429 back-off, paging, `NO_ACTIVE_DEVICE` handling.
- `PlayerStore`: state updates from poll responses; progress between polls.
- LRC parser and current-line lookup; menu-bar label state (table in §4.8).
- Media-key decoding (pure function: `data1` → action).
- `ImageCache` / `DataCache`: LRU eviction and size caps.
- SwiftUI previews of the main views in light and dark.

**Manual checklist:**

- Media keys work with Music closed; Music never starts, including from AirPods.
- After a reboot: the Greedify menu-bar item and the librespot device are both present.
- × removes the Dock icon; reopening brings it back.
- The phone sees "Studio Mac" and can transfer playback both ways.
- Lyrics in the menu bar follow the song, including after a seek.
- Clear per cache works and does not log out.
- Memory: ≤ 70 MB total while playing with the window closed.

## 10. Out of scope

- Distribution, notarisation, App Store, multiple users.
- Real song radio or recommendations (needs private APIs).
- Showing the tracks inside Daily Mixes.
- Offline downloads.
- Podcasts and audiobooks beyond what appears in playlists.
- Windows and Linux.

## 11. Project

- Repository: `~/source/Greedify`
- Xcode project, SwiftUI app target (macOS 15+), Swift 6, unit test target.
- Bundle ID `com.alperen.greedify`.
- The librespot binary is copied into `Greedify.app/Contents/MacOS/` by a build-phase script.
