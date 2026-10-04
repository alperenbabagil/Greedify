# Podcasts — design spec

Date: 2026-09-30
Status: implemented (2026-09-30)
Builds on: the main spec (`2026-09-29-greedify-design.md`) and the player/library code as it stands after the 2026-09-30 fix batch.

## 1. Goal

Greedify plays and browses podcasts, not just music. Decisions from brainstorming:

- **Scope:** all three levels:
  - followed shows, with a page per show;
  - "Your Episodes", the episodes saved one by one;
  - shows and episodes in search.
- **After an episode ends:** the show's next newer episode plays.
- **Transport while an episode plays:** back 15 s · previous · play/pause · next · forward 30 s (both kinds of button).
- **Model:** an episode is a kind of `Track` (`kind: .episode`), so every existing surface keeps working, and only what must differ checks `kind`.

**Success criteria**

- A followed show's page lists its episodes newest first, with played / in-progress markers. Clicking an in-progress episode resumes where it stopped.
- When an episode finishes, the show's next newer episode starts.
- The player bar, popover, macOS Now Playing, the menu-bar label and AppleScript all show the episode (title, show, cover).
- Search shows Podcasts and Episodes groups.
- A token without the new scope still plays everything; only resume points are missing, and a one-time banner explains why.
- No new daily-quota hot spots: every list is cached (§7).

## 2. Facts the design rests on (Spotify Web API, development mode, 2026)

- Still available: `GET /me/shows`, `GET /me/episodes`, `GET /shows/{id}` and `GET /shows/{id}/episodes`.
- Removed: `PUT`/`DELETE /me/shows|episodes`, `/contains` and the "several" `GET /shows` / `GET /episodes`. Following and saving go through `/me/library` with `spotify:show:` / `spotify:episode:` URIs, which Greedify already uses for tracks. Shows no longer carry `publisher`.
- `resume_point {fully_played, resume_position_ms}` comes only with the scope `user-read-playback-position`.
- A single episode plays with `uris: ["spotify:episode:…"]` and `position_ms`. `context_uri: spotify:show:…` works but always starts the oldest unplayed episode, so it isn't used.
- `/me/player` and `/me/player/currently-playing` return `item: null` for an episode unless asked with `additional_types=episode`.
- `/me/player/queue` already mixes tracks and episodes.
- librespot 0.8's `track_changed` for an episode has `ITEM_TYPE=Episode`, `NAME`, `SHOW_NAME`, `COVERS`, `DURATION_MS`, `URI` and `TRACK_ID`.

## 3. Model (package)

### 3.1 `Track`

It gains four fields:

| Field | Meaning |
|---|---|
| `kind: ItemKind` | `.track` or `.episode`. Decoding without it gives `.track`, so saved last-played data still loads. |
| `show: ShowRef?` | id, name, uri, images; set for episodes. |
| `releaseDate: String?` | The episode's `release_date` (`YYYY-MM-DD`, or a shorter precision). |
| `resumePoint: ResumePoint?` | `fullyPlayed: Bool`, `resumePositionMs: Int`. |

**Decoding:** when the JSON's `type` is `"episode"`, `Track` is built from the episode:

- `artists` = `[ArtistRef(id: nil, name: show.name, uri: "")]`, so no artist link is offered;
- `album` = `AlbumRef(id: nil, name: show.name, uri: show.uri, images: episode.images ?? show.images)`;
- `kind` = `.episode`.

An episode inside `/shows/{id}/episodes` has no `show` object: the caller passes the show in.

`Track.isEpisode` is a convenience for `kind == .episode`.

### 3.2 New types

- `Show`: `id`, `name`, `uri`, `images`, `totalEpisodes: Int?`, `description: String?`.
- `SavedShow`: `{ show }`.
- `SavedEpisode`: `{ episode: Track }`.
- `ShowRef`: `id`, `name`, `uri`, `images`, the part of `Show` an episode carries.

### 3.3 Where episodes appear

- `PlaybackState.item`, with `additional_types=episode`.
- `QueueResponse.currentlyPlaying` / `queue`: episodes are decoded, not dropped.
- `PlaylistItem`: request `additional_types=track,episode`, and keep episodes.
- `SearchResults` gains `shows: Paging<Show>?` and `episodes: Paging<Track>?`, and `SearchType` gains `.show` and `.episode`.

## 4. API (package)

New `SpotifyAPI` methods, all implemented in `LiveSpotifyAPI`:

| Method | Request |
|---|---|
| `savedShows(offset:limit:)` | `GET /me/shows`, limit ≤ 50 |
| `showEpisodes(id:offset:limit:)` | `GET /shows/{id}/episodes`, limit ≤ 50 |
| `savedEpisodes(offset:limit:)` | `GET /me/episodes`, limit ≤ 50 |
| `show(id:)` | `GET /shows/{id}` |

- `playbackState()` adds `additional_types=episode`.
- Follow/unfollow and save/remove go through the existing `saveToLibrary` / `removeFromLibrary` / `libraryContains`.
- `FakeSpotifyAPI` gains the same methods.

## 5. Auth

- `AuthConfig.defaultScopes` gains `user-read-playback-position`.
- `Tokens.hasScope(_:)` splits `scope` on spaces.
- The podcast pages (Your Shows, a show, Your Episodes) show a notice at the top when the stored token lacks the scope: "Log in to Spotify again to see where you stopped in each episode". **Log In…** clears the token and opens the setup window, whose login step asks for the new scope. **×** is remembered in `AppSettings.podcastNoticeDismissed`.
- Without the scope, everything works; `resumePoint` is simply nil.

## 6. Playback (package, `PlayerStore`)

### 6.1 Playing an episode

- `PlayRequest.episode(_ uri: String, at positionMs: Int)` gives `uris: [uri]` and `position_ms`.
- The start position is `resumePoint.resumePositionMs`, or 0 when `fullyPlayed` or when there is no resume point: `Track.startPositionMs`.
- `lastContextURI` is left unchanged, because an episode has no context worth resuming.

### 6.2 Next newer episode

When an episode becomes the current item, from librespot's `track_changed` or a poll showing a new episode:

1. **Find the newer episode.** Get the show's episode list: the show page's cached list if there is one, else `LibraryStore.episodes(of:)`, which fetches and caches it (§7). The list is newest first, so the next newer episode is the one just before the current one.
2. **Queue it**, unless the current one is the newest:
   - `addToQueue(uri:)`, once per current episode (remembered in `PlayerStore.queuedAfter: String?`).
   - Queued items can't carry a position, so the next episode starts at 0.
   - Not queued when the queue already has it (`upNext` from the last `refreshQueue`, if known).
3. **When the episode lacks a show id** (the librespot event carries only the show's name), wait for the delayed metadata poll (§6.6) to fill it in, then do the steps above.

`PlayerStore` gets the episode list through a closure (`episodesOfShow: (String) async -> [Track]`) injected by `AppModel`, so the player doesn't depend on `LibraryStore`.

### 6.3 Skip

- `skipBack()` seeks to `max(0, position − 15 000)`.
- `skipForward()` seeks to `min(duration − 1000, position + 30 000)`.
- Both use the existing `seek(toMs:)`: no new endpoint, and the local clock moves at once.

### 6.4 Now Playing and media keys

`NowPlayingInfo` (package) gains `isEpisode`. While it's true, `NowPlayingPublisher` (app):

- enables `skipBackwardCommand` (preferred interval 15) and `skipForwardCommand` (30), mapped to the skip methods;
- keeps next/previous enabled;
- disables the skip commands again for songs.

The artist field carries the show name. The media keys keep previous/next.

### 6.5 Lyrics and the menu-bar label

- Episodes skip the LRCLIB lookup: `Lyrics.none`, and the panel reads "No lyrics for podcasts".
- The menu-bar label shows the episode title the way it shows a song title.

### 6.6 librespot events

- `greedify-event` also forwards `SHOW_NAME`.
- `LibrespotEvent.parse` turns an `Episode` `track_changed` into `.trackChanged(Track)`:
  - `kind` `.episode`;
  - `artists` = `[ShowName]`;
  - `album` = show name + covers;
  - `show` = `ShowRef(id: nil, name: SHOW_NAME, uri: "", images: covers)`.
- The existing delayed metadata poll fills in the ids, as it does for songs.

### 6.7 Last played and AppleScript

- `LastPlayed` saves episodes like songs, since `kind` is encoded.
- Restoring an episode plays `PlayRequest.episode(uri, at: savedPosition)`.
- AppleScript's `current track` is unchanged: `artist` and `album` are the show name.

## 7. Library and caches (package, `LibraryStore`)

- **`shows: [Show]`, `loadMoreShows()`:** pages of 50, with the first page cached on disk for 1 hour (`lib:shows`).
- **`savedEpisodes: [Track]`, `loadMoreSavedEpisodes()`:** the same, cached for 1 hour (`lib:episodes`).
- **`episodes(of show: Show) async -> [Track]`:**
  - It loads a show's episodes, newest first, in pages of 50 as the page scrolls (`loadMoreEpisodes(of:)`).
  - The first page is cached on disk until the next local midnight (`lib:show:<id>`).
  - `PlayerStore`'s next-episode closure uses the same cache.
- **Follow and save flags:** reuse the like-flag cache and `/me/library/contains` (1 day), keyed by URI, so shows and episodes share the path with tracks.
  - `isFollowing(show)`, `toggleFollow(show)`, `isSaved(episode)` and `toggleSave(episode)` sit on top of that path.
  - In practice these are `isLiked` / `toggleLike` generalised to a URI.

## 8. UI (app)

### 8.1 Sidebar and routes

- Under Library, a **Podcasts** section with **Your Shows** and **Your Episodes**.
- Routes: `.shows`, `.show(Show)` and `.episodes`.
- The debug route hook gains `shows`, `episodes` and `show:N`.

### 8.2 Your Shows

A `CoverGrid` of `library.shows` (square covers). It loads more as it scrolls; clicking a show opens its page.

### 8.3 Show page: `ShowView`

- **Header:** `DetailHeader` with kind "Podcast", the show name, the episode count, and the description (one line).
  - **Play:** starts the newest episode that isn't fully played, from its resume point.
  - **Follow / Following:** replaces Shuffle.
- **Rows:** `EpisodeTable` of `EpisodeRow`s, newest first, loading 50 more at the end.

### 8.4 `EpisodeRow`

- The same row height as song rows (`theme.rowHeight`), with a 44 pt cover (the episode's, else the show's).
- **Title, first line:** medium weight; the accent colour when current.
- **Second line:** the release date and duration, for example "28 Sep · 54 min". In Your Episodes and search, the show's name comes first.
- **Status, on the right:**
  - in progress: a 40 pt thin bar and "12 min left";
  - fully played: a ✓, with the title at secondary opacity;
  - neither: nothing.
- **Click** (a single click, as in Spotify): `play(.episode(uri, at: track.startPositionMs))`.
- **Right-click menu:** Play, Play from Start, Add to Queue, Save / Remove from Your Episodes, Go to Show.

### 8.5 Your Episodes

An `EpisodeTable` of `library.savedEpisodes`, with the show name on each row.

### 8.6 Search

- Two more groups after Playlists: **Podcasts** (a `CoverGrid` of shows) and **Episodes** (an `EpisodeTable`).
- Each has "Show more", as today.
- It's the same single request, with `type=track,album,artist,playlist,show,episode`.
- Search returns episodes without their show, so those rows show the date and duration only, with no "Go to Show". Fetching each episode's show would cost quota per result.

### 8.7 Player bar and popover

- For an episode, the artist line shows the show name.
- **Title and artwork:** they open the show (`.show(Show)`, built from `track.show` when it has an id; otherwise the link waits for the metadata poll).
- **Like button:** saves or removes the episode.
- **Transport:** while `track.isEpisode`, `TransportControls` shows back 15 s (`gobackward.15`) and forward 30 s (`goforward.30`) on either side of previous/next, with `.skinnedControl(.button)` / `.largeButton`.

### 8.8 Lyrics panel

"No lyrics for podcasts" for episodes.

### 8.9 Theming

Everything goes through the themed helpers.

## 9. Failure handling

- **No scope:** no resume points, the banner (§5), everything else normal.
- **Unplayable episode** (`is_playable == false`, or a 404 on play): the row is at 50 % opacity, and playing it shows the existing error banner.
- **Next-episode lookup fails, or the current episode is the newest:** nothing is queued.
- **An episode from librespot before the Web API knows it:** shown from the event; the ids arrive with the metadata poll (§6.6).
- **Search quota exhausted:** the existing per-endpoint back-off, with no special case.

## 10. Testing

Package tests use Swift Testing, written to fail first.

- **Decoding:**
  - an episode from `/me/player` (with `additional_types`), the queue, playlist items and search becomes `Track` with `kind .episode`, `show`, `releaseDate` and `resumePoint`;
  - an episode inside `/shows/{id}/episodes` takes the passed-in show;
  - `LastPlayed` JSON without `kind` decodes as a song.
- **API:**
  - the paths and `limit` values of the four new methods;
  - `additional_types=episode` on `playbackState`;
  - search with `show,episode` (`StubTransport`).
- **Auth:** `Tokens.hasScope`, and the new default scope.
- **librespot:** an `Episode` `track_changed` line becomes an episode `Track` with the show name and covers.
- **`PlayerStore`:**
  - playing an episode sends its resume position; fully played means 0;
  - the next newer episode is queued once, and never for the newest;
  - an episode without a show id waits for the metadata poll;
  - skip back/forward clamp;
  - a restored last-played episode starts at its saved position.
- **`LibraryStore`:**
  - shows, saved episodes and show-episode paging and caches, with their expiry (1 h / next midnight);
  - follow/save through `/me/library` URIs.
- **App:**
  - a Debug build, then the installed build;
  - Your Shows → a show → play an in-progress episode (the log shows `position_ms`) → seek near its end, and the next newer episode starts;
  - skip buttons, search groups, show links, the banner, and Now Playing skip commands;
  - `scripts/measure-memory.sh`, with no change beyond noise.

## 11. Out of scope

- Playback speed: neither librespot nor the Web API supports it.
- Downloads and offline episodes.
- Video podcasts, and audiobooks.
- Marking an episode played or unplayed: the Web API has no write for resume points.
- Chapters.
