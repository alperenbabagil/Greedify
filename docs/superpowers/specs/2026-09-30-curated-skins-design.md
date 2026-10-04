# Curated skins — design spec

Date: 2026-09-30
Status: implemented (2026-10-01). Beyond the design: `radial`, `layers` and `image` materials, theme credits, a one-row centred bar, Liquid Glass off.
Replaces: the user-facing Winamp import of `2026-09-30-themes-design.md` §3, the backdrop and tiling of `2026-09-30-theme-images-design.md`, and the sprite-based controls of `2026-09-30-skinned-controls-design.md`. It also settles the follow-ups D (the play bar matches the skin) and E (list backgrounds use the skin's own look).

## 1. Goal

Skins stop being something the user imports. We (the developer and Claude) import a skin with a tool, study it, hand-tune the result, and ship it as a built-in theme.

A curated theme looks like its Winamp original, a **near-replica**, but it's drawn **natively**:
- the skin's materials (flat, gradient, dotted LCD, brushed, noise, small repeated patterns), bevel lighting, LCD display, buttons, sliders, list style and fonts are recreated as SwiftUI drawing, sharp at any size;
- they cover **every surface**: the play bar, sidebar, lists, headers, popover and lyrics;
- they're fitted to Greedify's layout; no bitmaps from the skin are pasted into the UI.

Adding a skin later is a repeatable, generic process: run the converter, tune the recipe with live reload, ship it (§6).

**Success criteria**

- Three curated themes ship: **Winamp Classic** (base-2.91), **Winamp5 Classified** and **Diablo II**. The user signs off on each after tuning, as looking like its skin.
- *Update (2026-10-02):* Diablo II was removed before the public release (its pictures were third-party game art). Two curated themes ship.
- Settings has no import, and no user themes load in Release.
- Adding a fourth skin needs no Swift code: tool → recipe → tuning → bundle.
- System and the four existing built-ins (Classic, Modern, Paper, High Contrast) look exactly as today.
- Memory with a curated theme selected is no higher than today's figures, and is expected lower: no backdrop image or sprite atlases.
- Live switching, resize and zoom never crash.

## 2. The recipe (`style`)

A curated theme is a `.greedifytheme` file with today's keys (colours, fonts, shapes; the base) plus a `style` section. The format stays `version` 1, since the keys are additive. Every key is optional and decoded leniently: a missing or invalid value falls back to the base look for that element only.

### 2.1 Primitives

**Material:** what a surface is made of.

```json
{ "kind": "solid", "color": "#2A3350" }
{ "kind": "gradient", "angle": 90, "stops": [{ "color": "#6070A0", "at": 0 }, { "color": "#405080", "at": 1 }] }
{ "kind": "dotGrid", "base": "#101C48", "dot": "#24346A", "pitch": 2, "size": 1 }
{ "kind": "brushed", "base": "#B8BCC4", "streak": "#9EA3AC", "density": 0.35, "seed": 7 }
{ "kind": "noise", "base": "#2B2420", "amount": 0.08, "seed": 3 }
{ "kind": "pattern", "width": 4, "height": 4, "scale": 1, "colors": ["#..", "… width×height, row-major"] }
```

- `pitch`, `size` and `scale` are in points.
- `angle` is in degrees, where 90 means top to bottom.
- `seed` makes `brushed` and `noise` stable, so they never flicker between redraws.

**Bevel:**

```json
{ "style": "raised" | "sunken" | "double", "light": "#C0C8E0", "dark": "#202840", "width": 1 }
```

**Text style:** `{ "font": "pixel" | "system" | "<family>", "size": 13, "weight": "regular|semibold|bold", "color": "#hex", "glow": 0 }`.
- `pixel` means the skin's `text.bmp` letterforms (`images.pixelFont`).
- `glow` is a blur radius in points, drawn in the text colour.

### 2.2 Regions

```json
"style": {
  "materials": { "window": M, "sidebar": M, "header": M, "bar": M, "popover": M, "lyrics": M },
  "bevels": { "panel": B, "bar": B },
  "divider": "#hex",
  "rows": {
    "normal":    { "fill": M, "text": "#hex", "secondary": "#hex" },
    "alternate": { "fill": M },
    "hover":     { "fill": M },
    "selected":  { "fill": M, "text": "#hex" },
    "playing":   { "text": "#hex" }
  },
  "lcd": { "material": M, "bevel": B, "digits": "segment" | "pixel" | "mono", "text": "#hex", "info": "#hex", "glow": 2 },
  "button": {
    "shape": "rect" | "rounded" | "circle" | "pill", "radius": 3,
    "face": M, "bevel": B, "glyph": "#hex", "glyphWeight": "semibold",
    "pressed": { "face": M, "glyph": "#hex" }, "active": "#hex"
  },
  "slider": {
    "groove": { "material": M, "bevel": B, "height": 6 },
    "fill": { "kind": "none" | "solid" | "ramp", "colors": ["#hex", "…"] },
    "thumb": { "shape": "rect" | "rounded" | "circle", "width": 22, "height": 12, "face": M, "bevel": B }
  },
  "volume": { "…": "same shape as slider; defaults to slider" },
  "text": { "title": T, "body": T, "secondary": T, "header": T },
  "bar": { "layout": "winamp" | "classic", "height": 110, "artwork": true }
}
```

A region a recipe leaves out uses today's themed look for that region.

### 2.3 The `winamp` bar layout

At our width, about 110 pt tall, in three rows:

1. **Display** (about 56 pt):
   - an optional 48 pt artwork tile;
   - the **LCD block**: big time digits (`lcd.digits`) and a small play/pause/stop indicator;
   - a flexible **title LCD strip** with the scrolling title (marquee, `text.title`) and an info line underneath (artist or show; `lcd.info`);
   - LCD surfaces use `lcd.material` and `lcd.bevel`.
2. **Seek:** a full-width `slider`, with the elapsed/remaining time shown in the LCD block, as Winamp does.
3. **Buttons** (about 32 pt), all in `button` style:
   - left: previous, play/pause and next (plus back 15 / forward 30 for episodes), then shuffle and repeat as toggles that light up in `button.active`;
   - right: like, lyrics, queue, device (a menu with a button-styled label), the `volume` slider and settings.

`bar.material` and `bevels.bar` frame the whole bar. `classic` is today's `PlayerBar` layout, used by every theme without a recipe.

**Popover:** a compact version with the same pieces:
- an LCD strip with the title and time;
- the seek slider;
- the transport row in `button` style;
- all on `materials.popover`.

## 3. Rendering (app)

**Style model** (package): `Theme.Style` and its value types:
- `Material`, `Bevel`, `TextSpec`, `LCDSpec`, `ButtonSpec`, `SliderSpec` and `RowStyles`;
- `BarSpec`, with `layout`, `height` and `artwork`.

It's decoded with the theme, and all of it is `Sendable` and `Equatable`.

**Resolution:** `ResolvedTheme.style`, a resolved copy with SwiftUI colours, is built once per theme switch.

**Components** (`App/Views/Shared/Recipe/`, one small file each):

- **`MaterialFill`:**
  - `solid` and `gradient` are native shapes.
  - `dotGrid`, `pattern`, `brushed` and `noise` are drawn from a small tile: `MaterialTile.make(material, scale)` in the package builds a `CGImage` of at most 64×64 px in code, from the recipe values and a seeded generator.
  - The tile repeats with `ImagePaint`. Tiles are cached per material and display scale.
  - There's no `ImageRenderer` and no full-size image.
- **`BevelFrame`:** raised, sunken or double edges in the bevel's colours.
- **`LCDPanel`:** its material with a sunken bevel.
  - `SegmentDigits` draws 7-segment glyphs (0–9, `:`, `-`) as paths, with an optional glow.
  - `PixelText` gains `glow`, and `MonoDigits` covers the `mono` style.
- **`RecipeButtonStyle`:** its shape, face, bevel and glyph, with pressed and active variants. Disabled buttons are dimmed.
- **`RecipeSlider`:** its groove, fill (a `ramp` is a horizontal gradient across the filled part) and thumb, with the drag behaviour of today's `ThemedSlider`.
- **`WinampBar` and `WinampPopoverPlayer`:** the §2.3 layouts. `PlayerBar` and `PopoverView` pick them when `style.bar.layout == .winamp`.
- **Existing helpers read the style**, so views don't branch on the theme:
  - `themedSurface(.content / .surface / .raised / .bar)` draws `materials.window / sidebar / popover / bar`;
  - `themedRow` draws the row styles, and `SectionHeader` and `ThemedDivider` use `header` and `divider`;
  - the lyrics panel draws `materials.lyrics` with `text.body`.

**Removed from the app:**
- `ThemeBackdrop`, `WindowAlignedBackdrop`, `BackdropPlan` and `ThemeImages`' backdrop path;
- `SkinControls`, `SkinButtonStyle`, `.skinnedControl`, the sprite branches of `ThemedSlider`, and `SkinDigits`;
- `SkinControlImages`;
- the `images.backdrop`, `seekBar`, `volume` and `digits` theme keys, which are ignored when read.

`images.pixelFont` stays. `RGBAImage` and `PixelScaler` move under the converter's use only, if it still needs them.

## 4. Built-ins and migration (package + app)

- **The curated recipes live in `Theme/Builtin/`:** `winamp-classic.greedifytheme`, `winamp5-classified.greedifytheme` and `diablo-ii.greedifytheme`.
  - `Theme.builtinOrder` becomes `system, classic, modern, paper, high-contrast, winamp-classic, winamp5-classified, diablo-ii`.
  - Each curated theme's `source` is `Winamp skin <file>.wsz`.
- **`ThemeStore` loads built-ins only in Release.**
  - The user Themes folder is no longer read, written or created.
  - Import, drag-and-drop, duplicate, delete and "Show in Finder" are removed from `ThemeStore`, `AppModel` and the Settings Themes tab.
- **Migration, on launch:** if `AppSettings.themeID` names a user theme file, it's mapped to the curated theme whose `source` file name matches, using the `source` recorded in the user file when it can still be read, or else the file name's stem. Otherwise it maps to `builtin.system`. The user's old files stay on disk, untouched and ignored.

## 5. Converter tool (package)

A SwiftPM executable target, `skin-recipe`, in `Packages/GreedifyKit`:

```bash
swift run --package-path Packages/GreedifyKit skin-recipe <skin.wsz> --name "<Theme Name>" --out <dir>
```

- The CLI is thin. The analysis is a public `SkinRecipeMaker` in GreedifyKit, which reuses `WinampSkin`, `ZipReader` and the BMP decoding, so it's testable.
- **What it measures** (each field noted in `"notes"` in the output for the tuner, then deleted):
  - **Palette:** the frame, panel, LCD background and text colours from `main.bmp` and `pledit.txt`, plus highlight and shadow from the play button's edges.
  - **LCD:** in `main.bmp`'s display box (the time area at about 24,26 to 99,42 and the title area at about 111,24 to 263,36), it checks whether the pixels repeat a 2–3 px pattern.
    - If they do: `dotGrid` with that pitch and the two most common colours.
    - If not: `solid`.
  - **Digits:** `segment` when the lit pixels of `numbers.bmp` / `nums_ex.bmp` digit 8 form seven straight bars (the rows and columns of lit pixels match a 7-segment mask), otherwise `pixel` (the font is kept as `images.pixelFont`).
  - **Buttons:** the shape is `circle` when the play sprite's corner pixels are background-coloured in a rounded pattern, `rounded` when only the extreme corners are, and `rect` otherwise. The face is a `gradient` from the rows at 25 % and 75 %, and the glyph is the contrasting ink.
  - **Sliders:** the groove colour from `posbar.bmp`, and the thumb size and colours from its handle. The volume fill is a `ramp` from `volume.bmp` frames 0, 14 and 27.
  - **Rows:** from `pledit.txt`.
  - **Materials:** `brushed` or `noise` is suggested when `main.bmp`'s large areas show high-frequency variation. Streaks along one axis mean `brushed`, otherwise `noise`, with `amount` from the variance.
- **Output:**
  - `<slug>.greedifytheme`, the draft recipe;
  - `<slug>.contact.png`, a reference sheet of `main.bmp` with the sampled points and boxes marked, plus the button, posbar, volume and digit sprites at 4×. It's for the tuner's eyes and is never bundled.

**Live tuning, Debug builds only:**
- Recipes in `~/Library/Application Support/Greedify/Recipes/` load as extra themes with the ids `dev.<file>`.
- A file watcher reloads a changed recipe and re-applies it if it's selected. `debug.theme "dev.<file>"` selects it.
- Unreadable files are skipped, with a log line (`com.alperen.greedify` / `app`).

**Shipping:** copy the tuned file to `Theme/Builtin/`, add its slug to `builtinOrder`, and commit. `docs/adding-a-skin.md` documents the three steps, and CLAUDE.md points to it.

## 6. Adding a skin later (the generic method)

1. `skin-recipe some.wsz --name "Some Skin" --out ~/Library/Application\ Support/Greedify/Recipes/`
2. In a Debug build, select `dev.some-skin`, and edit the recipe while looking at `some-skin.contact.png` and the original skin, until it looks right. No Swift changes are needed.
3. Move the file to `Theme/Builtin/`, add it to `builtinOrder`, build and commit.

## 7. Failure handling

- **An invalid recipe key:** that element uses the base look.
- **A recipe file that won't decode:** built-ins can't ship broken (§8's strict test); dev recipes are skipped with a log line.
- **The pixel font is missing or unreadable:** `pixel` text falls back to `mono` digits and the system font.
- **A material tile can't be built** (a zero or oversize tile is refused): a solid fill of the material's base colour.
- **Migration can't read an old theme file:** the file name's stem is used; if nothing matches, the theme is System.

## 8. Testing

Package tests use Swift Testing, written to fail first. Tests never contain real skins; they use synthetic ones from `BMPBuilder`, `SkinFixture` and `SkinSheets`.

- **Recipe codec:**
  - every primitive and region round-trips;
  - an invalid value is dropped alone;
  - a theme without `style` equals today's decoding.
- **Strict built-ins:** each curated recipe decodes with no dropped keys (a strict decoding mode that reports unknown or invalid keys, used only by tests).
- **Material tiles:** the `dotGrid` tile has the pitch-sized repeat with the dot at the right pixel; the `pattern` tile reproduces its matrix; `noise` and `brushed` are identical for the same seed and differ for another.
- **Converter analysis:**
  - palette sampling;
  - dot-grid detection on a generated dotted display, and none on a flat one;
  - bevel colours;
  - segment vs pixel digits, on a 7-segment 8 and on a non-segment glyph;
  - button shape (circle, rounded, rect);
  - the volume ramp;
  - the whole `.wsz` → recipe pipeline.
- **Migration:** a user theme id maps to its curated theme by `source`, by file stem, or to System.
- **ThemeStore:** Release loading lists built-ins only; Debug loading adds `dev.` recipes from a given folder, and a changed file reloads.
- **App:**
  - a Debug build;
  - the live-reload loop;
  - each curated theme switched live with resize, zoom and the popover open;
  - `scripts/measure-memory.sh` (no higher than today);
  - the user's sign-off per theme, after tuning sessions with screenshots.

## 9. Out of scope

- Modern (`.wal`, `skin.xml`) skins.
- Skin cursors, sounds, visualizers and the equalizer window's look.
- Curated skins beyond the three; later ones go through §6.
- Per-skin Swift code: a recipe primitive is added instead, when a future skin needs one.
