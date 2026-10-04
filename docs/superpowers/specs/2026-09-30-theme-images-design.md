# Theme images and skin fonts — design spec

Date: 2026-09-30
Status: implemented
Builds on: `2026-09-30-themes-design.md` (themes and Winamp skin import). This spec lifts two of its out-of-scope items: textures and background images, and the bitmap fonts in `text.bmp`.

## 1. Goal

Imported Winamp skins should look like their skin, not just borrow its colors:

- The skin's artwork (`main.bmp`) shows behind the main window. It is strongest behind the lyrics and faint behind the lists, and the player bar wears a strip of it (mockup option C, chosen in brainstorming).
- The skin's fonts carry over:
  - The font named in `pledit.txt` is used throughout the UI, with near-matching when macOS lacks the exact family.
  - The now-playing title in the player bar is drawn in the skin's pixel font (`text.bmp`).

**Success criteria**

- `diablo_ii` and `base-2.91`, re-imported, show their artwork, the pixel-font title and a matched font ("Copperplate Gothic Light" → Copperplate).
- Text stays readable over any backdrop: text ≥ 4.5:1 and secondary text ≥ 3:1 against the worst-case blended background.
- Themes without images, the System theme and the built-ins look exactly as they do today.
- The memory profile in CLAUDE.md doesn't move.
- Switching live (debug hook, with resize and zoom) never crashes.

## 2. Theme format: `images`

An optional group in the `.greedifytheme` JSON. The format stays `version` 1, since the keys are additive.

```json
"images": {
  "backdrop": "<base64 PNG>",
  "pixelFont": "<base64 PNG>"
}
```

- In the package, `Theme.images: Theme.Images` has `backdrop: Data?` and `pixelFont: Data?`, holding PNG bytes. `Theme.Images()` is empty.
- **Decoding stays lenient, per image.** Invalid base64, bytes that don't start with the PNG signature, or more than 512 KB of decoded data drop only that image. A file without `images` decodes exactly as before.
- **Encoding** writes `images` only when at least one image is present, so image-free themes are byte-identical to today's files.
- Both images are optional for hand-written themes too. The backdrop may be any PNG up to 512 KB, and the pixel font must follow the grid in §4.

## 3. Import

`WinampSkin` additionally reads two files, still from the fixed list of names; nothing else is read:

- `main.bmp` → `backdropPNG`: the whole bitmap, re-encoded as PNG at its native size through ImageIO (`CGImageDestination`).
- `text.bmp` → `pixelFontPNG`: re-encoded the same way, only if it's at least 155×18 pixels (the glyph grid). Otherwise it's ignored.

`SkinThemeMapper` copies both into `theme.images`. A skin without either image still imports; it just has no image.

**Font matching.** It replaces today's yes/no `fontAvailable` parameter. Importers take `installedFonts: [String]` (the family names; the app passes `NSFontManager.shared.availableFontFamilies`). The package picks the family with `FontMatcher.bestFamily(for:among:) -> String?`, trying in order:

1. an exact family match, ignoring case;
2. a whole-word prefix: the longest installed family whose words are a leading run of the wanted name's words, ignoring case. "Copperplate Gothic Light" → "Copperplate". "Arial Black" does not match "Arial Narrow", but it does match "Arial".
3. a fixed Windows-to-Mac table: "MS Sans Serif" → "Geneva", "Small Fonts" → "Monaco", "Terminal" → "Monaco", "System" → nil;
4. nil, meaning the system font.

The API changes are:

- `SkinThemeMapper.theme(fromArchive:fileName:installedFonts:)`
- `SkinThemeMapper.theme(from:fileName:installedFonts:)`
- `ThemeStore.theme(fromFile:fileName:installedFonts:)`
- `ThemeStore.importFile(data:fileName:installedFonts:)`

`AppModel.importTheme` passes the list it already builds, and tests pass literal arrays.

Themes imported before this change are not upgraded. Re-importing the `.wsz` produces the new theme, which gets a numbered name if the old one is still there.

## 4. Pixel font

`PixelFont`, in the package, is pure. It is built from PNG data (decoded through ImageIO into a `CGImage`) and cuts 5×6-pixel glyph cells.

Glyph map (the one Webamp uses), as (row, column):

| Characters | Cells |
|---|---|
| `A`–`Z` | row 0, columns 0–25 |
| `"` `@` | row 0, columns 26, 27 |
| space | row 0, column 30 |
| `0`–`9` | row 1, columns 0–9 |
| `…` `.` `:` `(` `)` `-` `'` `!` `_` `+` `\` `/` `[` `]` `^` `&` `%` `,` `=` `$` `#` | row 1, columns 10–30, in that order |
| `Å` `Ö` `Ä` `?` `*` | row 2, columns 0–4 |

Mapping a character:

1. Uppercase it.
2. If it's in the map, use its cell.
3. Otherwise fold the diacritic (`folding(options: .diacriticInsensitive)`, plus `ı`→`I`), and use the result's cell if there is one.
4. Otherwise use a space.

Example: "Oğlan qızı" → "OGLAN QIZI".

API:

- `PixelFont.cell(for: Character) -> (row: Int, column: Int)`
- `PixelFont.glyphs(for: String) -> [(row: Int, column: Int)]`
- `PixelFont(png: Data)`, which exposes `glyphImage(row:column:) -> CGImage?`. Glyphs are cropped once and cached.

## 5. Backdrop readability: `BackdropPlan`

`BackdropPlan`, in the package, is a pure function of the backdrop's pixels and the theme's colors. It decides how opaque each panel is over the art and, when the theme's text is too dim for the art to show, how far the text colors are lifted.

- **Input:** the decoded backdrop `CGImage` (`make(image:colors:base:)`; `make(backdrop: Data, …)` decodes and delegates), the theme's `background`, `surface`, `text`, `textSecondary` and `lyricsText`, and its `base`.
- **Worst case:** the image is sampled (nearest pixel, never averaged) down to at most 65,536 pixels; a skin's 275×116 `main.bmp` is read whole. Luminance is computed once per pixel. For a dark base, the worst case is the pixel at the 95th percentile of relative luminance (bright art fights light text); for a light base, the 5th percentile (dark art fights dark text). The percentile is found with a 1024-bin histogram, and only the pixels in the bin that holds it are ordered.
- **Readability:** a panel color `blend(worst, areaColor, α)` is readable when every checked color reaches its ratio against it and stays on its own side of it (lighter than the panel on a dark base, darker on a light one), so a panel can't pass by flipping the polarity.
- **Alpha per area,** each the smallest α in 0.35…0.95 that is readable, solved continuously (bisection) and rounded up to 0.01; 1 (opaque) if even 0.95 fails:
  - `sidebarAlpha`, over `surface`: the sidebar and the player-bar tiles. Checks `text` ≥ 4.5:1 and `textSecondary` ≥ 3:1.
  - `contentAlpha`, over `background`: the detail content. Same checks.
  - `lyricsAlpha`, over `background`: the solid-mode lyrics. Adds `lyricsText` ≥ 4.5:1. It checks a superset of content's colors over the same fill, so it can't need less than content; when a dim `lyricsText` needs more, `contentAlpha` is raised to match, so `lyricsAlpha ≤ contentAlpha` always holds and the art never shows less behind the lyrics than behind the lists.
- **Text lift:** dim text on busy art would need near-opaque panels (diablo_ii: lists 1.0, lyrics 0.9), and the art would disappear. Dimming the art first is the same as raising the panel alpha, so the headroom has to come from the text. `text`, `textSecondary` and `lyricsText` are lifted together, keeping hue and saturation: their HSL lightness moves a share `lift` of the remaining range away from the background (toward white on a dark base, toward black on a light one). `lift` runs 0, 0.05 … 0.6, and the plan takes the first step where `lyricsAlpha` ≤ 0.6 (at least 40% art behind the lyrics) and `sidebarAlpha`, `contentAlpha` ≤ 0.8. When no step gets there, the plan keeps the alphas of the largest lift but uses the smallest lift that already reaches them, so a lift that no longer lowers any alpha doesn't wash out the colors for nothing (white text can't get lighter). At `lift` 0 the colors are the theme's own, unchanged.
- **Output:** `BackdropPlan(sidebarAlpha:contentAlpha:lyricsAlpha:lift:text:textSecondary:lyricsText:)`. The app uses the returned colors in place of the theme's whenever the backdrop shows.

## 6. Rendering (app)

- `ResolvedTheme` gains `backdrop: CGImage?`, `pixelFont: PixelFont?` and `plan: BackdropPlan?`. They are all nil for themes without images and for System. On each theme change (and at launch), `AppModel` publishes the image-free theme at once, then decodes the images and plans the backdrop in a detached task (`ThemeImages`) and publishes the theme again with them; a newer change cancels an older load. So neither launch nor a theme switch waits on image work. `backdrop` is nil whenever `plan` is. With a plan, `text`, `textSecondary` (and the tertiary color derived from it) and `lyricsText` are the plan's lifted colors (§5).
- **Image size limit:** before decoding, `ThemeImage.cgImage` reads the pixel size from the image header and refuses anything over 2048×2048 (4,194,304 px). A flat PNG under the 512 KB file limit can still describe hundreds of megabytes of pixels. This applies to the backdrop, the pixel font and skin bitmaps on import.
- **Backdrop view:** at the `MainWindow` root, behind the split view, in `.background { }` with `.ignoresSafeArea()`. It is `Image(decorative: backdrop, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fill)`, clipped. A background never sizes its parent, so the constant `.fixedMinimum` columns and the constraint-loop rules are unaffected. It reports where it draws (global coordinates) through `onGeometryChange`; `MainWindow` passes that rect down as the `backdropFrame` environment value.
- **Sidebar art:** the sidebar column sits on an AppKit vibrancy view that hides the window's backdrop, so a translucent fill alone would show the vibrancy. The sidebar draws the art itself under its fill (`WindowAlignedBackdrop`): the same aspect-filled image at `backdropFrame`, offset by the sidebar's own global origin and clipped, so the art lines up across the seam. Only when a backdrop is present.
- **Translucent panels:** when a backdrop is present, the fills that are opaque today become translucent:
  - `themedSurface(.content)` → `background.opacity(contentAlpha)`;
  - `themedSurface(.surface)`, `.bar` and the sidebar fill → `surface.opacity(sidebarAlpha)`;
  - `themedSurface(.inset)` (the sidebar's New Playlist inset, already on the sidebar fill) → no fill of its own over a backdrop, `surface` otherwise;
  - the solid-mode lyrics background → `background.opacity(lyricsAlpha)`.
  Without a backdrop nothing changes.
- **Skinned player bar:** when a backdrop is present, the bar's background is the backdrop scaled to the bar height (`interpolation(.none)`) and tiled horizontally, clipped to the bar. Its three groups (artwork and title, transport and progress, and the right-hand controls) each sit on a `surface.opacity(sidebarAlpha)` tile with `buttonRadius` corners. The right-hand group's tile goes outside its 250 pt minimum frame, so the tile padding never eats the minimum. The strip draws nothing at zero size, caps the tile count at 64 and snaps each tile's width to whole device pixels, so neighbouring tiles meet without a seam. The bar's height stays `theme.playerBarHeight`.
- **Pixel-font title:** `PixelText(text:)` draws the glyphs with `Canvas`, at an integer scale of 2 (10×12 pt per glyph), tinted with the theme's `text` color (template rendering) and never smoothed. It replaces the title `Text` in `PlayerBar` when `pixelFont != nil`. The artist line stays in the theme font. A title wider than its space is clipped at a glyph boundary; there is no marquee. It carries an accessibility label with the real title and the static-text trait. `ImageRenderer` is never used (CLAUDE.md).
- **Lyrics:** in solid mode with a backdrop, the art shows through at `lyricsAlpha`, and plain lyrics and "No lyrics found" use `lyricsText` at full strength (the plan checked that color; dimming it further would undo the check). In artwork mode the lyrics keep the blurred album cover.
- **Fonts:** the `fonts.family` from matching flows through the existing `ResolvedTheme.font(...)`. Nothing new is needed there.

## 7. Error handling

| Case | Behaviour |
|---|---|
| A theme image with bad base64, not a PNG, or over 512 KB | Drop that image; the theme loads |
| A backdrop PNG that won't decode | No backdrop; the panels stay opaque |
| A theme image over 2048×2048 pixels | Refused from its header before decoding: no backdrop or pixel font |
| A pixel-font PNG under 155×18 or that won't decode | No pixel font; the title uses the theme font |
| A title character missing from the font | Fold the diacritic, otherwise a space |
| A font name with no match | The system font |
| A skin without `main.bmp` or `text.bmp` | The import succeeds without that image |

## 8. Testing

TDD in `GreedifyKitTests`:

- **`ThemeImagesTests`:**
  - a round trip;
  - bad base64, bytes that aren't PNG, and over 512 KB each drop only that image;
  - old files are unchanged;
  - image-free themes encode without `images`.
- **`WinampSkinTests` additions:**
  - `main.bmp` and `text.bmp` become PNGs at their native size (check the decoded dimensions);
  - a small `text.bmp` is ignored;
  - a skin without them still imports.
- **`FontMatcherTests`:**
  - exact matches, ignoring case;
  - "Copperplate Gothic Light" → "Copperplate";
  - "Arial Black" → "Arial" when only Arial and Arial Narrow are installed;
  - the Windows table;
  - no match → nil.
- **`PixelFontTests`:**
  - the cells for A, Z, 0, 9, `…`, `#`, `Å` and `*`;
  - lowercase draws as uppercase;
  - "Oğlan qızı" → OGLAN QIZI;
  - unknown characters → space;
  - glyph cropping from a fixture PNG gives 5×6 images with the right pixels.
- **`BackdropPlanTests`:**
  - a white fixture needs a higher alpha than a black fixture on a dark theme;
  - alphas stay in 0.35…0.95 in hundredths, or 1 when opaque, and lyrics alpha ≤ content alpha;
  - with the returned colors at the chosen alphas, the worst-case blends really give text ≥ 4.5, secondary ≥ 3 and lyricsText ≥ 4.5 (lyrics); 0.02 less fails;
  - a diablo-like fixture (dim olive on black, 6% bright orange) is lifted: lyrics ≤ 0.6, the others ≤ 0.8, hue within 3°, and one lift step less misses the targets;
  - readable colors (a black fixture, base-2.91's green) aren't lifted;
  - an unreadable text color is rescued by the lift; a grey background no lift can fix goes opaque without lifting; out-of-reach targets keep the smallest lift that reaches the best alphas;
  - a 4-megapixel image plans in well under a second.
- **`ThemeImagesTests` addition:** a flat PNG under 512 KB but over 2048×2048 gives no image, no plan and no pixel font.
- **Existing importer tests** move to `installedFonts:`.
- **App**, verified by build and a real run:
  - re-import `diablo_ii` and `base-2.91` (they are in `~/Downloads`);
  - run the live-switch stress with the `debug.theme` hook across a backdrop theme, Classic and System, with resize and zoom;
  - run `scripts/measure-memory.sh`.
  - The user checks the looks.

## 9. Out of scope

- A scrolling marquee.
- The pixel font anywhere except the player-bar title.
- A backdrop in the popover.
- `pledit.bmp` frame tiles and other skin sprites (buttons, sliders, number digits).
- Images for built-in themes.
- Automatic upgrade of themes that were already imported.
