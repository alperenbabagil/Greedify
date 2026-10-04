# Verification results

| # | Check | Result | Notes |
|---|---|---|---|
| C1 | Daily Mix plays via context_uri | PENDING | needs the user's Spotify developer app + phone (Task 1 step 4) |
| C2 | Dashboard accepts greedify://callback | PENDING | needs the user to create the developer app (Task 1 step 2) |
| C3 | Bundled librespot runs; flags present | PASS | otool: only /System and /usr/lib; copied binary runs (0.8.0); all 10 flags present; `--device-type computer --bitrate 320 --autoplay on --cache-size-limit 2048M` accepted; audio via Rodio/CoreAudio |
| C4 | Credentials survive restart under launchd | PENDING | needs an interactive Spotify login (Task 1 step 6) |

## Themes

Run 2026-09-30 on branch `feature/themes`.

- **Tests:** `swift test` in `Packages/GreedifyKit`: 192 tests in 29 suites, all pass (after the final-review fixes).
- **Real skins** (Winamp Skin Museum, `.wsz` from r2.webampskins.org; imported through `ThemeStore.theme(fromFile:fileName:fontAvailable:)` in a throwaway test, since the Import button can't be clicked without UI automation; black_and_green and pinkies were written to `~/Library/Application Support/Greedify/Themes/`, skins not committed). Contrast is WCAG. Re-run after the mapper fixes (text guarded on background, surface and raised; saturated accent; base from text polarity):

| Skin | Base | Background | Text | Surface | Accent | Text on bg / surface / raised | Secondary on bg / surface | Accent on bg | Accent saturation |
|---|---|---|---|---|---|---|---|---|---|
| black_and_green | dark | #000000 | #00FF00 | #141414 | #0080FF | 15.30 / 13.38 / 12.03 | 6.44 / 5.63 | 5.53 | 1.00 |
| pinkies | light | #FFFFFF | #6C5F6C | #EBEBEB | #DA63D0 | 6.03 / 5.04 / 4.67 | 3.82 / 3.20 | 3.15 | 0.62 |
| os8amp255 | dark | #000000 | #6090FF | #141414 | #2F60FF | 6.93 / 6.06 / 5.64 | 3.75 / 3.27 | 4.24 | 1.00 |
| cream_amp | dark | #330033 | #FFCC00 | #431443 | #999933 | 11.69 / 9.74 / 8.67 | 5.36 / 4.47 | 5.86 | 0.50 |
| E_mp3_V21 | light | #AAAEB0 | #000000 | #F9FAFA | #0055B3 (default accent) | 9.39 / 20.05 / 17.55 | 4.88 / 10.42 | 3.17 | 1.00 |
| Minty_Lime | light | #50AF5F | #1D3020 | #98F19E | #28512B | 5.12 / 10.34 / 9.32 | 3.00 / 6.06 | 3.34 | 0.34 |

  All six meet text ≥ 4.5 on background, surface and raised, secondary ≥ 3 on background and surface, accent ≥ 3 on background with saturation ≥ 0.25, and text ≥ 4.5 on selection. E_mp3_V21 and Minty_Lime are now `light` (their text is dark). E_mp3_V21 has no qualifying palette color, so it gets the light base's default accent pushed to 3:1.
- **Live theme switching under resize and zoom** (spec §1): Release build installed with `scripts/install.sh`, `debugHooks` on, main window open with lyrics on. Without relaunching, `com.alperen.greedify.debug.theme` alternated `builtin.classic`, `builtin.modern`, `builtin.system`, `pinkies.greedifytheme` and `black_and_green.greedifytheme`, four rounds; each theme ran the resize loop (900x560, 1400x800, 1000x600, 1200x700) with a theme flip after every resize, two zooms with a switch between them, and a route change. Then a 30-iteration burst with no waits (theme, resize, theme, resize, theme, zoom, theme), then close and reopen the main window. `pgrep -x Greedify` returned the same pid (19806) after every round and after the burst; no new crash report in `~/Library/Logs/DiagnosticReports`, and no fault or "Update Constraints" message in the unified log. The persisted `themeID` followed the hook. The Settings click-to-switch path itself was not exercised (no UI automation).
- **Memory** (Debug build, `scripts/measure-memory.sh`, Greedify only; total includes librespot, about 8 MB):

| Theme | Fresh | Window open | After closing |
|---|---|---|---|
| builtin.system | 23.8 MB | 57.9 MB | 54.9 MB |
| pinkies.greedifytheme | 24.8 MB | 57.0 MB | 54.3 MB |
| black_and_green.greedifytheme | 24.0 MB | 57.0 MB | 54.3 MB |

  All inside the CLAUDE.md profile (fresh ~23, open 56-74, closed 52-59); no growth attributable to themes.

### Theme images

Run 2026-09-30 on branch `feature/themes`, after the final-review fix wave (text lift, per-area alphas, off-main-actor decoding, pixel cap, sidebar art).

- **Tests:** `swift test` in `Packages/GreedifyKit`: 228 tests in 33 suites, all pass.
- **Real skins** (`SkinThemeMapper.theme(fromArchive:fileName:installedFonts:)` with `NSFontManager.shared.availableFontFamilies`, then `BackdropPlan.make(image:colors:base:)`, in a throwaway test that was deleted; skins not committed). Each result was written to `~/Library/Application Support/Greedify/Themes/<name> 2.greedifytheme`. All three backdrops are 275x116 and plan in about 6 ms.

| Skin | Family | Worst pixel | Lift | Sidebar α | Content α | Lyrics α | Art behind lyrics | text | textSecondary | lyricsText | Pixel font |
|---|---|---|---|---|---|---|---|---|---|---|---|
| diablo_ii | Copperplate | #FB8D2E | 0.3 | 0.68 | 0.60 | 0.60 | 40% | #978F60 → #B7B18E | #6A6548 → #A19B75 | #978F60 → #B7B18E | yes |
| base-2.91 | Arial | #62626D | 0 | 0.76 | 0.35 | 0.35 | 65% | #00FF00 (unchanged) | #00A600 (unchanged) | #00FF00 (unchanged) | yes |
| Winamp5_Classified_v5.5 | Arial | #F4F4F6 | 0.35 | 0.52 | 0.69 | 0.69 | 31% | #FFFFFF (unchanged) | #B0BBD2 → #CBD3E1 | #FFFFFF (unchanged) | no (patterned paper) |

  Before the fix, diablo_ii planned lists 1.0 and lyrics 0.9 (the art was hidden). Winamp5 can't reach the 40% lyrics target: its text is already white over near-white art, so the plan keeps the smallest lift (0.35) that gets the best alphas.
- **Live theme switching** (Release build installed in `/Applications`, `com.alperen.greedify.debug.*` hooks, no relaunch): three rounds of `diablo_ii 2`, `base-2.91 2`, Classic and System. Each round switches with the lyrics shown, resizes to 900x560, 1400x800 and 1000x600, switches away and back, then hides the lyrics and zooms twice (switching themes between the zooms), and changes route. Same pid throughout, no crash report.
- **Known issue, not from this branch:** zooming while the lyrics inspector is shown aborts with "too many Update Constraints passes" (`SplitViewChildController … didUpdateMinSize`). It reproduces on `main` (a8b98c0) and on this branch's pre-fix commit (6db0490), in every theme including System, 3/3 from 1400x800 with nothing playing. For that reason the stress above zooms with the lyrics hidden.
- **Memory** (Release build, relaunched fresh for each theme, `scripts/measure-memory.sh`; main window opened with the lyrics shown, then closed with the debug hooks):

| Theme | Fresh launch (closed) | Window open | After closing | Total with librespot (after closing) |
|---|---|---|---|---|
| builtin.system | 24.3 MB | 57.0 MB | 54.0 MB | 62.5 MB |
| diablo_ii 2 | 25.0 MB | 58.7 MB | 55.7 MB | 64.1 MB |

  Both are inside the CLAUDE.md profile (window open 56-74 MB, after closing 52-59 MB), and under the 70 MB target.

### Needs a human (theme images)

No UI automation was possible, so these were not looked at. For each of diablo_ii, base-2.91 and Winamp5_Classified_v5.5:

- The skin artwork behind the window and the lyrics, and that text stays readable through the translucent panels.
- The skinned player bar.
- The sidebar showing the art lined up with the window's across the sidebar/detail seam, including during a live resize, and the lifted text colors (diablo_ii's olive is noticeably lighter).
- The now-playing title drawn in the skin's pixel font (Winamp5_Classified has none, so it should fall back to the normal font).
- The matched fonts (Copperplate for diablo_ii, Arial for the other two).

### Needs a human

- Pixel-level look of each built-in theme (System, Classic, Modern, Paper, High Contrast), and System compared with before the feature.
- The Settings Themes tab: click a swatch to switch, Duplicate, Show in Finder, Delete, the help tag on a broken swatch, and dropping a `.wal` file.
- Readability of imported skins in the sidebar, rows, player bar and lyrics.

## Skinned player controls (2026-09-30)

- Package tests: 276 pass (`swift test`), 22 new across the palette, sprites, control images, the scaler, the theme codec, pixel-font shading and digit masks.
- Crash check: Winamp5_Classified, builtin.classic and diablo_ii switched live, each with a resize to 860×600 and zoom in/out: no crash.
- Memory: fresh launch, window open, diablo_ii selected: Greedify 69.1 MB (within the 56–74 MB window-open range).
- User's review, after re-importing the skins: readable after two fixes (diablo's title shading, Classified's dotted LED digits). The overall look is "better but far from ok": the bar should match the skin far more closely, and list backgrounds should use the skin's background instead of the repeated art. Both are follow-ups (D, E).

## Podcasts (2026-09-30)

- Package tests: 310 pass (`swift test`), 34 new (episode decoding, endpoints, scope, librespot episodes, player resume/skip/next-episode, library caches and paging, search).
- API, after the day's library quota reset (20:43): `me/shows`, `shows/{id}/episodes`, `me/episodes`, `search` and `me/library/contains` all 200.
- User check: login notice, resuming a part-played episode, back 15 / forward 30, the next newer episode, show links and podcast search — all working.
- Memory: fresh launch, window on Your Shows 74.0 MB, Liked Songs 70.4 MB (range 56–74 MB); 81.9 MB after browsing all podcast pages (allocator high-water mark).
