# Theme Images and Skin Fonts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Imported Winamp skins show their artwork behind the main window, with a skinned player bar, and carry their fonts: a near-matched system font throughout, and the skin's pixel font for the now-playing title.

**Architecture:**
- The package gains an optional `Theme.images` group, stored as base64 PNG in the theme JSON.
- The importer saves `main.bmp` and `text.bmp` as PNGs. A pure `FontMatcher` picks the installed family.
- A pure `PixelFont` turns `text.bmp` into 5×6 ink masks, and a pure `BackdropPlan` computes how much panel tint keeps text readable over the art.
- The app decodes all of it once per theme switch into `ResolvedTheme`. It draws the backdrop behind the window, tints the panels by the plan, tiles the art in the player bar and draws the title with `Canvas`.

**Tech Stack:** Swift 6, SwiftUI and AppKit (macOS 15), Swift Testing, ImageIO (`CGImageSource`, `CGImageDestination`).

**Spec:** `docs/superpowers/specs/2026-09-30-theme-images-design.md`. It builds on `docs/superpowers/specs/2026-09-30-themes-design.md`.

**Branch:** `feature/themes` in the worktree `../Greedify-themes`. All paths below are relative to it.

## Global Constraints

- Platform macOS 15; package code is Swift 6 language mode; no new third-party dependencies.
- **Theme format:** an optional `images` object with keys `backdrop` and `pixelFont`, each a base64 PNG. The format stays `version` 1.
- **Image acceptance:** bytes must start with the PNG signature `89 50 4E 47 0D 0A 1A 0A` and be ≤ 512 KB (524,288 bytes) after base64 decoding. Otherwise only that image is dropped.
- **Encoding:** themes without images encode with no `images` key.
- **Pixel font:** `text.bmp` must be at least 155×18. Cells are 5×6, with 31 columns and up to 3 rows. The glyph map is exactly the one in spec §4. Unknown characters draw as a space at (0,30). The title is drawn at scale 2 (10×12 pt per glyph), tinted with the theme's `text`, and is never smoothed.
- **BackdropPlan:** alphas are 0.35…0.95 in steps of 0.05, or 1 when even 0.95 fails. Text must reach 4.5:1 and `textSecondary` 3:1 against the blended worst case. The worst case is the 95th-percentile luminance pixel for dark bases and the 5th percentile for light bases.
- `lyricsAlpha = min(listsAlpha, smallest passing α over background)`.
- **FontMatcher order:**
  1. an exact match, ignoring case;
  2. the longest whole-word prefix;
  3. the table: "MS Sans Serif" → "Geneva", "Small Fonts" → "Monaco", "Terminal" → "Monaco", "System" → nil;
  4. nil.
- **Importer API** (replaces `fontAvailable:`):
  - `SkinThemeMapper.theme(fromArchive:fileName:installedFonts:)`
  - `SkinThemeMapper.theme(from:fileName:installedFonts:)`
  - `ThemeStore.theme(fromFile:fileName:installedFonts:)`
  - `ThemeStore.importFile(data:fileName:installedFonts:)`
- **System theme:** System, built-ins and themes without images must render exactly as today. Every new visual is gated on `theme.backdrop != nil` or `theme.pixelFont != nil`.
- **Layout safety (CLAUDE.md):**
  - backdrops only in `.background { }`, where they never size the parent;
  - the constant `.fixedMinimum` columns stay untouched;
  - the player-bar height stays `theme.playerBarHeight`;
  - never use `ImageRenderer`.
- **Out of scope:** a marquee; the pixel font outside the player-bar title; a popover backdrop; `pledit.bmp` frame tiles or other sprites; images for built-ins; auto-upgrading already-imported themes.
- **Commits** end with:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ
```

## Review Focus

1. **A pixel font whose "space" cell isn't plain paper** (a patterned or coloured `text.bmp` background) would turn every glyph into a solid block. The expected behaviour is to treat the font as unusable and fall back to the theme font. Test: Task 4, `patternedPaperIsRejected`.
2. **Titles with characters the font lacks** (CJK, emoji) or an empty title must draw spaces or nothing, never crash. Test: Task 4, `unknownAndEmptyTitles`.
3. **A tiny or single-colour backdrop** (1×1, all black) must still produce a valid plan. Test: Task 5, `tinyBackdropStillPlans`.
4. **A light-base skin with dark art** must tint against the darkest pixels, not the brightest. Test: Task 5, `lightBaseUsesDarkestPixels`.
5. **A theme file with an oversized image** (over 512 KB) must still load, minus that image. Test: Task 1, `oversizedImageIsDropped`.

---

## File map

| File | Responsibility |
|---|---|
| `Packages/GreedifyKit/Sources/GreedifyKit/Theme/ThemeImage.swift` (new) | PNG signature check, decode image data to `CGImage`, encode `CGImage` to PNG, pixel-font minimum size |
| `…/Theme/Theme.swift` | `Theme.Images`, `images` key in Codable |
| `…/Theme/Winamp/SkinBitmap.swift` | `init?(image:)`, `pixels()` |
| `…/Theme/Winamp/WinampSkin.swift` | `backdropPNG`, `pixelFontPNG` |
| `…/Theme/Winamp/SkinThemeMapper.swift` | copy images; `installedFonts` + `FontMatcher` |
| `…/Theme/FontMatcher.swift` (new) | family near-matching |
| `…/Theme/PixelFont.swift` (new) | glyph map, ink masks |
| `…/Theme/BackdropPlan.swift` (new) | per-area tint alphas |
| `…/Theme/ThemeStore.swift` | `installedFonts` pass-through |
| Tests: `ThemeImagesTests`, `FontMatcherTests`, `PixelFontTests`, `BackdropPlanTests` (new); `WinampSkinTests`, `SkinThemeMapperTests`, `ThemeStoreTests` (modified); `Support/PNGFixture.swift` (new) | |
| `App/Views/Shared/ResolvedTheme.swift` | `backdrop`, `pixelFont`, `plan`, alphas, `loadImages:` |
| `App/Views/Shared/ThemeComponents.swift` | translucent fills, `SurfaceKind.bar`, `themedTile()`, `ThemeBackdrop`, `BackdropStrip`, `PixelText` |
| `App/Views/Main/MainWindow.swift`, `PlayerBar.swift`, `App/Views/Settings/ThemeSettings.swift`, `App/Model/AppModel.swift` | wiring |

---

### Task 1: Theme.images and PNG helpers

**Files:**
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/ThemeImage.swift`
- Create: `Packages/GreedifyKit/Tests/GreedifyKitTests/Support/PNGFixture.swift`
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Theme.swift` (the struct, the `Keys` enum, `init(from:)` and `encode(to:)`)
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/ThemeImagesTests.swift`

**Interfaces:**
- Consumes: `BMPBuilder.make(width:height:pixel:)` (existing test support).
- Produces:
  - `public enum ThemeImage` with `pngSignature: [UInt8]`, `isPNG(_ data: Data) -> Bool`, `cgImage(_ data: Data) -> CGImage?`, `png(_ image: CGImage) -> Data?`, `png(fromImageData:) -> Data?`, `pixelFontMinWidth = 155` and `pixelFontMinHeight = 18`;
  - `public struct Theme.Images: Equatable, Sendable` with `backdrop: Data?`, `pixelFont: Data?`, `init(backdrop:pixelFont:)`, `isEmpty`, `static maxBytes = 524_288` and `static func accept(_ data: Data?) -> Data?` (internal);
  - `Theme.images: Theme.Images`, defaulting to empty;
  - test support `PNGFixture.make(width:height:pixel:) -> Data`.

- [ ] **Step 1: Write the test support**

`Tests/GreedifyKitTests/Support/PNGFixture.swift`:

```swift
import Foundation
@testable import GreedifyKit

/// PNG test images, built from BMPBuilder and re-encoded through the package's own ImageIO path.
enum PNGFixture {
    static func make(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        ThemeImage.png(fromImageData: BMPBuilder.make(width: width, height: height, pixel: pixel))!
    }
}
```

- [ ] **Step 2: Write the failing test**

`Tests/GreedifyKitTests/ThemeImagesTests.swift`:

```swift
import Foundation
import Testing
@testable import GreedifyKit

struct ThemeImagesTests {
    let red = PNGFixture.make(width: 4, height: 3) { _, _ in (255, 0, 0) }
    let blue = PNGFixture.make(width: 2, height: 2) { _, _ in (0, 0, 255) }

    func decode(_ json: String) throws -> Theme { try Theme.decode(from: Data(json.utf8)) }

    @Test func pngHelpersRoundTrip() throws {
        #expect(ThemeImage.isPNG(red))
        let image = try #require(ThemeImage.cgImage(red))
        #expect(image.width == 4 && image.height == 3)
        #expect(!ThemeImage.isPNG(Data("hello".utf8)))
    }

    @Test func imagesRoundTrip() throws {
        var t = Theme.defaults(for: .dark)
        t.images = Theme.Images(backdrop: red, pixelFont: blue)
        let back = try Theme.decode(from: t.encoded())
        #expect(back.images == t.images)
        #expect(back == t)
    }

    @Test func badBase64DropsOnlyThatImage() throws {
        let t = try decode(#"{"images":{"backdrop":"!!!not base64!!!","pixelFont":"\#(blue.base64EncodedString())"}}"#)
        #expect(t.images.backdrop == nil)
        #expect(t.images.pixelFont == blue)
    }

    @Test func nonPNGIsDropped() throws {
        let t = try decode(#"{"images":{"backdrop":"\#(Data("hello".utf8).base64EncodedString())"}}"#)
        #expect(t.images.isEmpty)
    }

    @Test func oversizedImageIsDropped() throws {
        var big = Data(ThemeImage.pngSignature)
        big.append(Data(count: Theme.Images.maxBytes)) // one signature over the limit
        let t = try decode(#"{"name":"Big","images":{"backdrop":"\#(big.base64EncodedString())","pixelFont":"\#(blue.base64EncodedString())"}}"#)
        #expect(t.name == "Big")
        #expect(t.images.backdrop == nil)
        #expect(t.images.pixelFont == blue)
    }

    @Test func themesWithoutImagesAreUnchanged() throws {
        #expect(try decode("{}").images.isEmpty)
        let json = try #require(String(data: Theme.defaults(for: .light).encoded(), encoding: .utf8))
        #expect(!json.contains("\"images\""))
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd Packages/GreedifyKit && swift test --filter ThemeImagesTests`
Expected: a build failure, "cannot find 'ThemeImage' in scope".

- [ ] **Step 4: Write `ThemeImage.swift`**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG plumbing for theme images (theme images spec §2–§3), all through ImageIO.
public enum ThemeImage {
    public static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    /// A skin's `text.bmp` must hold the full 5×6 glyph grid (31 columns × 3 rows).
    public static let pixelFontMinWidth = 155
    public static let pixelFontMinHeight = 18

    public static func isPNG(_ data: Data) -> Bool { data.starts(with: pngSignature) }

    /// Decodes any ImageIO-readable image (PNG, BMP…).
    public static func cgImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func png(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    /// Re-encodes an image (a skin's BMP) as PNG at its native size.
    public static func png(fromImageData data: Data) -> Data? { cgImage(data).flatMap(png) }
}
```

- [ ] **Step 5: Add `Theme.Images` and the `images` key to `Theme.swift`**

Inside `public struct Theme`, after `public struct Shapes { … }`:

```swift
    /// Optional skin images, stored in the file as base64 PNG (theme images spec §2).
    public struct Images: Equatable, Sendable {
        public static let maxBytes = 524_288
        public var backdrop: Data?
        public var pixelFont: Data?
        public init(backdrop: Data? = nil, pixelFont: Data? = nil) { self.backdrop = backdrop; self.pixelFont = pixelFont }
        public var isEmpty: Bool { backdrop == nil && pixelFont == nil }

        /// PNG bytes within the size limit, else nil.
        static func accept(_ data: Data?) -> Data? {
            guard let data, data.count <= maxBytes, ThemeImage.isPNG(data) else { return nil }
            return data
        }
    }
```

After `public var lyrics: LyricsStyle`, add:

```swift
    public var images = Images()
```

In `extension Theme: Codable`, change `Keys` and add `ImageKeys`:

```swift
    private enum Keys: String, CodingKey { case version, name, author, source, base, colors, fonts, shapes, lyrics, images }
    private enum ImageKeys: String, CodingKey { case backdrop, pixelFont }
```

In `init(from:)`, just before `self = t`:

```swift
        if let ic = try? c.nestedContainer(keyedBy: ImageKeys.self, forKey: .images) {
            func image(_ key: ImageKeys) -> Data? {
                (try? ic.decode(String.self, forKey: key))
                    .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
                    .flatMap(Images.accept)
            }
            t.images = Images(backdrop: image(.backdrop), pixelFont: image(.pixelFont))
        }
```

At the end of `encode(to:)`:

```swift
        if !images.isEmpty {
            var ic = c.nestedContainer(keyedBy: ImageKeys.self, forKey: .images)
            try ic.encodeIfPresent(images.backdrop?.base64EncodedString(), forKey: .backdrop)
            try ic.encodeIfPresent(images.pixelFont?.base64EncodedString(), forKey: .pixelFont)
        }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd Packages/GreedifyKit && swift test --filter ThemeImagesTests`
Expected: PASS (6 tests). Then run the whole suite with `swift test`; every test must pass.

- [ ] **Step 7: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/ThemeImage.swift Packages/GreedifyKit/Sources/GreedifyKit/Theme/Theme.swift Packages/GreedifyKit/Tests/GreedifyKitTests/Support/PNGFixture.swift Packages/GreedifyKit/Tests/GreedifyKitTests/ThemeImagesTests.swift
git commit -m "feat(theme): optional base64 PNG images in theme files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 2: Import main.bmp and text.bmp as images

**Files:**
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinBitmap.swift` (split the init; add `pixels()`)
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/WinampSkin.swift` (properties and `init(archive:)`)
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinThemeMapper.swift` (`theme(from:…)`)
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/WinampSkinTests.swift`, `SkinThemeMapperTests.swift`

**Interfaces:**
- Consumes: `ThemeImage` and `Theme.Images.accept` (Task 1).
- Produces:
  - `SkinBitmap.init?(image: CGImage)` and `SkinBitmap.pixels() -> [ThemeColor]`, both internal (used by Tasks 4 and 5);
  - `WinampSkin.backdropPNG: Data?`, `WinampSkin.pixelFontPNG: Data?` and `static func pixelFontPNG(from: Data) -> Data?`;
  - the mapper sets `theme.images`.

- [ ] **Step 1: Write the failing tests**

Append to `WinampSkinTests`:

```swift
    @Test func mainAndTextBitmapsBecomePNGsAtNativeSize() throws {
        let main = BMPBuilder.make(width: 275, height: 116) { x, _ in (UInt8(x % 256), 40, 60) }
        let text = BMPBuilder.make(width: 155, height: 18) { _, _ in (0, 0, 0) }
        let skin = try WinampSkin(archive: SkinFixture.wsz(["main.bmp": main, "text.bmp": text]))
        let backdrop = try #require(skin.backdropPNG.flatMap(ThemeImage.cgImage))
        #expect(ThemeImage.isPNG(skin.backdropPNG!))
        #expect(backdrop.width == 275 && backdrop.height == 116)
        let font = try #require(skin.pixelFontPNG.flatMap(ThemeImage.cgImage))
        #expect(font.width == 155 && font.height == 18)
    }

    @Test func smallTextBitmapIsIgnored() throws {
        let text = BMPBuilder.make(width: 100, height: 10) { _, _ in (0, 0, 0) }
        let skin = try WinampSkin(archive: SkinFixture.wsz(["pledit.txt": Data(SkinFixture.classicPledit.utf8), "text.bmp": text]))
        #expect(skin.pixelFontPNG == nil)
    }

    @Test func skinsWithoutImagesStillImport() throws {
        let skin = try WinampSkin(archive: SkinFixture.wsz(["pledit.txt": Data(SkinFixture.classicPledit.utf8)]))
        #expect(skin.backdropPNG == nil && skin.pixelFontPNG == nil)
    }
```

Append to `SkinThemeMapperTests`:

```swift
    @Test func imagesAreCopiedIntoTheTheme() {
        var skin = green
        skin.backdropPNG = PNGFixture.make(width: 4, height: 4) { _, _ in (200, 0, 0) }
        skin.pixelFontPNG = PNGFixture.make(width: 155, height: 18) { _, _ in (0, 0, 0) }
        let t = SkinThemeMapper.theme(from: skin, fileName: "g.wsz", fontAvailable: always)
        #expect(t.images.backdrop == skin.backdropPNG)
        #expect(t.images.pixelFont == skin.pixelFontPNG)
    }
```

(Task 3 renames `fontAvailable: always`; keep today's spelling here.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/GreedifyKit && swift test --filter "WinampSkinTests|SkinThemeMapperTests"`
Expected: a build failure, "value of type 'WinampSkin' has no member 'backdropPNG'".

- [ ] **Step 3: Split `SkinBitmap`'s init and add `pixels()`**

Replace `init?(data: Data)` with two inits. The body of `init?(image:)` is today's init from `let (w, h) = …` onward, unchanged:

```swift
    init?(data: Data) {
        guard let image = ThemeImage.cgImage(data) else { return nil }
        self.init(image: image)
    }

    init?(image: CGImage) {
        guard image.width > 0, image.height > 0, image.width * image.height <= 4_000_000 else { return nil }
        let (w, h) = (image.width, image.height)
        // …the existing color-space, buffer and draw code, unchanged…
    }
```

Add the method:

```swift
    /// Every pixel, row by row from the top.
    func pixels() -> [ThemeColor] {
        stride(from: 0, to: rgba.count, by: 4).map { ThemeColor(r8: Int(rgba[$0]), g8: Int(rgba[$0 + 1]), b8: Int(rgba[$0 + 2])) }
    }
```

- [ ] **Step 4: Add the images to `WinampSkin`**

In the struct, after `public var genex: GenexColors?`:

```swift
    /// `main.bmp` re-encoded as PNG: the theme's backdrop (theme images spec §3).
    public var backdropPNG: Data?
    /// `text.bmp` re-encoded as PNG when it holds the full glyph grid: the pixel font.
    public var pixelFontPNG: Data?
```

In `init(archive:)`, replace the `frameColor = …` line with:

```swift
        let main = read("main.bmp")
        frameColor = main.flatMap(SkinBitmap.init(data:)).flatMap(Self.frameColor(of:))
        backdropPNG = main.flatMap(ThemeImage.png(fromImageData:))
        pixelFontPNG = read("text.bmp").flatMap(Self.pixelFontPNG(from:))
```

Leave the `noColorSources` guard unchanged; colors are still required. Add to the extension:

```swift
    static func pixelFontPNG(from data: Data) -> Data? {
        guard let image = ThemeImage.cgImage(data),
              image.width >= ThemeImage.pixelFontMinWidth, image.height >= ThemeImage.pixelFontMinHeight else { return nil }
        return ThemeImage.png(image)
    }
```

- [ ] **Step 5: Copy the images in the mapper**

In `SkinThemeMapper.theme(from:fileName:fontAvailable:)`, after `theme.lyrics = .solid`:

```swift
        theme.images = Theme.Images(backdrop: Theme.Images.accept(skin.backdropPNG),
                                    pixelFont: Theme.Images.accept(skin.pixelFontPNG))
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd Packages/GreedifyKit && swift test --filter "WinampSkinTests|SkinThemeMapperTests"`
Expected: PASS. Then run the full `swift test`; all must pass.

- [ ] **Step 7: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp Packages/GreedifyKit/Tests/GreedifyKitTests/WinampSkinTests.swift Packages/GreedifyKit/Tests/GreedifyKitTests/SkinThemeMapperTests.swift
git commit -m "feat(theme): import main.bmp and text.bmp as theme images

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 3: FontMatcher and the `installedFonts` importer API

**Files:**
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/FontMatcher.swift`
- Modify: `…/Theme/Winamp/SkinThemeMapper.swift` (both `theme(…)` signatures and the `fonts` line)
- Modify: `…/Theme/ThemeStore.swift` (`importFile`, `theme(fromFile:)`)
- Modify: `App/Model/AppModel.swift` (`importTheme`, the `families` line and the `theme(fromFile:)` call)
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/FontMatcherTests.swift` (new), `SkinThemeMapperTests.swift`, `ThemeStoreTests.swift`

**Interfaces:**
- Consumes: the existing mapper and store.
- Produces:
  - `public enum FontMatcher { static func bestFamily(for: String, among: [String]) -> String? }`;
  - the importer signatures listed in Global Constraints (with `installedFonts: [String]`).

- [ ] **Step 1: Write the failing test**

`Tests/GreedifyKitTests/FontMatcherTests.swift`:

```swift
import Testing
@testable import GreedifyKit

struct FontMatcherTests {
    let installed = ["Arial", "Arial Narrow", "Copperplate", "Geneva", "Monaco", "Verdana"]

    @Test func exactMatchIgnoresCase() {
        #expect(FontMatcher.bestFamily(for: "verdana", among: installed) == "Verdana")
        #expect(FontMatcher.bestFamily(for: "Arial Narrow", among: installed) == "Arial Narrow")
    }

    @Test func wholeWordPrefix() {
        #expect(FontMatcher.bestFamily(for: "Copperplate Gothic Light", among: installed) == "Copperplate")
        #expect(FontMatcher.bestFamily(for: "Arial Black", among: installed) == "Arial")
        #expect(FontMatcher.bestFamily(for: "Arialish", among: installed) == nil) // not a whole word
    }

    @Test func windowsTable() {
        #expect(FontMatcher.bestFamily(for: "MS Sans Serif", among: installed) == "Geneva")
        #expect(FontMatcher.bestFamily(for: "Small Fonts", among: installed) == "Monaco")
        #expect(FontMatcher.bestFamily(for: "Terminal", among: installed) == "Monaco")
        #expect(FontMatcher.bestFamily(for: "System", among: installed) == nil)
    }

    @Test func noMatch() {
        #expect(FontMatcher.bestFamily(for: "Comic Sans MS", among: installed) == nil)
        #expect(FontMatcher.bestFamily(for: "  ", among: installed) == nil)
        #expect(FontMatcher.bestFamily(for: "Geneva", among: []) == nil)
    }
}
```

Also add to `SkinThemeMapperTests` (it fails until Step 5, because of the rename):

```swift
    @Test func fontNamesAreNearMatched() {
        var skin = green
        skin.playlist?.font = "Copperplate Gothic Light"
        #expect(SkinThemeMapper.theme(from: skin, fileName: "d.wsz", installedFonts: ["Copperplate"]).fonts.family == "Copperplate")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/GreedifyKit && swift test --filter "FontMatcherTests|SkinThemeMapperTests"`
Expected: a build failure, "cannot find 'FontMatcher' in scope".

- [ ] **Step 3: Write `FontMatcher.swift`**

```swift
import Foundation

/// Picks the installed font family for a skin's `pledit.txt` font name (theme images spec §3).
public enum FontMatcher {
    /// Windows fonts from the Winamp era with a Mac look-alike; nil means "use the system font".
    static let windowsEquivalents: [String: String?] = [
        "ms sans serif": "Geneva", "small fonts": "Monaco", "terminal": "Monaco", "system": nil,
    ]

    public static func bestFamily(for wanted: String, among installed: [String]) -> String? {
        let name = wanted.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let exact = installed.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return exact }

        let words = name.lowercased().split(separator: " ")
        let prefixes = installed.filter { family in
            let familyWords = family.lowercased().split(separator: " ")
            return !familyWords.isEmpty && familyWords.count < words.count && Array(words.prefix(familyWords.count)) == familyWords
        }
        if let longest = prefixes.max(by: { $0.split(separator: " ").count < $1.split(separator: " ").count }) { return longest }

        if let mapped = windowsEquivalents[name.lowercased()] {
            return mapped.flatMap { target in installed.first { $0.caseInsensitiveCompare(target) == .orderedSame } }
        }
        return nil
    }
}
```

- [ ] **Step 4: Switch the importer API to `installedFonts`**

In `SkinThemeMapper.swift`:

```swift
    /// `installedFonts` are the Mac's font family names; the skin's font is near-matched against them.
    public static func theme(fromArchive data: Data, fileName: String, installedFonts: [String]) throws -> Theme {
        if (fileName as NSString).pathExtension.lowercased() == "wal" { throw ThemeImportError.unsupportedModernSkin }
        return theme(from: try WinampSkin(archive: data), fileName: fileName, installedFonts: installedFonts)
    }

    public static func theme(from skin: WinampSkin, fileName: String, installedFonts: [String]) -> Theme {
```

In the same file, replace the `theme.fonts = …` line with:

```swift
        theme.fonts = Theme.Fonts(family: playlist?.font.flatMap { FontMatcher.bestFamily(for: $0, among: installedFonts) },
                                  scale: 1, titleWeight: .bold)
```

In `ThemeStore.swift`, change `importFile` and `theme(fromFile:)`:

```swift
    public func importFile(data: Data, fileName: String, installedFonts: [String]) throws -> ThemeEntry {
        try add(Self.theme(fromFile: data, fileName: fileName, installedFonts: installedFonts))
    }

    public nonisolated static func theme(fromFile data: Data, fileName: String, installedFonts: [String]) throws -> Theme {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "wsz", "wal", "zip":
            return try SkinThemeMapper.theme(fromArchive: data, fileName: fileName, installedFonts: installedFonts)
```

The rest of `theme(fromFile:)` is unchanged.

In `App/Model/AppModel.swift` `importTheme(from:)`:
- replace `let families = Set(NSFontManager.shared.availableFontFamilies.map { $0.lowercased() })` with `let families = NSFontManager.shared.availableFontFamilies`;
- replace `fontAvailable: { families.contains($0.lowercased()) })` with `installedFonts: families)`.

- [ ] **Step 5: Migrate the existing tests**

In `SkinThemeMapperTests.swift`:
- replace `private func always(_: String) -> Bool { true }` with `private let fonts = ["Arial"]`;
- replace every `fontAvailable: always` with `installedFonts: fonts`;
- replace `fontAvailable: { _ in false }` with `installedFonts: []`.

In `ThemeStoreTests.swift`, replace every `fontAvailable: { _ in true }` with `installedFonts: ["Arial"]`.

Check that nothing is left:

```bash
grep -rn "fontAvailable" Packages App
```

Expected: no output.

- [ ] **Step 6: Run the tests and the build**

Run: `cd Packages/GreedifyKit && swift test`
Expected: all pass, including `FontMatcherTests` (4 tests) and `fontNamesAreNearMatched`.

Run: `xcodegen generate && xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Packages/GreedifyKit App/Model/AppModel.swift
git commit -m "feat(theme): near-match skin fonts against the installed families

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 4: PixelFont

**Files:**
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/PixelFont.swift`
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/PixelFontTests.swift`

**Interfaces:**
- Consumes: `SkinBitmap(data:)`, `SkinBitmap.color(x:y:)` (Task 2) and `ThemeImage.pixelFontMinWidth/Height` (Task 1).
- Produces: `public final class PixelFont: Sendable` with:
  - `cellWidth = 5`, `cellHeight = 6`, `columns = 31`;
  - `static cell(for: Character) -> (row: Int, column: Int)`;
  - `static glyphs(for: String) -> [(row: Int, column: Int)]`;
  - `init?(png: Data)`;
  - `mask(row:column:) -> [Bool]`, which is 30 values, row-major, `true` = ink.

This refines spec §4's `glyphImage(row:column:) -> CGImage?` into ink masks. That is the same cropping-once idea, but a mask is what lets the app tint the glyphs with the theme's `text` color.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import GreedifyKit

struct PixelFontTests {
    func at(_ c: Character) -> [Int] { let cell = PixelFont.cell(for: c); return [cell.row, cell.column] }

    @Test func glyphMap() {
        #expect(at("A") == [0, 0])
        #expect(at("Z") == [0, 25])
        #expect(at("\"") == [0, 26])
        #expect(at("@") == [0, 27])
        #expect(at(" ") == [0, 30])
        #expect(at("0") == [1, 0])
        #expect(at("9") == [1, 9])
        #expect(at("…") == [1, 10])
        #expect(at(".") == [1, 11])
        #expect(at("#") == [1, 30])
        #expect(at("Å") == [2, 0])
        #expect(at("*") == [2, 4])
    }

    @Test func lowercaseAndDiacriticsFold() {
        #expect(at("a") == [0, 0])
        #expect(PixelFont.glyphs(for: "Oğlan qızı").map { $0.column } == PixelFont.glyphs(for: "OGLAN QIZI").map { $0.column })
        #expect(PixelFont.glyphs(for: "Oğlan qızı").map { $0.row } == PixelFont.glyphs(for: "OGLAN QIZI").map { $0.row })
        #expect(at("ö") == [2, 1]) // Ö has its own glyph
    }

    @Test func unknownAndEmptyTitles() {
        #expect(PixelFont.glyphs(for: "").isEmpty)
        #expect(at("日") == [0, 30])
        #expect(at("🎵") == [0, 30])
        #expect(at("ß") == [0, 30])
    }

    /// Black paper; cell (0,0) has ink at its top-left and bottom-right pixels only.
    func fontPNG(paper: (UInt8, UInt8, UInt8) = (0, 0, 0)) -> Data {
        PNGFixture.make(width: 155, height: 18) { x, y in
            (x == 0 && y == 0) || (x == 4 && y == 5) ? (0, 255, 0) : paper
        }
    }

    @Test func masksMarkInk() throws {
        let font = try #require(PixelFont(png: fontPNG()))
        let a = font.mask(row: 0, column: 0)
        #expect(a.count == 30)
        #expect(a[0] && a[29])
        #expect(a.filter { $0 }.count == 2)
        #expect(!font.mask(row: 1, column: 0).contains(true))
        #expect(!font.mask(row: 0, column: 30).contains(true)) // space
    }

    @Test func smallOrUndecodableImagesAreRejected() {
        #expect(PixelFont(png: PNGFixture.make(width: 100, height: 10) { _, _ in (0, 0, 0) }) == nil)
        #expect(PixelFont(png: Data("nope".utf8)) == nil)
    }

    @Test func patternedPaperIsRejected() {
        // Ink in the space cell means the font has no plain paper to measure against.
        let png = PNGFixture.make(width: 155, height: 18) { x, y in (x + y) % 2 == 0 ? (255, 255, 255) : (0, 0, 0) }
        #expect(PixelFont(png: png) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd Packages/GreedifyKit && swift test --filter PixelFontTests`
Expected: a build failure, "cannot find 'PixelFont' in scope".

- [ ] **Step 3: Write `PixelFont.swift`**

```swift
import Foundation

/// A Winamp `text.bmp` pixel font (theme images spec §4): 5×6 cells, 31 columns, up to 3 rows.
/// Glyphs are ink masks (the pixels that differ from the paper), so the app can tint them.
public final class PixelFont: Sendable {
    public static let cellWidth = 5
    public static let cellHeight = 6
    public static let columns = 31
    static let space = (row: 0, column: 30)

    private static let rows: [[Character]] = [
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ\"@"),
        Array("0123456789" + "….:()-'!_+\\/[]^&%,=$#"),
        Array("ÅÖÄ?*"),
    ]

    private let masks: [[Bool]] // index row * columns + column

    public init?(png: Data) {
        guard let bitmap = SkinBitmap(data: png),
              bitmap.width >= ThemeImage.pixelFontMinWidth, bitmap.height >= ThemeImage.pixelFontMinHeight,
              let paper = bitmap.color(x: Self.space.column * Self.cellWidth, y: 0) else { return nil }
        let rowCount = min(Self.rows.count, bitmap.height / Self.cellHeight)
        var masks: [[Bool]] = []
        for row in 0..<Self.rows.count {
            for column in 0..<Self.columns {
                var cell: [Bool] = []
                for y in 0..<Self.cellHeight {
                    for x in 0..<Self.cellWidth {
                        guard row < rowCount, let p = bitmap.color(x: column * Self.cellWidth + x, y: row * Self.cellHeight + y) else {
                            cell.append(false); continue
                        }
                        cell.append(abs(p.r - paper.r) + abs(p.g - paper.g) + abs(p.b - paper.b) > 0.1)
                    }
                }
                masks.append(cell)
            }
        }
        // A space with ink means patterned paper: every glyph would come out as a block.
        guard !masks[Self.space.row * Self.columns + Self.space.column].contains(true) else { return nil }
        self.masks = masks
    }

    /// 30 values, row-major (5 wide, 6 tall): `true` where the glyph has ink.
    public func mask(row: Int, column: Int) -> [Bool] {
        let i = row * Self.columns + column
        return masks.indices.contains(i) ? masks[i] : Array(repeating: false, count: Self.cellWidth * Self.cellHeight)
    }

    public static func glyphs(for text: String) -> [(row: Int, column: Int)] { text.map(cell(for:)) }

    /// Uppercase first; otherwise fold the diacritic; otherwise a space.
    public static func cell(for character: Character) -> (row: Int, column: Int) {
        if let c = lookup(String(character).uppercased()) { return c }
        let folded = String(character).folding(options: .diacriticInsensitive, locale: nil).uppercased()
        return lookup(folded) ?? space
    }

    private static func lookup(_ s: String) -> (row: Int, column: Int)? {
        guard s.count == 1, let ch = s.first else { return nil }
        if ch == " " { return space }
        for (row, characters) in rows.enumerated() {
            if let column = characters.firstIndex(of: ch) { return (row, column) }
        }
        return nil
    }
}
```

`"ı".uppercased()` is "I" in Swift (Unicode case mapping), so `ı` needs no special case. `ß` uppercases to "SS" (two characters) and has no fold, so it falls back to a space.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/GreedifyKit && swift test --filter PixelFontTests`
Expected: PASS (6 tests). If `masksMarkInk` fails on the colour threshold, check that `SkinBitmap` returns 0…1 components; don't loosen the test. Then run the full `swift test`.

- [ ] **Step 5: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/PixelFont.swift Packages/GreedifyKit/Tests/GreedifyKitTests/PixelFontTests.swift
git commit -m "feat(theme): PixelFont glyph map and ink masks from text.bmp

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 5: BackdropPlan

**Files:**
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/BackdropPlan.swift`
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/BackdropPlanTests.swift`

**Interfaces:**
- Consumes: `SkinBitmap(data:)`, `SkinBitmap.pixels()` (Task 2), `ThemeColor` (`luminance`, `contrast(with:)`, `blended(toward:_:)`) and `Theme.Colors` / `ThemeBase`.
- Produces: `public struct BackdropPlan: Equatable, Sendable` with:
  - `listsAlpha: Double`, `lyricsAlpha: Double`;
  - `static let alphaSteps: [Double]`;
  - `static func make(backdrop: Data, colors: Theme.Colors, base: ThemeBase) -> BackdropPlan?`;
  - `static func blend(_ worst: ThemeColor, over area: ThemeColor, alpha: Double) -> ThemeColor`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import GreedifyKit

struct BackdropPlanTests {
    let dark = Theme.defaults(for: .dark).colors
    let light = Theme.defaults(for: .light).colors
    func solid(_ c: UInt8, size: Int = 8) -> Data { PNGFixture.make(width: size, height: size) { _, _ in (c, c, c) } }

    func readable(_ plan: BackdropPlan, worst: ThemeColor, colors: Theme.Colors) -> Bool {
        let lists = [colors.surface, colors.background].map { BackdropPlan.blend(worst, over: $0, alpha: plan.listsAlpha) }
        let lyrics = BackdropPlan.blend(worst, over: colors.background, alpha: plan.lyricsAlpha)
        return (lists + [lyrics]).allSatisfy {
            colors.text.contrast(with: $0) >= 4.5 && colors.textSecondary.contrast(with: $0) >= 3
        }
    }

    @Test func brightArtNeedsMoreTintOnADarkTheme() throws {
        let white = try #require(BackdropPlan.make(backdrop: solid(255), colors: dark, base: .dark))
        let black = try #require(BackdropPlan.make(backdrop: solid(0), colors: dark, base: .dark))
        #expect(white.listsAlpha > black.listsAlpha)
        #expect(black.listsAlpha == 0.35)
        #expect(readable(white, worst: .white, colors: dark))
    }

    @Test func lightBaseUsesDarkestPixels() throws {
        let blackArt = try #require(BackdropPlan.make(backdrop: solid(0), colors: light, base: .light))
        let whiteArt = try #require(BackdropPlan.make(backdrop: solid(255), colors: light, base: .light))
        #expect(blackArt.listsAlpha > whiteArt.listsAlpha)
        #expect(readable(blackArt, worst: .black, colors: light))
    }

    @Test func alphasStayInRangeAndLyricsNeverExceedLists() throws {
        for c: UInt8 in [0, 60, 128, 200, 255] {
            let plan = try #require(BackdropPlan.make(backdrop: solid(c), colors: dark, base: .dark))
            #expect(BackdropPlan.alphaSteps.contains(plan.listsAlpha) || plan.listsAlpha == 1)
            #expect(plan.lyricsAlpha <= plan.listsAlpha)
        }
    }

    @Test func percentileIgnoresASmallBrightSpeck() throws {
        // 1 white pixel in 100 is under the 95th percentile, so the plan treats the art as black.
        let speck = PNGFixture.make(width: 10, height: 10) { x, y in x == 0 && y == 0 ? (255, 255, 255) : (0, 0, 0) }
        #expect(BackdropPlan.make(backdrop: speck, colors: dark, base: .dark)?.listsAlpha == 0.35)
    }

    @Test func unreadableThemeGoesOpaque() throws {
        var bad = dark
        bad.text = ThemeColor(hex: "#202020")!  // unreadable even on its own background
        #expect(BackdropPlan.make(backdrop: solid(255), colors: bad, base: .dark)?.listsAlpha == 1)
    }

    @Test func tinyBackdropStillPlans() {
        #expect(BackdropPlan.make(backdrop: solid(0, size: 1), colors: dark, base: .dark) != nil)
        #expect(BackdropPlan.make(backdrop: Data("nope".utf8), colors: dark, base: .dark) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd Packages/GreedifyKit && swift test --filter BackdropPlanTests`
Expected: a build failure, "cannot find 'BackdropPlan' in scope".

- [ ] **Step 3: Write `BackdropPlan.swift`**

```swift
import Foundation

/// How opaque each area's panel must be over the backdrop so text stays readable (theme images spec §5).
public struct BackdropPlan: Equatable, Sendable {
    public let listsAlpha: Double
    public let lyricsAlpha: Double

    public init(listsAlpha: Double, lyricsAlpha: Double) {
        self.listsAlpha = listsAlpha
        self.lyricsAlpha = lyricsAlpha
    }

    /// 0.35, 0.40 … 0.95.
    public static let alphaSteps: [Double] = (7...19).map { Double($0) * 5 / 100 }

    /// nil when the backdrop can't be decoded.
    public static func make(backdrop: Data, colors: Theme.Colors, base: ThemeBase) -> BackdropPlan? {
        guard let pixels = SkinBitmap(data: backdrop)?.pixels(), !pixels.isEmpty else { return nil }
        let sorted = pixels.sorted { $0.luminance < $1.luminance }
        let percentile = base == .dark ? 0.95 : 0.05
        let worst = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * percentile))]
        let overBackground = smallestAlpha(worst: worst, over: colors.background, colors: colors)
        let lists = max(smallestAlpha(worst: worst, over: colors.surface, colors: colors), overBackground)
        return BackdropPlan(listsAlpha: lists, lyricsAlpha: min(lists, overBackground))
    }

    /// The panel color `area` at `alpha` over the backdrop color `worst`.
    public static func blend(_ worst: ThemeColor, over area: ThemeColor, alpha: Double) -> ThemeColor {
        worst.blended(toward: area.withAlpha(1), alpha)
    }

    static func smallestAlpha(worst: ThemeColor, over area: ThemeColor, colors: Theme.Colors) -> Double {
        alphaSteps.first { alpha in
            let composite = blend(worst, over: area, alpha: alpha)
            return colors.text.contrast(with: composite) >= 4.5 && colors.textSecondary.contrast(with: composite) >= 3
        } ?? 1
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/GreedifyKit && swift test --filter BackdropPlanTests`
Expected: PASS (6 tests). Then run the full `swift test`.

- [ ] **Step 5: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/BackdropPlan.swift Packages/GreedifyKit/Tests/GreedifyKitTests/BackdropPlanTests.swift
git commit -m "feat(theme): BackdropPlan picks panel tint that keeps text readable over art

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 6: App — backdrop behind the window, translucent panels, lyrics

**Files:**
- Modify: `App/Views/Shared/ResolvedTheme.swift` (properties, `init`)
- Modify: `App/Views/Shared/ThemeComponents.swift` (`ThemedSurface.fill`; add `ThemeBackdrop`)
- Modify: `App/Views/Main/MainWindow.swift:36` (root backgrounds) and `:113` (sidebar fill)
- Modify: `App/Views/Main/PlayerBar.swift` (`LyricsPanel` solid background)
- Modify: `App/Views/Settings/ThemeSettings.swift:90` (swatch)

**Interfaces:**
- Consumes: `ThemeImage.cgImage`, `Theme.images`, `BackdropPlan.make` and `PixelFont(png:)` (Tasks 1, 4 and 5).
- Produces:
  - `ResolvedTheme.backdrop: CGImage?`, `pixelFont: PixelFont?`, `plan: BackdropPlan?`, `listsAlpha: Double`, `lyricsAlpha: Double` and `init(_ entry: ThemeEntry, loadImages: Bool = true)`;
  - the view `ThemeBackdrop()`.

- [ ] **Step 1: Extend `ResolvedTheme`**

Add stored properties after `var lyrics: LyricsStyle`:

```swift
    /// Skin images, decoded once per theme change; nil for System and themes without images.
    var backdrop: CGImage?
    var pixelFont: PixelFont?
    var plan: BackdropPlan?
    var listsAlpha: Double { plan?.listsAlpha ?? 1 }
    var lyricsAlpha: Double { plan?.lyricsAlpha ?? 1 }
```

Change the signature to `init(_ entry: ThemeEntry, loadImages: Bool = true)`, and at the end of the init add:

```swift
        if loadImages, !entry.isSystem, let t = entry.theme {
            backdrop = t.images.backdrop.flatMap(ThemeImage.cgImage)
            plan = backdrop == nil ? nil : t.images.backdrop.flatMap { BackdropPlan.make(backdrop: $0, colors: t.colors, base: t.base) }
            pixelFont = t.images.pixelFont.flatMap(PixelFont.init(png:))
        }
```

If the compiler rejects `ResolvedTheme: Sendable` because `CGImage` isn't `Sendable` in this SDK, declare the conformance as `@unchecked Sendable`: every property is an immutable value after init. Note that in the report.

In `App/Views/Settings/ThemeSettings.swift:90`, change `let t = ResolvedTheme(entry)` to `let t = ResolvedTheme(entry, loadImages: false)`. The swatches only show colours, and this avoids decoding images on every render.

- [ ] **Step 2: Make the fills translucent over a backdrop**

In `ThemeComponents.swift` `ThemedSurface`:

```swift
    private var fill: Color {
        switch kind {
        case .content: theme.background.opacity(theme.listsAlpha)
        case .surface: theme.surface.opacity(theme.listsAlpha)
        case .raised: theme.raised
        }
    }
```

Add the backdrop view to the same file:

```swift
/// The skin's artwork behind the whole window, crisp and aspect-filled (theme images spec §6).
/// Only ever used as a background, so it never sizes its parent.
struct ThemeBackdrop: View {
    @Environment(\.theme) private var theme
    var body: some View {
        if let image = theme.backdrop {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        }
    }
}
```

- [ ] **Step 3: Wire the window, sidebar and lyrics**

`MainWindow.swift` root: directly after the `VStack(spacing: 0) { … }` closes (before the existing `.background { Button("") … }`), add:

```swift
        .background { ThemeBackdrop() }
```

`MainWindow.swift:113` (the Sidebar): change `theme.surface.ignoresSafeArea()` to `theme.surface.opacity(theme.listsAlpha).ignoresSafeArea()`.

`PlayerBar.swift` `LyricsPanel`: change `theme.background.ignoresSafeArea()` to `theme.background.opacity(theme.lyricsAlpha).ignoresSafeArea()`.

- [ ] **Step 4: Build**

Run: `xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run and check**

1. Create a backdrop theme without the UI. Write a throwaway test (never commit it) that reads `~/Downloads/diablo_ii.wsz`, calls `SkinThemeMapper.theme(fromArchive:fileName:installedFonts:)` with `["Copperplate", "Arial"]`, and writes `theme.encoded()` to `~/Library/Application Support/Greedify/Themes/diablo_ii 2.greedifytheme`. Then delete the test.
2. Run `scripts/install.sh`.
3. Run `defaults write com.alperen.greedify debugHooks -bool YES`, relaunch, open the main window, turn lyrics on, and select the theme with the hook:

```bash
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(CommandLine.arguments[1]), object: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil, deliverImmediately: true)' com.alperen.greedify.debug.theme "diablo_ii 2.greedifytheme"
```

4. Confirm `pgrep -x Greedify` and that the log has no crash.
5. Afterwards, switch back to `builtin.system` and run `defaults delete com.alperen.greedify debugHooks`.

The user checks how it looks. Note in the report whether the sidebar column shows the backdrop, or its own system material covers it; either is acceptable.

- [ ] **Step 6: Commit**

```bash
git add App/Views/Shared/ResolvedTheme.swift App/Views/Shared/ThemeComponents.swift App/Views/Main/MainWindow.swift App/Views/Main/PlayerBar.swift App/Views/Settings/ThemeSettings.swift
git commit -m "feat(theme): skin artwork behind the window with readable translucent panels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 7: App — skinned player bar and pixel-font title

**Files:**
- Modify: `App/Views/Shared/ThemeComponents.swift` (`SurfaceKind.bar`, `ThemedSurface`, `themedTile()`, `BackdropStrip`, `PixelText`)
- Modify: `App/Views/Main/PlayerBar.swift` (lines 19, 24, 41, 59 and 63)

**Interfaces:**
- Consumes: `ResolvedTheme.backdrop`, `pixelFont`, `listsAlpha` (Task 6) and `PixelFont.glyphs(for:)`, `mask(row:column:)`, `cellWidth`, `cellHeight` (Task 4).
- Produces: `SurfaceKind.bar`, `View.themedTile()`, `BackdropStrip(image:)` and `PixelText(text:font:scale:)`.

- [ ] **Step 1: Add `.bar`, the tile modifier and the strip**

In `ThemeComponents.swift`:
- change `enum SurfaceKind { case content, surface, raised }` to `enum SurfaceKind { case content, surface, raised, bar }`;
- in `ThemedSurface.body`, change the System line to `if kind == .surface || kind == .bar { content.background(.bar) } else { content }`;
- replace `.background { fill.ignoresSafeArea() }` with `.background { backdropOrFill.ignoresSafeArea() }`.

Then add and adjust:

```swift
    /// The bar wears the skin's art when there is one; everything else is a plain fill.
    @ViewBuilder private var backdropOrFill: some View {
        if kind == .bar, let image = theme.backdrop { BackdropStrip(image: image) } else { fill }
    }

    private var fill: Color {
        switch kind {
        case .content: theme.background.opacity(theme.listsAlpha)
        case .surface, .bar: theme.surface.opacity(theme.listsAlpha)
        case .raised: theme.raised
        }
    }
```

Add to the file:

```swift
extension View {
    /// Over a skinned player bar, a group of controls sits on a tinted tile; otherwise nothing changes.
    func themedTile() -> some View { modifier(ThemedTile()) }
}

private struct ThemedTile: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        if theme.backdrop != nil {
            content
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: theme.buttonRadius).fill(theme.surface.opacity(theme.listsAlpha)))
        } else {
            content
        }
    }
}

/// The backdrop scaled to the bar's height, never smoothed, tiled horizontally (theme images spec §6).
struct BackdropStrip: View {
    let image: CGImage
    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.height / CGFloat(max(1, image.height))
            let tile = max(1, CGFloat(image.width) * scale)
            HStack(spacing: 0) {
                ForEach(0..<max(1, Int((geo.size.width / tile).rounded(.up))), id: \.self) { _ in
                    Image(decorative: image, scale: 1).resizable().interpolation(.none).frame(width: tile, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipped()
        }
    }
}

/// A line in the skin's pixel font, drawn cell by cell and tinted with the theme's text color
/// (theme images spec §6). Clipped at a glyph boundary; VoiceOver reads the real text.
struct PixelText: View {
    @Environment(\.theme) private var theme
    let text: String
    let font: PixelFont
    var scale: CGFloat = 2

    var body: some View {
        let glyphs = PixelFont.glyphs(for: text)
        let cellWidth = CGFloat(PixelFont.cellWidth) * scale
        Canvas { context, size in
            var ink = Path()
            for (i, glyph) in glyphs.prefix(Int(size.width / cellWidth)).enumerated() {
                let mask = font.mask(row: glyph.row, column: glyph.column)
                for y in 0..<PixelFont.cellHeight {
                    for x in 0..<PixelFont.cellWidth where mask[y * PixelFont.cellWidth + x] {
                        ink.addRect(CGRect(x: CGFloat(i) * cellWidth + CGFloat(x) * scale, y: CGFloat(y) * scale,
                                           width: scale, height: scale))
                    }
                }
            }
            context.fill(ink, with: .color(theme.text))
        }
        .frame(maxWidth: CGFloat(glyphs.count) * cellWidth, alignment: .leading)
        .frame(height: CGFloat(PixelFont.cellHeight) * scale)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
```

- [ ] **Step 2: Wire the player bar**

In `PlayerBar.swift`:

Line 19, the title:

```swift
                    if let pixelFont = theme.pixelFont {
                        PixelText(text: player.track?.name ?? "Nothing playing", font: pixelFont)
                    } else {
                        Text(player.track?.name ?? "Nothing playing").fontWeight(.semibold).lineLimit(1)
                    }
```

Add `.themedTile()` immediately before each of these three lines:
- line 24, `.frame(minWidth: 160, idealWidth: 280, maxWidth: 280, alignment: .leading)`;
- line 41, `.frame(maxWidth: .infinity)`, the transport and progress `VStack`;
- line 59, `.frame(minWidth: 250, idealWidth: 350, maxWidth: 350, alignment: .trailing)`.

Line 63: `.themedSurface(.surface)` → `.themedSurface(.bar)`.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run and check**

1. `scripts/install.sh`, with debug hooks on.
2. Select `diablo_ii 2.greedifytheme` via the `debug.theme` hook, and open the main window with a song playing.
3. Then alternate that theme, `builtin.classic` and `builtin.system` via the hook while running resize (`900x560`, `1400x800`, `1000x600`) and zoom ×2, for 3 rounds, without relaunching.
4. Confirm `pgrep -x Greedify` gives the same pid throughout and the log has no crash.
5. Reset to `builtin.system` and delete `debugHooks`.

The user checks the looks: the art strip in the bar, the tiles, and the pixel-font title.

- [ ] **Step 5: Commit**

```bash
git add App/Views/Shared/ThemeComponents.swift App/Views/Main/PlayerBar.swift
git commit -m "feat(theme): skinned player bar and pixel-font now-playing title

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 8: Verification and docs

**Files:**
- Modify: `docs/verification.md` (the Themes section)
- Modify: `CLAUDE.md` (the Themes bullet under "Changes since the plan")
- Modify: `docs/superpowers/specs/2026-09-30-theme-images-design.md` (`Status:`)

- [ ] **Step 1: Full suite**

Run: `cd Packages/GreedifyKit && swift test`
Expected: every test passes. Record the count.

- [ ] **Step 2: Real skins**

Use a throwaway test (never committed) to convert `~/Downloads/diablo_ii.wsz`, `~/Downloads/base-2.91.wsz` and `~/Downloads/Winamp5_Classified_v5.5.wsz`, with `installedFonts: NSFontManager.shared.availableFontFamilies` (the test file does `import AppKit`). For each skin, print:
- the matched family;
- the backdrop size;
- whether a pixel font exists, and its width and height;
- `BackdropPlan` `listsAlpha` and `lyricsAlpha`.

Write each result to `~/Library/Application Support/Greedify/Themes/<name> 2.greedifytheme` so the user can switch to them in Settings. Delete the throwaway test.

- [ ] **Step 3: Memory**

Run `scripts/measure-memory.sh`, with the main window opened and closed via the debug hooks, for `builtin.system` and for `diablo_ii 2`. Expected: within the CLAUDE.md profile (window open 56–74 MB; after closing about 52–59 MB).

- [ ] **Step 4: Docs**

In `docs/verification.md` Themes, add a "Theme images" subsection with:
- the test count;
- the table from Step 2;
- the live-switch stress result from Task 7;
- the memory numbers;
- "Needs a human": the backdrop behind the window and lyrics, the skinned player bar, the pixel-font title, and the matched fonts, for each of the three skins.

In `CLAUDE.md`, extend the Themes bullet with:

```markdown
Imported skins also carry `images` (base64 PNG `backdrop` from main.bmp and `pixelFont` from text.bmp); `BackdropPlan` sets how translucent the panels are over the art, `PixelText` draws the now-playing title in the skin's font, and `FontMatcher` near-matches the pledit.txt font. Spec: `docs/superpowers/specs/2026-09-30-theme-images-design.md`.
```

Set the spec's `Status:` to `implemented`.

- [ ] **Step 5: Commit**

```bash
git add docs/verification.md CLAUDE.md docs/superpowers/specs/2026-09-30-theme-images-design.md
git commit -m "docs: theme images verified; CLAUDE.md notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```
