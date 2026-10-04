# Adding a curated skin

Greedify ships skins as built-in themes that we tune by hand, rather than letting the user import them. A theme is a `.greedifytheme` recipe: the skin's look written as native drawing primitives (materials, bevels, LCD, buttons, sliders, rows, text), plus optional pictures and credits. Spec: `docs/superpowers/specs/2026-09-30-curated-skins-design.md`.

## 1. Draft it

```bash
swift run --package-path Packages/GreedifyKit skin-recipe ~/Downloads/some.wsz --name "Some Skin" --out ~/Library/Application\ Support/Greedify/Recipes/
```

This writes `some-skin.greedifytheme` (the draft recipe) and `some-skin.contact.png`. The contact sheet shows `main.bmp` with the sampled areas boxed, plus the sprite sheets, for reference while tuning. The tool prints what each value was measured from.

## 2. Tune it

Build and run the Debug app. Recipes in `~/Library/Application Support/Greedify/Recipes/` appear in Settings → Themes as `dev.<file>` and reload whenever the file is saved. Edit the JSON while looking at the contact sheet and the original skin. The main things to tune:

- `style.materials`: `solid`, `gradient`, `dotGrid`, `brushed`, `noise`, `pattern`, `radial` (a glow), `image` (a picture next to the recipe) and `layers` (a stack of these).
- `style.lcd`: the display's material, digits (`segment`, `pixel` or `mono`), text and glow.
- `style.button`, `style.slider` and `style.volume`: shapes, faces, bevels and fills.
- `style.rows`: the list colours. `rows.normal.text` is the app's text colour.
- **The whole-window Winamp look:** each of these is optional (spec: `docs/superpowers/specs/2026-10-03-winamp-window-design.md`).
  - `style.list` (`layout: playlist`): Winamp's playlist editor.
  - `style.pageHeader` (`layout: strip`): a slim page header.
  - `style.frame`: the panel frame with a striped title strip.
  - `style.bar.analyser` / `readouts` / `transport: winamp`: the analyser, the kbps line and the button row.
  - `style.text.lyrics`: the lyric lines' font.
- `credits`: who made the skin and where any pictures came from. They're listed under Settings → Credits.

Pictures go next to the recipe (and, when shipping, into `Theme/Builtin/`). They're decoded at up to 2048 px, so keep them modest; each one costs memory while it's shown.

## 3. Ship it

Copy the recipe and its pictures into `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Builtin/`, add the slug to `Theme.builtinOrder`, update `BuiltinThemeTests`, then run `swift test`. `ThemeStoreTests.curatedRecipesShipWithoutDroppedKeys` decodes every curated recipe strictly, so a typo fails the build. Commit.
