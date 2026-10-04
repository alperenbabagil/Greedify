# Skinned player controls — design spec

Date: 2026-09-30
Status: implemented (2026-09-30). The user's review: better, but the bar should match the skin far more closely (follow-up D) and list backgrounds should use the skin's background colour instead of the repeated art (follow-up E).
Builds on: `2026-09-30-theme-images-design.md`. This spec lifts its out-of-scope item "other skin sprites (buttons, sliders, number digits)" and replaces its tiled player-bar strip.

## 1. Goal

An imported Winamp skin should style the player's controls, not sit behind them. Today the player bar tiles all of `main.bmp` (Winamp's whole main window, with its own buttons, time display and title bar), and our controls float on top of copies of Winamp's controls.

Decisions from brainstorming:

- **Background:** the skin's panel colour, flat. No tiling.
- **Buttons:** our own vector buttons, drawn in colours sampled from the skin's button sprites (face gradient, bevel, glyph, pressed, "on"). Crisp at any size.
- **Seek and volume bars:** the skin's own sprites, smoothed with an edge-aware pixel-art upscaler (not a plain nearest-neighbour blow-up).
- **Times:** the skin's digit sprites (`numbers.bmp` / `nums_ex.bmp`), smoothed the same way.
- **Scope:** the main window's player bar and the menu-bar popover.

**Success criteria**

- `base-2.91`, `Winamp5_Classified_v5.5` and `diablo_ii`, re-imported, show:
  - no tiled `main.bmp` in the bar;
  - vector buttons in the skin's colours;
  - the skin's seek groove and handle, and its volume ramp;
  - the skin's digits for the times.
- Glyphs stay legible: glyph against face ≥ 3:1, otherwise the theme's text colour.
- Themes imported before this change load and show a plain panel instead of the tiles. The System theme and the built-ins look exactly as today.
- The memory profile in CLAUDE.md doesn't move beyond a few MB while a skin is selected.
- Switching themes live, and resize and zoom, never crash.

## 2. Sprite coordinates

The classic skin format fixes every sprite's position. Slices are plain rectangles (x, y, w, h) in bitmap pixels.

| Sheet (expected size) | Part | Rect |
|---|---|---|
| `cbuttons.bmp` (136×36) | play, normal / pressed | (23, 0, 23, 18) / (23, 18, 23, 18) |
| `shufrep.bmp` (92×85) | shuffle on, normal | (28, 30, 47, 15) |
| | repeat on, normal | (0, 30, 28, 15) |
| `posbar.bmp` (307×10, some skins 248–307 wide) | groove | (0, 0, 248, 10) |
| | handle, normal / pressed | (248, 0, 29, 10) / (278, 0, 29, 10) |
| `volume.bmp` (68×433) | fill frame *i* = 0…27 | (0, 15·*i*, 68, 13) |
| | handle, pressed / normal | (0, 422, 14, 11) / (15, 422, 14, 11) |
| `numbers.bmp` (99×13) | digit *d* = 0…9 | (9·*d*, 0, 9, 13) |
| `nums_ex.bmp` (108×13) | digit *d*, minus | (9·*d*, 0, 9, 13), (99, 0, 9, 13) |
| `main.bmp` (275×116) | control area, for the panel colour | (0, 88, 275, 28) |

File names match case-insensitively, as today. `nums_ex.bmp` wins over `numbers.bmp` when both exist.

A sheet that is missing, or smaller than the rects it needs, gives `nil` for its part only. A posbar narrower than 307 px but at least 277 px keeps the groove and the normal handle and reuses it as pressed. A `volume.bmp` at least 418 px tall but under 433 px (some skins ship the frames without handles) keeps its frames, and the handle is drawn as a vector knob in the palette's face colours.

## 3. Import (package)

### 3.1 `WinampSkin`

It reads the sheets above in addition to what it reads today, and decodes them to RGBA with the existing BMP decoder.

### 3.2 `SkinControlPalette`

It's sampled from `cbuttons.bmp` and `shufrep.bmp`. All colours are sRGB hex, the same as the theme's other colours.

| Field | How it's sampled |
|---|---|
| `faceTop`, `faceBottom` | The play button's inner area (inset 2 px), the rows at 25 % and 75 % of its height: each row's median. The glyph is a minority of any row. |
| `highlight` | The median of the button's top row and left column, corners excluded. |
| `shadow` | The median of its bottom row and right column. |
| `glyph` | The inner pixels clearly unlike their own row's face (squared RGB distance > 0.02 from the row's median). Its median is the colour, and none means no glyph. |
| `pressedFaceTop`, `pressedFaceBottom`, `pressedGlyph` | The same, from the pressed play button. |
| `on` | The shuffle-on sprite: the pixel with the greatest saturation × brightness (the lit indicator). |
| `panel` | The most common colour of `main.bmp`'s control area, quantised to 4 bits per channel before counting. |

**Contrast rule:** if `glyph` against the average face is below 3:1, `glyph` becomes `nil` and the app uses the theme's `text`. The same applies to `pressedGlyph`.

### 3.3 Images kept

The importer crops these, re-encodes them as PNG (the images spec's 512 KB per-image limit still applies), and stores them unscaled:

- `seekBar`: groove and handles, as a 307×10 strip in `posbar.bmp`'s own layout.
- `volume`: the whole `volume.bmp`.
- `digits`: a 108×13 strip, digits 0–9, a blank, and a minus when the skin has one.

### 3.4 Theme format

Additive keys; `version` stays 1.

```json
"controls": {
  "faceTop": "#6f7fa6", "faceBottom": "#4b5a80",
  "highlight": "#b8c4e0", "shadow": "#1c2440",
  "glyph": "#e8ecf8", "pressedFaceTop": "#4b5a80", "pressedFaceBottom": "#3a4768",
  "pressedGlyph": "#ffffff", "on": "#7cff4f", "panel": "#4a5a86"
},
"images": { "backdrop": "…", "pixelFont": "…", "seekBar": "…", "volume": "…", "digits": "…" }
```

Decoding is lenient per key: a bad colour drops that field, and a bad image drops that image. `controls` is written only when it has at least `faceTop`, `faceBottom` and `panel`.

## 4. Smoothing: `PixelScaler` (package)

- **Algorithm:** Scale2x (EPX) run twice gives 4×.
  - Exact integer rules, no blur, so edges stay sharp and diagonals and curves come out stepped-smooth.
  - The app then draws the 4× image at its on-screen size with high-quality interpolation. At 2–4× display scale that's a downscale, so it stays crisp.
  - If real skins look rough in review, xBRZ replaces Scale2x behind the same function. The spec doesn't change.
- **Signature:** `PixelScaler.scale4x(_ image: RGBAImage) -> RGBAImage`, pure and nonisolated.
- **Where it runs:** in `ThemeImages`, off the main actor, as it does for the backdrop.
- **What's scaled:** only what's drawn: the groove, 2 handles, the 28 volume frames, the 2 volume handles and 12 digit glyphs. That's about 2.5 MB of RGBA in total, held by the resolved theme and freed with it.

## 5. App

### 5.1 `ResolvedTheme`

It gains `controls: SkinControls?`, holding the palette as SwiftUI `Color`s and the scaled images as `CGImage`s (seek groove, handles, 28 volume frames, volume handles, digits). It's non-nil only for a theme with a `controls` section.

### 5.2 Bar background

- With `controls`, `ThemedSurface(.bar)` fills the bar with `panel`.
- `BackdropStrip` is deleted: no theme tiles `main.bmp` in the bar any more.
- A theme with a backdrop but no `controls` (imported before this change) gets its `surface` colour in the bar.
- `themedTile()` is deleted: with no art in the bar, the tiles have nothing to separate the controls from.

### 5.3 `SkinButtonStyle` (vector)

- **Shape:** a rounded rectangle, radius 3 pt, filled with the linear gradient `faceTop` → `faceBottom`.
- **Bevel:** a 1 pt `highlight` edge on the top and left, and a 1 pt `shadow` edge on the bottom and right.
- **Glyph:** the SF Symbol in `glyph`, or the theme's `text` if `glyph` is nil.
- **Pressed:** the pressed gradient and glyph, with the highlight and shadow edges swapped.
- **Active** (shuffle and repeat on, lyrics shown): the glyph uses `on`.
- **Sizes:** in the player bar, play/pause is 44×32 pt and every other button 32×24 pt. The popover uses its current larger sizes.
- **Where:** the player bar's buttons (transport, shuffle, repeat, like, lyrics, queue, settings) and the popover's transport buttons, applied through a `.skinnedControl(_:active:)` modifier that leaves the view unchanged without skin controls, so the views don't branch on the theme.
- The device picker is a text menu, not an icon button, and keeps its accent-coloured label.

### 5.4 Seek bar

- It's a skin variant inside `ThemedSlider`, chosen when `controls` has a groove.
- **Groove:** a 3-slice. The left and right 4 source px keep their shape and the middle stretches. It's 20 pt tall.
- **Handle:** the scaled handle, 29×10 source px drawn at 58×20 pt. The pressed image shows while dragging.
- There's no separate played fill; the handle's position shows progress, as in Winamp.

### 5.5 Volume

- It's also a skin variant inside `ThemedSlider`.
- **Background:** the frame for the current level, frame index `round(value / 100 × 27)`, drawn at the slider's size (84×16 pt in the bar, volume.bmp's aspect).
- **Handle:** the scaled handle on top (17×14 pt), the pressed one while dragging.

### 5.6 Times: `SkinDigits`

- It draws `m:ss` (or `h:mm:ss`) from the skin's digit shapes, 13 pt tall: pixels closer to the ink than to any blank-cell colour are ink, the rest transparent (a dotted LED background blurred into the strokes when drawn as a picture). The shapes are tinted with the ink colour, pushed to 4.5:1 against the panel and the popover's `raised`.
- **Colon:** two squares in the digits' ink: digit 8's most common colour other than the blank cell's (the LED background).
- **Width:** fixed per character, so the layout doesn't jump.
- **Where:** `ProgressBar` uses it for both labels when `controls` has digits; otherwise the monospaced text stays.

### 5.7 Title

Unchanged: the pixel-font title from the images spec.

## 6. Failure handling

- **Missing sheet:** each part falls back independently. No `volume.bmp`: the volume bar is today's `ThemedSlider` in the skin's colours, while the buttons and seek bar stay skinned. No palette: the buttons use today's bevel style.
- **Low-contrast glyph:** the theme's text colour (§3.2).
- **Bad data in a theme file:** only that key is dropped (§3.4).
- **Scaling failure** (it can't normally fail, but a zero-sized image is possible): that image is `nil`, and its part falls back.

## 7. Testing

Package tests use Swift Testing, written to fail first.

- **Slicing:**
  - A synthetic skin (`SkinFixture` / `BMPBuilder`) with each sheet at its standard size gives the expected rects.
  - Each missing or undersized sheet gives `nil` for its part only.
  - A 277–306 px posbar reuses the normal handle as pressed.
- **Palette:**
  - A synthetic play button with a known gradient face, bevel and glyph gives those colours.
  - A glyph at 2:1 contrast gives `nil`.
  - The shuffle-on indicator is found.
  - The panel is the dominant colour.
- **Scaler:**
  - Scale2x's documented 3×3 neighbourhood cases, flat areas and single pixels.
  - `scale4x` equals `scale2x` run twice.
  - The output size is exactly 4×.
- **Theme file:** round-trip with `controls` and the three images; an old file without them; a bad colour and a bad image each dropped alone.
- **Import end to end:** a synthetic `.wsz` gives a theme with `controls` and the images.
- **App:**
  - A Debug build, then the installed build with each of the three skins switched live (`debug.theme`), plus resize and zoom.
  - The user judges the look: no screenshots can be taken from the session.
  - `scripts/measure-memory.sh` before and after, with a skin selected.

## 8. Out of scope

- The eq and pl windows (`eqmain.bmp`, `pledit.bmp` frames).
- `titlebar.bmp`, `monoster.bmp`, `balance.bmp`, `playpaus.bmp`.
- The kbps/kHz display.
- The stop and eject buttons. Greedify has no stop, and eject has no meaning here.
- Modern (`skin.xml`) skins: they're still rejected.
