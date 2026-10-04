# Winamp window: the whole window looks like Winamp

Approved in chat on 2026-10-03. Extends the curated-skins spec (`2026-09-30-curated-skins-design.md`).

## Goal

The two Winamp skins (Winamp Classic, Winamp5 Classified) already have a Winamp player bar. The rest of the window
is still a modern layout in green. This spec makes the whole window read as Winamp: the song lists become a
playlist editor, the page header becomes a slim strip, the panels get Winamp frames, and the bar gains the
analyser, the readouts and Winamp's button row. Every change is a recipe option, never an `isWinamp` check, so a
future skin can opt in.

## Recipe additions (package, `Style`)

All of these are optional and read leniently, as every recipe key is.

- **`list`** (`ListSpec`): `layout` is `cards` (the default, today's rows) or `playlist`; there's also `rowHeight`
  (default 18) and `font` / `size` (a `TextSpec`-style font choice; default the system font at 11 pt).
- **`pageHeader`** (`PageHeaderSpec`): `layout` is `hero` (the default) or `strip`; `artwork` is the cover's size
  in a strip (default 48).
- **`frame`** (`FrameSpec`): Winamp's panel frame.
  - `face` is the frame's material and `bevel` its edge; `thickness` (default 3) is how wide it is.
  - `title` (`TitleStripSpec`): `material` (the striped band), `height` (default 14), `text` (colour), and
    `prefix` (e.g. `"WINAMP"`). The app supplies the label: LIBRARY, PLAYLIST, LYRICS.
- **`bar`** gains:
  - `analyser`: a list of colours, top to bottom (the bars' ramp). Absent means no analyser.
  - `readouts`: a bool (kbps / kHz / stereo in the LCD).
  - `transport`: `winamp` (the flush ⏮ ▶ ⏸ ⏹ ⏭ ⏏ row) or `plain` (the default, today's).
- **`text.lyrics`**: a `TextSpec` for the lyric lines (font, size, colour); the current line takes the playing
  row's colour.

## Analyser bars (package, `Analyser`)

`Analyser.bars(seed:count:)` returns `count` heights in 0…1. They're worked out from the seed (the track's id),
so the same song always shows the same shape. It's a pure function that's tested, uses no randomness, and has
a falloff toward the high bands like a real spectrum. The view draws it once per song and play state (dimmed when
paused, empty when stopped), with no timer.

## App

- **Song list (`TrackRow`, `TrackTable`):** with `list.layout == .playlist`, a row is one line at
  `rowHeight`: `N. Artist - Title`, then the album (when there's room), the like heart (shown on hover or when
  liked, drawn in the text colour), and the time. There's no artwork. The column header is the same small font.
  The row styles (normal, hover, selected, playing) work as before.
- **Page header (`DetailHeader`):** with `strip`, the cover is `artwork` pt and sits beside the kind, title and
  meta, with Play and Shuffle as the skin's recipe buttons (`skinnedControl`) in a row to the right. The title uses
  the recipe's title font (pixel with glow when the skin has one). Shows and artist pages use `DetailHeader`
  already; their headers follow.
- **Frames (`WinampFrame`):** the sidebar, the page and the lyrics panel are each drawn inside a frame: a title
  strip at the top (`WINAMP LIBRARY`, `WINAMP PLAYLIST`, `WINAMP LYRICS` when the prefix is "WINAMP"), and the
  face and bevel around the sides and bottom.
  - The frame is padding plus a background inside each column's fixed-minimum content, so it never changes a
    column's minimum (CLAUDE.md, NavigationSplitView constraint loop).
  - The frame never takes clicks (`allowsHitTesting(false)`), like every background.
- **Sidebar search:** with a frame, the field's background is the LCD's material with a sunken bevel. The
  `.searchable` field is AppKit's; the sidebar can only style around it, so this part is best-effort.
- **Player bar (`WinampBar`):**
  - The analyser sits in the LCD beside the time.
  - The readouts are small text under the time: `320 kbps  44 kHz  stereo`, lit while playing and dim
    otherwise. The bitrate is `AppSettings.bitrate` (what librespot was told).
  - The `winamp` transport is flush small buttons:
    - previous, play, pause, stop (pause and seek to 0), next, eject;
    - eject focuses search, as Winamp's opens a file;
    - shuffle and repeat stay as toggles beside it.
- **Lyrics (`LyricsPanel`):** `text.lyrics` sets the lines' font and size; the current line takes the playing
  row's colour.
- **Recipes:**
  - Both Winamp recipes turn all of this on.
  - Classic: grey frame, gold-grey stripes, green on black.
  - Classified: silver frame, blue stripes, white on blue; its round buttons become rounded rectangles.

## Budgets (don't regress)

- CPU: nothing new redraws per frame. The analyser and readouts change only with the song or the play state.
  Window open and playing stays at about 1–2%.
- Memory: the frames are materials and bevels (no images). With the window open on Classic, about 76 MB today; it
  should stay within a few MB of that.

## Testing

- **Package (TDD):**
  - the new keys decode and encode, round trip included;
  - unknown keys fail in strict mode;
  - both built-in recipes still decode strictly, and use the new options;
  - `Analyser.bars` is deterministic, in range and the right length.
- **App:**
  - Debug build, then snapshots of both skins at 1280, 900 and 600 pt wide, plus the popover;
  - System and the plain themes stay unchanged (snapshot);
  - CPU check with `top` and `sample`, then `measure-memory.sh`, then `install.sh`.

## As built (2026-10-03)

- **Measured:** with the window open, Classic and Classified are 89 MB (before: 76 and 75); System is 71 MB. CPU is
  1–1.6% with the window open and a long title scrolling.
- **Frames:** the frames are colour strips (`EdgeBevel`, `FrameFace`). Panel-sized `Canvas` bevels cost +27 MB in
  backing buffers. The toolbar band takes the skin's `header` material (its title text is light).
- **Analyser:** the analyser is plain colour layers, one band per ramp colour. It shows when the bar is at least
  1100 pt wide, or in the compact bar; in between, the title keeps the room.
- **`PixelText`:** it became a cached bitmap. As a `Canvas`, the scrolling title made the GPU take ~50 MB for a
  second every few seconds.
- **`Marquee`:** it steps 4 pt eight times a second, like Winamp's title, instead of a 60 fps animation (~10% CPU
  while scrolling).
- **Readouts:** they're one line, `320 KBPS   44 KHZ   STEREO`.
- **Not done:**
  - The sidebar's search field is AppKit's `.searchable` field and keeps its own look.
  - The labelled recipe buttons (`RecipeLabelButtonStyle`) apply wherever `themedButton` is used under a strip
    header, sheets included.

## Follow-up: title bar, sidebar button, search (approved 2026-10-03)

- **Title bar:** with a frame, the window title is removed. The band under the toolbar becomes Winamp's title bar:
  stripes, with `GREEDIFY` over the page column (`TitleBarBand`), kept clear of the traffic lights and the sidebar
  button.
  - The band reaches only upward: sideways, the page column's safe area runs under the sidebar.
  - The label falls back to white or black when the strip's text colour doesn't read on the band (Classified).
- **Sidebar button:** it's `skinnedControl(.small)`.
- **Search:** AppKit's `.searchable` field gives way to `SkinSearchField` at the top of the sidebar: the LCD's
  material in a sunken bevel, a clear button, and Escape clears it. The window's search focus (⌘K, eject, the
  `focusSearch` hook) lands there.
- **Measured:** Classic 86 MB with the window open, 0.2% CPU idle.

## Follow-up: Winamp5 Classified follows its skin (approved 2026-10-03)

- **Colours:** sampled from the `.wsz` in `~/Downloads`:
  - title bar steel `#9BA3B5` → `#3F4C6A` → `#0E1829` → `#1C2C51`, with a silver groove (black edged);
  - LCD dots `#002263` on `#284A89`;
  - analyser rows alternating white and `#274987` (`viscolor.txt`);
  - playlist font Arial (`pledit.txt`).
- **New keys:**
  - `frame.title.background`, `stripeHeight`, `rounded`, `font`, `size`, `weight`;
  - `lcd.radius`;
  - `button.labelShape`.
- **Toolbar band:** the header fill covers only the band; stretched over the whole column, a gradient showed just
  its top.
- **Measured:** Classified 89 MB with the window open, 0.3% CPU idle; Classic unchanged.

## Follow-up: Classified as the original's main window and playlist (approved 2026-10-03)

- **Panels:** set into a silver body: `frame.radius` 7, `frame.outline`, 8 pt thick, flat `#1C3D7D`, 20 pt title
  strips.
- **Player bar:** `bar.mainWindow` (`WinampMainBar`, 124 pt):
  - a wide LCD: time over analyser, `Artist - Title (3:41)`, artist, kbps / kHz, MONO / STEREO, and a silver shelf
    with the volume, device, lyrics and queue;
  - the full-width seek bar;
  - the round transport with eject, and the shuffle / repeat tab with LEDs.
- **Footer:** `list.footer` (`PlaylistFooter`), on the frame's face: new playlist, queue, a mini LCD with
  position / length and the tiny transport, and the folder button (search).
- **Scroller:** `list.scroller` (`PageScrollView` + `.skinScroller()`), on the pages and the lyrics; the sidebar
  keeps the system scroller.
- **Not done:** the equalizer (Spotify has no EQ).
- **Measured:** Classified 88 MB with the window open, 0.3% CPU idle. Classic and System are unchanged.

## Follow-up: user review (2026-10-04)

- **Footer:** the playlist footer is removed (`list.footer` and `PlaylistFooter` are gone). The user didn't want it.
- **Buttons:** as the original's: glossy elliptical faces (`#FFFFFF` → `#AFAFAF` → `#BDC3CE`), a `#181D27` outline,
  a `#B3B9C6` halo, 3 pt apart, in a recessed channel (`bar.transportWell`). The bevel is dropped when a recipe
  gives an outline or halo. The shelf in the LCD is raised silver.
- **Title bar:** framed skins make the window's title bar transparent: the split view's title-bar backdrop covered
  the page column's band in dark grey on screen.
- **Measured:** Classified 89 MB with the window open, 0.3% CPU idle.

## Follow-up: back to the classic bar layout (2026-10-04)

- **Bar:** the user asked for Classified's player bar to use Classic's layout. `bar.mainWindow` and
  `WinampMainBar` are removed, and Classified's bar is 88 pt again.
- **Kept:** the original's glossy buttons, with the transport in its recessed channel (`bar.transportWell`).

## Follow-up: the popover as Winamp (approved 2026-10-04)

- **Layout:** a framed skin's popover is the original's stacked windows:
  - the `WINAMP` main window: LCD with time, analyser, title and kbps / kHz, the seek bar, and shuffle / transport /
    repeat;
  - the action buttons as skin buttons on the frame;
  - the `WINAMP PLAYLIST` window: the open section and the quick-play list as numbered playlist lines.
- **Rows and fields:** search results are playlist lines too (`Artist - Title`, what a result is, dim on the
  right). The search field is the LCD style, devices are dense lines, and the lyrics use the skin's lyric type.
- **Unchanged:** System and the plain themes keep the old popover.
- **Measured:** ten popover renders grow the app as on System (+1 MB).
