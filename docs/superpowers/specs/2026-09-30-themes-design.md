# Greedify themes and Winamp skins — design spec

Date: 2026-09-30
Status: implemented

## 1. Goal

Let the user change how Greedify looks: its colors, fonts, and the shapes of its buttons, cards, rows and sections. Themes can be written by hand or imported from classic Winamp `.wsz` skins.

**Why:** Spotify users have asked for skins for years. Spotify marked the idea "Not Right Now" in 2023. The existing workaround, Spicetify, patches the official client and breaks on Spotify updates. Greedify draws its own UI, so its themes can't be broken by Spotify updates. Themes are meant as a headline feature for an open-source release.

**Success criteria**

- Every built-in theme and at least two real imported skins look coherent across the main window, the popover and the lyrics panel.
- Switching themes is live, with no relaunch, and can't bring back the NavigationSplitView constraint-loop crash.
- The memory profile doesn't move. A theme is a few dozen values, and no skin bitmap stays loaded.
- A broken or partial theme file never crashes the app and never hides the other themes.

**Licensing:** Greedify ships no Winamp skins, since each skin belongs to its own author. Users import `.wsz` files they download themselves. The built-in themes are original and don't copy Winamp or Spotify artwork or branding.

## 2. The theme model

`Theme` is `Codable` and `Sendable`, in `GreedifyKit/Theme/`.

| Group | Keys |
|---|---|
| metadata | `version` (Int, currently 1), `name`, `author?`, `source?` |
| `base` | `light` \| `dark`. Drives `NSApp.appearance` for what we can't theme: context menus, scroll bars, title bar, text cursors, the Settings window. |
| `colors` | `background`, `surface`, `raised`, `text`, `textSecondary`, `accent`, `onAccent`, `selection`, `divider`, `lyricsText`. Each is `#RRGGBB` or `#RRGGBBAA`. |
| `fonts` | `family?` (nil means the system font), `scale` (0.8–1.4), `titleWeight` (`regular` \| `semibold` \| `bold` \| `heavy`) |
| `shapes` | `cardRadius`, `buttonRadius`, `artworkRadius`, `rowRadius` (0–24), `borderWidth` (0–3), `buttonStyle` (`flat` \| `outlined` \| `filled` \| `bevel`), `density` (`compact` \| `regular`) |
| `lyrics` | `artwork` (blurred cover, today's look) \| `solid` (theme colors) |

**Decoding rules:**

- Every key is optional. A missing value comes from a fixed default palette for the file's `base` (`Theme.defaults(for: .dark/.light)`, the macOS dark and light system colors written out as hex). A missing `base` means `dark`.
- A value that's out of range is clamped. A color that won't parse falls back per value.
- Unknown keys are ignored. A newer `version` still loads whatever it can.
- A file that isn't JSON at all fails with a reason and is shown as broken. It never throws past `ThemeStore`.

**File format:** one `.greedifytheme` file per theme, containing UTF-8 JSON. User themes live in `~/Library/Application Support/Greedify/Themes/`.

**Built-in themes** ship as package resources (`resources: [.process("Theme/Builtin")]`):

- **System:** today's look. Native materials and the system accent color, and it follows the Appearance setting. This is a special case: its `ResolvedTheme` uses dynamic system colors, not fixed hex values.
- **Classic:** green-on-black and Winamp-flavored: `bevel` buttons, 2 pt radii, `compact`, `solid` lyrics.
- **Modern:** dark, a soft accent, large radii, `filled` buttons.
- **Paper:** light, warm and `outlined`.
- **High Contrast:** black and white, a yellow accent, 2 pt borders.

## 3. Winamp `.wsz` import

This lives in `GreedifyKit/Theme/Winamp/` and has three pure parts.

**1. `ZipReader`** reads the central directory and supports `stored` and `deflate` entries (raw deflate through Apple's `Compression` framework, `COMPRESSION_ZLIB`).

- Archives over 10 MB and entries over 5 MB uncompressed are refused.
- Entry paths are only matched, never used to write files.
- Lookup is by the last path component, ignoring case, so skins inside a subfolder work.

**2. `WinampSkin`** holds only these sources, each optional:

| File | Parsed into |
|---|---|
| `pledit.txt` | `normal`, `current`, `normalBG`, `selectedBG`, `font`. Keys are matched ignoring case, a missing `#` is tolerated, and other sections are ignored. |
| `viscolor.txt` | up to 24 RGB colors. `//` comments and extra whitespace are tolerated. |
| `main.bmp` | the dominant color of the frame, sampled from the title-bar and border strips (decoded through ImageIO) |
| `genex.bmp` | the Winamp 2.9 color swatch pixels at their known x positions on row 0 (the same positions Webamp reads) |

**3. `SkinThemeMapper`** turns a `WinampSkin` into a `Theme`:

- **Main colors:** `background` = `normalBG`, `text` = `normal`, `selection` = `selectedBG`.
  - `genex.bmp` values override these when present.
  - With no `pledit.txt`, they come from `main.bmp`, with `text` picked for contrast.
- **Accent:** the candidates are `current`, `viscolor` 2–17 and the `main.bmp` frame color, kept only with saturation ≥ 0.25 and at least 1.5:1 against `text`.
  - The most saturated wins, preferring candidates that already contrast 3:1 with `background`; ties go to the first. It's then pushed toward black or white (which keeps its hue) until it reaches 3:1.
  - With no candidate left, it's the base's default accent, pushed to 3:1 the same way. It never falls back to `text`.
  - `onAccent` is black or white, whichever contrasts more.
- **Derived colors:**
  - `surface` = the `main.bmp` frame color. If it's within ΔL 4 of `background`, it's `background` shifted 8% in lightness away from the base instead.
  - `raised` = `surface` blended 6% toward `text`.
  - `textSecondary` = `text` blended 35% toward `background`.
  - `divider` = `text` at 15% opacity.
  - `lyricsText` = `text`.
- **Base and contrast guard:**
  - `base` = `dark` when white text contrasts more with `background` than black does, otherwise `light`, so the base matches the text's polarity.
  - The contrast guard pushes `text` toward white or black until it reaches 4.5:1 against `background`, `surface` and `raised` (the sidebar and headers draw it there), and `textSecondary` until 3:1 against `background` and `surface`.
  - If even black or white can't reach 4.5:1 on the shifted `surface`, the surface is shifted the other way instead.
  - `selection` is moved toward `background` until `text` reads on it at 4.5:1.
- **Font and shapes:** `fonts.family` = `font`, but only if `NSFontManager` has it (checked in the app and passed in, so the mapper stays pure). Shapes use `bevel`, radii of 2, `borderWidth` 1 and `compact`. `lyrics` is `solid`.
- **Metadata:** `name` = the file name without `.wsz`, and `source` = "Winamp skin *<file name>*".
- **Errors** (`ThemeImportError`, with a plain-words message):
  - `unsupportedModernSkin`: the file is a `.wal`, or the zip has `skin.xml`;
  - `noColorSources`: none of the four files is present;
  - `unreadable`: a bad zip or an oversized file.

Importing writes a `.greedifytheme` file. The `.wsz` isn't kept. A clashing name gets " 2", " 3" and so on.

## 4. ThemeStore

`@MainActor @Observable`, in the package, owned by `AppModel`.

- **State:** `themes: [ThemeEntry]`, where each entry is the id (the file name, or `builtin.<name>`), the `Theme` or a load error, and whether it's built in. `selectedID` is persisted in `AppSettings.themeID`, which defaults to `builtin.system`.
- **Operations:**
  - `reload()`: rescans the folder. Runs at launch, when the Themes tab appears, and after an import.
  - `select(_:)`.
  - `import(url:)`: handles `.wsz` and `.greedifytheme`. Only local files are accepted, up to 10 MB for a skin and 1 MB for a theme file. The read and parse run off the main actor (`ThemeStore.theme(fromFile:fileName:fontAvailable:)`), and the result is saved on it (`add(_:)`).
  - `duplicate(_:)`.
  - `delete(_:)`: user themes only. The file goes to the Trash, and deleting the selected theme selects System.
  - `current`: the selected theme, or System if the selected one is missing or broken.
- **File I/O is injected** (a small protocol over the folder), so tests use an in-memory folder.

## 5. Rendering

- **`ResolvedTheme`** is built in the app from `current`, once per change. It holds SwiftUI `Color`s, `Font`s and the shape values, is exposed as `@Environment(\.theme)`, and is injected at the roots of `MainWindow`, `PopoverView` and `LyricsPanel`.
- **`AppModel.applyAppearance()`:** the System theme keeps using `settings.appearance`. Any other theme sets `NSApp.appearance` from `base`. In General settings, the Appearance picker is disabled with "Set by the theme" when the theme isn't System.

**Themed components** go in `App/Views/Shared/Theme.swift`:

| Component | Replaces |
|---|---|
| `ThemedButtonStyle(role: .primary/.secondary/.icon)` | `.borderedProminent`, `.bordered`, `.plain` buttons in themed views. `bevel` draws a 1 pt highlight on the top-left edge and a 1 pt shadow on the bottom-right, swapped while pressed. |
| `ThemedSlider` | `Slider` in `ProgressBar` and the volume control, with its own track, fill and knob. Bevel themes get a square knob. |
| `Card` | the `CoverGrid` tiles, `QueuePopover`, the popover's background |
| `SectionHeader` | sidebar sections, the track table header |
| `ThemedRow` | hover and current-track highlights in `TrackRow` and the sidebar rows |
| text roles (`.themed(.primary/.secondary/.accent)`, `.themedFont(.body/.title/.caption)`) | `.foregroundStyle(.secondary/.tertiary)`, `Color.accentColor`, `.font(...)` in themed views |

**Other view changes:**

- **Sidebar:** `List` stays, for scrolling and sections, but without the `selection:` binding. Rows are buttons that set `model.route` and draw a `ThemedRow` highlight. The `List` uses `.scrollContentBackground(.hidden)` over `surface`. The arrow keys no longer move through the sidebar; the user accepted this.
- **Player bar and sidebar footer:** `surface` replaces `.bar`, and `divider` replaces `Divider()`.
- **Content:** `background` fills the detail column.
- **Lyrics panel:** `artwork` keeps today's view. `solid` uses `background`, `lyricsText` at the existing opacities, and `accent` for the current line.
- **Layout safety:**
  - Column minimums stay constant (`.fixedMinimum`) and never depend on the theme.
  - The player bar's height comes from `density` alone (76 for `regular`, 64 for `compact`), and it sits outside the split view.
  - Font scale changes only content inside rows.
- **Not themed:** the Settings and Setup windows, context menus, the search field's own chrome, the title bar and the menu-bar label image.

## 6. Settings: Themes tab

- A grid of swatches, each 120×80. A swatch is a `Card` showing background, surface, an accent pill and a line of text in the theme's font, with the name below it and a checkmark on the current theme. Clicking one selects it, live.
- Buttons: **Import Skin or Theme…** (an `NSOpenPanel` for `wsz` and `greedifytheme`) and **Show Themes Folder**. Dropping files onto the grid imports them.
- A **Browse the Winamp Skin Museum** link opens `https://skins.webamp.org`.
- The context menu for user themes has **Show in Finder**, **Duplicate** and **Delete**. Built-in themes have **Duplicate** only.
- A broken theme shows as a grey swatch with the reason in its help tag.
- Import errors show in `BannerOverlay`.

## 7. Error handling

| Case | Behaviour |
|---|---|
| The selected theme file is missing or broken at launch | Use System; keep `themeID` so it comes back if the file returns |
| A bad value in a theme | Clamp or fall back for that value only |
| Import of a `.wal` or a modern skin | "This looks like a Winamp 3/5 skin; only classic (.wsz) skins are supported." |
| A skin without color files | "No color files found in this skin." |
| A corrupt, oversized or non-local file | "Couldn't read this file." |
| A theme file in the folder that fails to load | Grey swatch; help tag "Couldn't read this theme: *<reason>*" |
| A font named by the theme isn't installed | Use the system font |

## 8. Testing

This follows TDD with Swift Testing in `GreedifyKitTests`.

- `ThemeDecodingTests`:
  - a complete file;
  - a partial file (fallbacks);
  - clamping;
  - bad colors;
  - unknown keys;
  - a newer version;
  - a file that isn't JSON.
- `ZipReaderTests`:
  - stored and deflated entries;
  - a subfolder and mixed-case names;
  - the size limits;
  - a corrupt central directory.
- `WinampSkinTests`:
  - `pledit.txt` quirks;
  - `viscolor.txt` comments;
  - BMP sampling;
  - `genex.bmp` positions.
- `SkinThemeMapperTests`:
  - the contrast guard, checked with real ratios;
  - accent choice;
  - light and dark base;
  - the font fallback;
  - `.wal` detection.
- `ThemeStoreTests`:
  - built-ins plus user files;
  - a broken file listed but skipped;
  - selection persisted;
  - the System fallback;
  - import writing a file;
  - name clashes;
  - duplicate and delete.
- **Fixtures** are small hand-made `.wsz` files built by a test helper, not real skins.
- **The app** is checked by building and running:
  - every built-in theme with the window, lyrics and popover open;
  - two real skins from the museum;
  - resize and zoom stress while switching (debug hooks);
  - `scripts/measure-memory.sh` before and after.

## 9. Out of scope

- Winamp 3/5 `.wal` skins.
- The bitmap fonts in `text.bmp`.
- Textures and background images.
- Theming the Settings and Setup windows or context menus.
- An in-app skin browser or downloads.
- Light and dark variants inside one theme.
- A folder watcher.
- A theme editor UI (duplicate the file and edit the JSON instead).
