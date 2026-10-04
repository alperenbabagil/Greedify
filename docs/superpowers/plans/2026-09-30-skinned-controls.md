# Skinned Player Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Imported Winamp skins style the player bar's and popover's controls: vector buttons in the skin's colours, the skin's own seek bar, volume ramp and digits (smoothed 4×), and a flat panel instead of the tiled `main.bmp`.

**Architecture:**

- **Package, import time:** the importer slices the classic sprite sheets and samples a colour palette (`SkinControlPalette`). It stores the palette as `Theme.Controls`, plus three cropped PNGs in `Theme.Images`.
- **Package, load time:** `SkinControlImages` slices those PNGs and upscales them with Scale2x twice (`PixelScaler`), off the main actor.
- **App:** `ResolvedTheme.controls` (`SkinControls`) feeds a vector `SkinButtonStyle`, skin variants of `ThemedSlider`, and `SkinDigits`.

**Tech Stack:** Swift 6, SwiftUI, CoreGraphics/ImageIO, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-30-skinned-controls-design.md`

## Global Constraints

- The theme format stays `version` 1. The new keys (`controls`, `images.seekBar`, `images.volume`, `images.digits`) are additive, and decoding is lenient per key.
- Each theme image is at most 512 KB (`Theme.Images.maxBytes`) and at most 2048×2048 px (`ThemeImage.maxPixels`).
- A glyph is used only at ≥ 3:1 contrast against the average face; otherwise it's `nil` and the app uses the theme's `text`.
- The upscale is exactly 4× (`SkinControlImages.scale = 4`), Scale2x run twice. It runs off the main actor (in `ThemeImages`).
- Draw with SwiftUI `Image` / `Canvas`, never `ImageRenderer` (CLAUDE.md: ImageRenderer keeps GPU buffers).
- In the main window and popover, style through the themed helpers (`.themed`, `.themedFont`, `.themedSurface`, `.themedButton`, `ThemedSlider`, and now `.skinnedControl`), never raw `.secondary` / `.bar` / `Slider`.
- No new dependencies. Package code is TDD: watch the test fail, then pass. App changes are verified by building and a real run.
- Never replace the installed app while music is playing without asking the user: check `osascript -e 'tell application "Greedify" to player state as string'` first.
- Commits end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ
  ```

## Review Focus

1. **Sheets larger than standard** (a 200×50 `cbuttons.bmp`) must still be sliced at the standard coordinates, not rejected. Pinned in Task 3.
2. **Volume at exactly 0 or 100, or out of range** must pick frame 0 or 27 and never index out of bounds. Pinned in Task 5 (`volumeFrameIndex`).
3. **Switching to a skin before its images finish decoding:** the colours already apply, and every sprite part must fall back (`SkinControlImages.empty`). Pinned in Task 5 (`emptyHasNoParts`), and each view checks its part.
4. **A `volume.bmp` without handles (68×420):** frames are kept, and the handle becomes a vector knob. Pinned in Tasks 4 and 5.
5. **Times with hours (`1:02:03`) or before anything plays (`0:00`):** `SkinDigits` draws every colon and digit. Checked in Task 8's real run.

---

## File Structure

Package (`Packages/GreedifyKit/Sources/GreedifyKit/`):

| File | What changes |
|---|---|
| `Theme/RGBAImage.swift` | **Create.** Straight RGBA pixel buffer: decode, crop, paste, back to `CGImage`. |
| `Theme/PixelScaler.swift` | **Create.** `scale2x` and `scale4x`. |
| `Theme/Theme.swift` | **Modify.** `Theme.Controls`, the new `Images` keys and the codec. |
| `Theme/Winamp/SkinBitmap.swift` | **Modify.** `colors(in:)` for a rect. |
| `Theme/Winamp/SkinControlPalette.swift` | **Create.** Samples `Theme.Controls` from `cbuttons`, `shufrep` and `main`. |
| `Theme/Winamp/SkinSprites.swift` | **Create.** Crops the posbar, volume and digit sheets into the stored PNGs. |
| `Theme/Winamp/WinampSkin.swift` | **Modify.** Reads the new sheets. |
| `Theme/Winamp/SkinThemeMapper.swift` | **Modify.** Copies controls and images into the theme. |
| `Theme/SkinControlImages.swift` | **Create.** Load-time slicing and 4× smoothing. |

Package tests (`Packages/GreedifyKit/Tests/GreedifyKitTests/`):

| File | What changes |
|---|---|
| `Support/SkinSheets.swift` | **Create.** Synthetic standard sprite sheets. |
| `PixelScalerTests.swift` | **Create.** |
| `SkinControlsTests.swift` | **Create.** Palette, sprites, control images, import end to end. |
| `ThemeTests.swift` | **Modify.** Codec tests. |

App (`App/Views/`):

| File | What changes |
|---|---|
| `Shared/SkinControls.swift` | **Create.** `SkinControls`, `SkinControlSize`, `SkinButtonFace`, `SkinButtonStyle`, `.skinnedControl`, `SkinDigits`. |
| `Shared/ResolvedTheme.swift` | **Modify.** `controls`, and `ThemeImages.controlImages`. |
| `Shared/ThemeComponents.swift` | **Modify.** Bar panel fill; delete `BackdropStrip` and `ThemedTile`; `BevelEdges` colours; `ThemedSlider` skins. |
| `Shared/Shared.swift` | **Modify.** `ProgressBar` digits and seek skin, `TransportControls`, `LikeButton`. |
| `Main/PlayerBar.swift` | **Modify.** Drop the tiles; skinned buttons and volume. |

Docs: `CLAUDE.md`, the spec's status, and `docs/verification.md`.

---

### Task 1: RGBAImage and PixelScaler

**Files:**
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/RGBAImage.swift`
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/PixelScaler.swift`
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/PixelScalerTests.swift`

**Interfaces:**
- Produces:
  - `public struct RGBAImage: Equatable, Sendable` with:
    - `width`, `height`, `pixels: [UInt32]`, where each pixel is `0xRRGGBBAA`;
    - `init(width:height:pixels:)` and `init(width:height:fill:)`;
    - `init?(_ image: CGImage)`;
    - `subscript(x: Int, y: Int) -> UInt32`;
    - `func crop(x:y:width:height:) -> RGBAImage?`;
    - `mutating func paste(_:x:y:)`;
    - `func cgImage() -> CGImage?`.
  - `public enum PixelScaler` with `static func scale2x(_: RGBAImage) -> RGBAImage` and `static func scale4x(_: RGBAImage) -> RGBAImage`.

- [ ] **Step 1: Write the failing tests**

Create `Packages/GreedifyKit/Tests/GreedifyKitTests/PixelScalerTests.swift`:

```swift
import Foundation
import Testing
@testable import GreedifyKit

struct PixelScalerTests {
    let K: UInt32 = 0xFF0000FF, P: UInt32 = 0x00FF00FF, Q: UInt32 = 0x0000FFFF, Z: UInt32 = 0x777777FF

    @Test func flatStaysFlatAtTwiceTheSize() {
        let out = PixelScaler.scale2x(RGBAImage(width: 3, height: 2, fill: P))
        #expect(out.width == 6 && out.height == 4)
        #expect(out.pixels.allSatisfy { $0 == P })
    }

    /// Scale2x: E0 = A when C == A, C != D, A != B (A above, B right, C left, D below); E3 likewise toward D.
    @Test func cornersFollowMatchingNeighbours() {
        let image = RGBAImage(width: 3, height: 3, pixels: [Z, K, Z,
                                                           K, P, Q,
                                                           Z, Q, Z])
        let out = PixelScaler.scale2x(image)
        #expect(out[2, 2] == K)   // top-left of the centre: up and left agree
        #expect(out[3, 2] == P)
        #expect(out[2, 3] == P)
        #expect(out[3, 3] == Q)   // bottom-right: right and down agree
    }

    @Test func aLonePixelStaysABlock() {
        let image = RGBAImage(width: 3, height: 3, pixels: [Z, Z, Z, Z, P, Z, Z, Z, Z])
        let out = PixelScaler.scale2x(image)
        #expect([out[2, 2], out[3, 2], out[2, 3], out[3, 3]] == [P, P, P, P])
    }

    @Test func scale4xIsScale2xTwice() {
        let image = RGBAImage(width: 3, height: 3, pixels: [Z, K, Z, K, P, Q, Z, Q, Z])
        let out = PixelScaler.scale4x(image)
        #expect(out == PixelScaler.scale2x(PixelScaler.scale2x(image)))
        #expect(out.width == 12 && out.height == 12)
    }

    @Test func cropPasteAndCGImageRoundTrip() throws {
        var canvas = RGBAImage(width: 4, height: 3, fill: Z)
        canvas.paste(RGBAImage(width: 2, height: 1, fill: K), x: 1, y: 2)
        #expect(canvas[1, 2] == K && canvas[3, 2] == Z && canvas[1, 1] == Z)
        #expect(canvas.crop(x: 1, y: 2, width: 2, height: 1) == RGBAImage(width: 2, height: 1, fill: K))
        #expect(canvas.crop(x: 3, y: 0, width: 2, height: 1) == nil)      // runs off the right edge
        let back = try #require(canvas.cgImage().flatMap(RGBAImage.init))
        #expect(back == canvas)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/GreedifyKit && swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `cannot find 'PixelScaler' in scope` / `cannot find 'RGBAImage' in scope`.

- [ ] **Step 3: Implement RGBAImage**

Create `Packages/GreedifyKit/Sources/GreedifyKit/Theme/RGBAImage.swift`:

```swift
import CoreGraphics
import Foundation

/// Straight (not premultiplied) RGBA pixels, row by row from the top, one `0xRRGGBBAA` per pixel.
/// Skin sprites are sliced and upscaled in this form (skinned controls spec §4).
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt32]

    public init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(width >= 0 && height >= 0 && pixels.count == width * height)
        self.width = width; self.height = height; self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt32) {
        self.init(width: width, height: height, pixels: Array(repeating: fill, count: width * height))
    }

    /// Decodes without smoothing, in the image's own RGB space so skin colours aren't converted.
    /// Skin sprites are opaque, so drawing premultiplied loses nothing.
    public init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w * h <= ThemeImage.maxPixels else { return nil }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(data: pointer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        self.init(width: w, height: h, pixels: stride(from: 0, to: bytes.count, by: 4).map { i in
            UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
        })
    }

    public subscript(x: Int, y: Int) -> UInt32 { pixels[y * width + x] }

    /// The rectangle as its own image; nil when it doesn't fit inside this one.
    public func crop(x: Int, y: Int, width w: Int, height h: Int) -> RGBAImage? {
        guard x >= 0, y >= 0, w > 0, h > 0, x + w <= width, y + h <= height else { return nil }
        var out: [UInt32] = []
        out.reserveCapacity(w * h)
        for row in y..<(y + h) { out += pixels[(row * width + x)..<(row * width + x + w)] }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    /// Copies `image` in with its top-left at (x, y); what falls outside is dropped.
    public mutating func paste(_ image: RGBAImage, x: Int, y: Int) {
        for row in 0..<image.height where (0..<height).contains(y + row) {
            for column in 0..<image.width where (0..<width).contains(x + column) {
                pixels[(y + row) * width + x + column] = image[column, row]
            }
        }
    }

    public func cgImage() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(pixels.count * 4)
        for p in pixels { bytes += [UInt8(p >> 24), UInt8(p >> 16 & 0xFF), UInt8(p >> 8 & 0xFF), UInt8(p & 0xFF)] }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
```

- [ ] **Step 4: Implement PixelScaler**

Create `Packages/GreedifyKit/Sources/GreedifyKit/Theme/PixelScaler.swift`:

```swift
import Foundation

/// Edge-aware pixel-art upscaling for skin sprites (skinned controls spec §4). Scale2x (EPX / AdvMAME2x) follows
/// matching neighbours into each corner, so diagonals and curves come out stepped-smooth and nothing is blurred.
public enum PixelScaler {
    public static func scale2x(_ src: RGBAImage) -> RGBAImage {
        let w = src.width, h = src.height
        var out = [UInt32](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p = src[x, y]
                let a = y > 0 ? src[x, y - 1] : p       // above
                let b = x < w - 1 ? src[x + 1, y] : p   // right
                let c = x > 0 ? src[x - 1, y] : p       // left
                let d = y < h - 1 ? src[x, y + 1] : p   // below
                let o = 2 * y * 2 * w + 2 * x
                out[o] = c == a && c != d && a != b ? a : p
                out[o + 1] = a == b && a != c && b != d ? b : p
                out[o + 2 * w] = d == c && d != b && c != a ? c : p
                out[o + 2 * w + 1] = b == d && b != a && d != c ? d : p
            }
        }
        return RGBAImage(width: 2 * w, height: 2 * h, pixels: out)
    }

    public static func scale4x(_ src: RGBAImage) -> RGBAImage { scale2x(scale2x(src)) }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd Packages/GreedifyKit && swift test --filter PixelScalerTests 2>&1 | grep -E "✘|Test run with"`
Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/RGBAImage.swift Packages/GreedifyKit/Sources/GreedifyKit/Theme/PixelScaler.swift Packages/GreedifyKit/Tests/GreedifyKitTests/PixelScalerTests.swift
git commit -m "feat(theme): RGBA buffers and Scale2x upscaling for skin sprites" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 2: Theme.Controls and the new image keys

**Files:**
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Theme.swift`
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/ThemeTests.swift` (append)

**Interfaces:**
- Produces:
  - `public struct Theme.Controls: Equatable, Sendable`:
    - optional `ThemeColor` fields `faceTop`, `faceBottom`, `highlight`, `shadow`, `glyph`, `pressedFaceTop`, `pressedFaceBottom`, `pressedGlyph`, `on`, `panel`;
    - `public init()` with all fields nil;
    - `public var isUsable: Bool`, true when `faceTop`, `faceBottom` and `panel` are all set.
  - `public var Theme.controls: Controls?`.
  - `Theme.Images` gains `seekBar`, `volume` and `digits: Data?`, with `init(backdrop:pixelFont:seekBar:volume:digits:)` (all defaulting to nil).

- [ ] **Step 1: Write the failing tests**

Append to `Packages/GreedifyKit/Tests/GreedifyKitTests/ThemeTests.swift`:

```swift
struct ThemeControlsCodecTests {
    func png() -> Data { PNGFixture.make(width: 2, height: 2) { _, _ in (10, 20, 30) } }

    @Test func controlsAndControlImagesRoundTrip() throws {
        var theme = Theme.defaults(for: .dark)
        var controls = Theme.Controls()
        controls.faceTop = ThemeColor(hex: "#6070A0"); controls.faceBottom = ThemeColor(hex: "#405080")
        controls.panel = ThemeColor(hex: "#4A5A86"); controls.glyph = ThemeColor(hex: "#F0F0F0"); controls.on = ThemeColor(hex: "#7CFF4F")
        theme.controls = controls
        theme.images = Theme.Images(seekBar: png(), volume: png(), digits: png())
        let back = try Theme.decode(from: theme.encoded())
        #expect(back.controls == controls)
        #expect(back.images == theme.images)
    }

    @Test func oldFilesHaveNoControls() throws {
        let theme = try Theme.decode(from: Data(#"{"version":1,"name":"Old","images":{"backdrop":""}}"#.utf8))
        #expect(theme.controls == nil)
        #expect(theme.images.seekBar == nil && theme.images.volume == nil && theme.images.digits == nil)
    }

    @Test func aBadColourIsDroppedAlone() throws {
        let json = #"{"controls":{"faceTop":"#6070A0","faceBottom":"#405080","panel":"#4A5A86","glyph":"nope"}}"#
        let controls = try #require(try Theme.decode(from: Data(json.utf8)).controls)
        #expect(controls.glyph == nil && controls.faceTop == ThemeColor(hex: "#6070A0"))
    }

    @Test func controlsWithoutAFaceOrPanelAreDropped() throws {
        let json = #"{"controls":{"faceTop":"#6070A0","glyph":"#FFFFFF"}}"#
        #expect(try Theme.decode(from: Data(json.utf8)).controls == nil)
        var theme = Theme.defaults(for: .dark)
        theme.controls = Theme.Controls()           // unusable: not written
        #expect(!String(decoding: try theme.encoded(), as: UTF8.self).contains("controls"))
    }

    @Test func aBadControlImageIsDroppedAlone() throws {
        let good = png().base64EncodedString()
        let json = #"{"images":{"seekBar":"\#(good)","volume":"bm90IGEgcG5n","digits":"\#(good)"}}"#
        let images = try Theme.decode(from: Data(json.utf8)).images
        #expect(images.seekBar != nil && images.volume == nil && images.digits != nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/GreedifyKit && swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `type 'Theme' has no member 'Controls'`.

- [ ] **Step 3: Implement**

In `Theme.swift`, replace the `Images` struct with:

```swift
    /// Optional skin images, stored in the file as base64 PNG (theme images spec §2, skinned controls spec §3.3).
    public struct Images: Equatable, Sendable {
        public static let maxBytes = 524_288
        public var backdrop: Data?
        public var pixelFont: Data?
        /// `posbar.bmp` as a 307×10 strip: groove, handle, pressed handle.
        public var seekBar: Data?
        /// `volume.bmp`: 28 fill frames, then the handles when the skin has them.
        public var volume: Data?
        /// Digits 0–9 and a blank (99×13), plus a minus when the skin has one (108×13).
        public var digits: Data?
        public init(backdrop: Data? = nil, pixelFont: Data? = nil, seekBar: Data? = nil, volume: Data? = nil, digits: Data? = nil) {
            self.backdrop = backdrop; self.pixelFont = pixelFont; self.seekBar = seekBar; self.volume = volume; self.digits = digits
        }
        public var isEmpty: Bool { backdrop == nil && pixelFont == nil && seekBar == nil && volume == nil && digits == nil }

        /// PNG bytes within the size limit, else nil.
        static func accept(_ data: Data?) -> Data? {
            guard let data, data.count <= maxBytes, ThemeImage.isPNG(data) else { return nil }
            return data
        }
    }

    /// A skin's button colours, sampled from its sprites (skinned controls spec §3.2).
    public struct Controls: Equatable, Sendable {
        public var faceTop, faceBottom, highlight, shadow, glyph: ThemeColor?
        public var pressedFaceTop, pressedFaceBottom, pressedGlyph: ThemeColor?
        public var on, panel: ThemeColor?
        public init() {}
        /// Enough to draw a button and the bar.
        public var isUsable: Bool { faceTop != nil && faceBottom != nil && panel != nil }
    }
```

After `public var images = Images()`, add:

```swift
    public var controls: Controls?
```

In the `Codable` extension, change `Keys` and `ImageKeys` and add `ControlKeys`:

```swift
    private enum Keys: String, CodingKey { case version, name, author, source, base, colors, fonts, shapes, lyrics, images, controls }
    private enum ImageKeys: String, CodingKey { case backdrop, pixelFont, seekBar, volume, digits }
    private enum ControlKeys: String, CodingKey {
        case faceTop, faceBottom, highlight, shadow, glyph, pressedFaceTop, pressedFaceBottom, pressedGlyph, on, panel
    }
    private static var controlPaths: [(ControlKeys, WritableKeyPath<Controls, ThemeColor?>)] {
        [(.faceTop, \.faceTop), (.faceBottom, \.faceBottom), (.highlight, \.highlight), (.shadow, \.shadow), (.glyph, \.glyph),
         (.pressedFaceTop, \.pressedFaceTop), (.pressedFaceBottom, \.pressedFaceBottom), (.pressedGlyph, \.pressedGlyph),
         (.on, \.on), (.panel, \.panel)]
    }
```

In `init(from:)`, replace the images line with the new images line, and add controls decoding before `self = t`:

```swift
            t.images = Images(backdrop: image(.backdrop), pixelFont: image(.pixelFont),
                              seekBar: image(.seekBar), volume: image(.volume), digits: image(.digits))
        }
        if let kc = try? c.nestedContainer(keyedBy: ControlKeys.self, forKey: .controls) {
            var controls = Controls()
            for (key, path) in Self.controlPaths {
                if let hex = try? kc.decode(String.self, forKey: key), let color = ThemeColor(hex: hex) { controls[keyPath: path] = color }
            }
            t.controls = controls.isUsable ? controls : nil
        }
```

(The existing `t.images = Images(backdrop: image(.backdrop), pixelFont: image(.pixelFont))` line and its closing `}` are what the first two lines above replace.)

In `encode(to:)`, extend the images block and add controls after it:

```swift
        if !images.isEmpty {
            var ic = c.nestedContainer(keyedBy: ImageKeys.self, forKey: .images)
            try ic.encodeIfPresent(images.backdrop?.base64EncodedString(), forKey: .backdrop)
            try ic.encodeIfPresent(images.pixelFont?.base64EncodedString(), forKey: .pixelFont)
            try ic.encodeIfPresent(images.seekBar?.base64EncodedString(), forKey: .seekBar)
            try ic.encodeIfPresent(images.volume?.base64EncodedString(), forKey: .volume)
            try ic.encodeIfPresent(images.digits?.base64EncodedString(), forKey: .digits)
        }
        if let controls, controls.isUsable {
            var kc = c.nestedContainer(keyedBy: ControlKeys.self, forKey: .controls)
            for (key, path) in Self.controlPaths { try kc.encodeIfPresent(controls[keyPath: path]?.hex, forKey: key) }
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Packages/GreedifyKit && swift test 2>&1 | grep -E "✘|Test run with"`
Expected: all tests pass (5 new).

- [ ] **Step 5: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/Theme.swift Packages/GreedifyKit/Tests/GreedifyKitTests/ThemeTests.swift
git commit -m "feat(theme): controls palette and control images in theme files" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 3: SkinControlPalette (and the synthetic sheets)

**Files:**
- Create: `Packages/GreedifyKit/Tests/GreedifyKitTests/Support/SkinSheets.swift`
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinBitmap.swift` (add `colors(in:)`)
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinControlPalette.swift`
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/SkinControlsTests.swift`

**Interfaces:**
- Consumes: `Theme.Controls` (Task 2).
- Produces:
  - `enum SkinControlPalette` (internal) with `struct Rect { x, y, w, h: Int }` and `static func make(cbuttons: SkinBitmap?, shufrep: SkinBitmap?, main: SkinBitmap?) -> Theme.Controls?`.
  - The glyph rule: pixels with squared RGB distance > 0.02 from their row's median.
  - `SkinBitmap.colors(in: SkinControlPalette.Rect) -> [ThemeColor]`.
  - The test helper `SkinSheets` (colours as `(UInt8, UInt8, UInt8)`, sheets as BMP `Data`), used by Tasks 4 and 5.

- [ ] **Step 1: Write the synthetic sheets**

Create `Packages/GreedifyKit/Tests/GreedifyKitTests/Support/SkinSheets.swift`:

```swift
import Foundation
@testable import GreedifyKit

/// Standard-size Winamp sprite sheets with known colours (never real skins: those belong to their authors).
enum SkinSheets {
    typealias RGB = (UInt8, UInt8, UInt8)
    static let back: RGB = (0x10, 0x10, 0x10)
    static let highlight: RGB = (0xC0, 0xC8, 0xE0), shadow: RGB = (0x20, 0x28, 0x40)
    static let faceTop: RGB = (0x60, 0x70, 0xA0), faceBottom: RGB = (0x40, 0x50, 0x80), glyph: RGB = (0xF0, 0xF0, 0xF0)
    static let pressedTop: RGB = (0x40, 0x50, 0x78), pressedBottom: RGB = (0x30, 0x40, 0x68), pressedGlyph: RGB = (0xFF, 0xFF, 0xFF)
    static let lit: RGB = (0x7C, 0xFF, 0x4F), panel: RGB = (0x4A, 0x5A, 0x86)
    static let groove: RGB = (0x11, 0x22, 0x33), handle: RGB = (0xA0, 0xA0, 0xA0), handlePressed: RGB = (0xB0, 0xB0, 0xB0)
    static let ink: RGB = (0x00, 0xC8, 0x00)

    static func color(_ c: RGB) -> ThemeColor { ThemeColor(r8: Int(c.0), g8: Int(c.1), b8: Int(c.2)) }
    static func bitmap(_ data: Data) -> SkinBitmap { SkinBitmap(data: data)! }

    /// Play button at (23, 0, 23, 18), pressed at (23, 18, 23, 18): a highlight top/left edge, a shadow bottom/right
    /// edge, a face darker in its lower half, and a 6×6 glyph at x 31…36, y 6…11 (offset by 18 when pressed).
    static func cbuttons(width: Int = 136, height: Int = 36, glyphColor: RGB = glyph) -> Data {
        BMPBuilder.make(width: width, height: height) { x, y in
            guard (23..<46).contains(x), y < 36 else { return back }
            let pressed = y >= 18, top = pressed ? 18 : 0, ly = y - top
            if ly == 0 || x == 23 { return highlight }
            if ly == 17 || x == 45 { return shadow }
            if (31...36).contains(x), (6...11).contains(ly) { return pressed ? pressedGlyph : glyphColor }
            return ly < 9 ? (pressed ? pressedTop : faceTop) : (pressed ? pressedBottom : faceBottom)
        }
    }

    /// Grey sheet with a lit indicator inside the shuffle-on sprite (28, 30, 47, 15).
    static func shufrep() -> Data {
        BMPBuilder.make(width: 92, height: 85) { x, y in (40..<44).contains(x) && (36..<39).contains(y) ? lit : (0x30, 0x30, 0x30) }
    }

    /// Mostly red, with the control area (rows 88…115) in the panel colour.
    static func main() -> Data { BMPBuilder.make(width: 275, height: 116) { _, y in y >= 88 ? panel : (0x90, 0x10, 0x10) } }

    /// Groove over x 0…247, handle at 248…276, pressed handle at 278…306 (when wide enough).
    static func posbar(width: Int = 307) -> Data {
        BMPBuilder.make(width: width, height: 10) { x, _ in x < 248 ? groove : x < 277 ? handle : x >= 278 ? handlePressed : back }
    }

    /// Frame i (rows 15i…15i+12) is filled with red = 9·i; the handles at y 422 are pressed (x 0…13) and normal (x 15…28).
    static func volume(height: Int = 433) -> Data {
        BMPBuilder.make(width: 68, height: height) { x, y in
            if y >= 422 { return x < 14 ? handlePressed : (15..<29).contains(x) ? handle : back }
            return y % 15 < 13 ? (UInt8(9 * (y / 15)), 0x40, 0x40) : back
        }
    }

    /// Digit d (x 9d…9d+8) is black paper with an ink column at x = 9d + d % 9; the blank cell (x 90…98) is paper only.
    /// With `minus`, 108 px wide and an ink row across x 99…107 at y 6.
    static func numbers(minus: Bool = false) -> Data {
        BMPBuilder.make(width: minus ? 108 : 99, height: 13) { x, y in
            if x >= 99 { return y == 6 ? ink : (0, 0, 0) }
            let d = x / 9
            return d < 10 && x == 9 * d + d % 9 ? ink : (0, 0, 0)
        }
    }
}
```

- [ ] **Step 2: Write the failing palette tests**

Create `Packages/GreedifyKit/Tests/GreedifyKitTests/SkinControlsTests.swift`:

```swift
import Foundation
import Testing
@testable import GreedifyKit

struct SkinControlPaletteTests {
    typealias S = SkinSheets

    func palette(cbuttons: Data = S.cbuttons()) -> Theme.Controls? {
        SkinControlPalette.make(cbuttons: S.bitmap(cbuttons), shufrep: S.bitmap(S.shufrep()), main: S.bitmap(S.main()))
    }

    @Test func samplesThePlayButton() throws {
        let c = try #require(palette())
        #expect(c.faceTop == S.color(S.faceTop))
        #expect(c.faceBottom == S.color(S.faceBottom))
        #expect(c.highlight == S.color(S.highlight))
        #expect(c.shadow == S.color(S.shadow))
        #expect(c.glyph == S.color(S.glyph))
        #expect(c.pressedFaceTop == S.color(S.pressedTop))
        #expect(c.pressedFaceBottom == S.color(S.pressedBottom))
        #expect(c.pressedGlyph == S.color(S.pressedGlyph))
    }

    @Test func findsTheLitIndicatorAndThePanel() throws {
        let c = try #require(palette())
        #expect(c.on == S.color(S.lit))
        #expect(c.panel == S.color(S.panel))
    }

    @Test func aGlyphThatBarelyShowsFallsBack() throws {
        let c = try #require(palette(cbuttons: S.cbuttons(glyphColor: (0x68, 0x78, 0xA8))))
        #expect(c.glyph == nil)
        #expect(c.faceTop == S.color(S.faceTop))
    }

    /// Review focus 1: a sheet larger than standard is still read at the standard coordinates.
    @Test func largerSheetsStillWork() throws {
        let c = try #require(palette(cbuttons: S.cbuttons(width: 200, height: 50)))
        #expect(c.faceTop == S.color(S.faceTop))
    }

    @Test func aSmallCbuttonsGivesNoControls() {
        #expect(palette(cbuttons: S.cbuttons(width: 100, height: 36)) == nil)
        #expect(SkinControlPalette.make(cbuttons: nil, shufrep: nil, main: S.bitmap(S.main())) == nil)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd Packages/GreedifyKit && swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `cannot find 'SkinControlPalette' in scope`.

- [ ] **Step 4: Add `colors(in:)` to SkinBitmap**

Append inside `struct SkinBitmap` in `SkinBitmap.swift`:

```swift
    /// The pixels of a rectangle, row by row; the parts outside the bitmap are skipped.
    func colors(in r: SkinControlPalette.Rect) -> [ThemeColor] {
        var out: [ThemeColor] = []
        for y in stride(from: max(0, r.y), to: min(height, r.y + r.h), by: 1) {
            for x in stride(from: max(0, r.x), to: min(width, r.x + r.w), by: 1) {
                if let c = color(x: x, y: y) { out.append(c) }
            }
        }
        return out
    }
```

- [ ] **Step 5: Implement the palette**

Create `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinControlPalette.swift`:

```swift
import Foundation

/// A skin's button colours, sampled from its sprites (skinned controls spec §3.2).
enum SkinControlPalette {
    struct Rect { let x, y, w, h: Int }
    static let play = Rect(x: 23, y: 0, w: 23, h: 18)
    static let playPressed = Rect(x: 23, y: 18, w: 23, h: 18)
    static let shuffleOn = Rect(x: 28, y: 30, w: 47, h: 15)
    static let controlArea = Rect(x: 0, y: 88, w: 275, h: 28)
    static let minGlyphContrast = 3.0

    static func make(cbuttons: SkinBitmap?, shufrep: SkinBitmap?, main: SkinBitmap?) -> Theme.Controls? {
        var c = Theme.Controls()
        if let cb = cbuttons, cb.width >= 136, cb.height >= 36 {
            if let n = button(cb, play) {
                c.faceTop = n.faceTop; c.faceBottom = n.faceBottom; c.highlight = n.highlight; c.shadow = n.shadow; c.glyph = n.glyph
            }
            if let p = button(cb, playPressed) {
                c.pressedFaceTop = p.faceTop; c.pressedFaceBottom = p.faceBottom; c.pressedGlyph = p.glyph
            }
        }
        if let s = shufrep, s.width >= 92, s.height >= 85 {
            c.on = s.colors(in: shuffleOn).max { chroma($0) < chroma($1) }
        }
        if let m = main, m.width >= 275, m.height >= 116 {
            let a = controlArea
            c.panel = m.dominantColor(in: [(a.x..<(a.x + a.w), a.y..<(a.y + a.h))])
        }
        return c.isUsable ? c : nil
    }

    struct ButtonColors { let faceTop, faceBottom, highlight, shadow: ThemeColor; let glyph: ThemeColor? }
    /// Squared RGB distance from its row's face beyond which a pixel counts as glyph (about 0.08 per channel).
    static let glyphDistance = 0.02

    /// Face from the medians of the rows at 25 % and 75 % (inset 2 px: the glyph is a minority of any row), bevel
    /// from the edges (corners left out), glyph from the pixels clearly unlike their own row's face.
    static func button(_ b: SkinBitmap, _ r: Rect) -> ButtonColors? {
        let inner = Rect(x: r.x + 2, y: r.y + 2, w: r.w - 4, h: r.h - 4)
        guard inner.w > 0, inner.h > 0 else { return nil }
        func row(_ y: Int) -> [ThemeColor] { b.colors(in: Rect(x: inner.x, y: y, w: inner.w, h: 1)) }
        guard let top = median(row(r.y + Int(Double(r.h) * 0.25))),
              let bottom = median(row(r.y + Int(Double(r.h) * 0.75))) else { return nil }
        let highlight = median(b.colors(in: Rect(x: r.x + 1, y: r.y, w: r.w - 2, h: 1))
                               + b.colors(in: Rect(x: r.x, y: r.y + 1, w: 1, h: r.h - 2))) ?? top
        let shadow = median(b.colors(in: Rect(x: r.x + 1, y: r.y + r.h - 1, w: r.w - 2, h: 1))
                            + b.colors(in: Rect(x: r.x + r.w - 1, y: r.y + 1, w: 1, h: r.h - 2))) ?? bottom
        var ink: [ThemeColor] = []
        for y in inner.y..<(inner.y + inner.h) {
            let pixels = row(y)
            guard let face = median(pixels) else { continue }
            ink += pixels.filter { distance($0, face) > glyphDistance }
        }
        var glyph = median(ink)
        if let g = glyph, g.contrast(with: top.blended(toward: bottom, 0.5)) < minGlyphContrast { glyph = nil }
        return ButtonColors(faceTop: top, faceBottom: bottom, highlight: highlight, shadow: shadow, glyph: glyph)
    }

    static func distance(_ p: ThemeColor, _ q: ThemeColor) -> Double {
        (p.r - q.r) * (p.r - q.r) + (p.g - q.g) * (p.g - q.g) + (p.b - q.b) * (p.b - q.b)
    }

    /// Per-channel median: a stray pixel can't tint it the way it would a mean.
    static func median(_ colors: [ThemeColor]) -> ThemeColor? {
        guard !colors.isEmpty else { return nil }
        func mid(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        return ThemeColor(r: mid(colors.map(\.r)), g: mid(colors.map(\.g)), b: mid(colors.map(\.b)))
    }

    /// Saturation × brightness in HSV terms: the lit indicator stands out on either.
    static func chroma(_ c: ThemeColor) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd Packages/GreedifyKit && swift test --filter SkinControlPaletteTests 2>&1 | grep -E "✘|Test run with"`
Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 7: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinBitmap.swift Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinControlPalette.swift Packages/GreedifyKit/Tests/GreedifyKitTests/Support/SkinSheets.swift Packages/GreedifyKit/Tests/GreedifyKitTests/SkinControlsTests.swift
git commit -m "feat(theme): sample a skin's button colours from its sprites" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 4: Import the sprites (SkinSprites, WinampSkin, SkinThemeMapper)

**Files:**
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinSprites.swift`
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/WinampSkin.swift`
- Modify: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinThemeMapper.swift:71-72`
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/SkinControlsTests.swift` (append)

**Interfaces:**
- Consumes: `RGBAImage` (Task 1), `Theme.Controls` / `Theme.Images` (Task 2), `SkinControlPalette.make` (Task 3).
- Produces:
  - `enum SkinSprites` with the constants `grooveWidth = 248`, `handleWidth = 29`, `handleX = 248`, `pressedHandleX = 278`, `barHeight = 10`, `seekStripWidth = 307`, `volumeWidth = 68`, `volumeMinHeight = 418`, `volumeFullHeight = 433`, `digitWidth = 9`, `digitHeight = 13`, `digitsWidth = 99`, `digitsWithMinusWidth = 108`.
  - `static func seekBarPNG(from: Data) -> Data?`, `static func volumePNG(from: Data) -> Data?`, `static func digitsPNG(numbers: Data?, numsEx: Data?) -> Data?`.
  - `WinampSkin.controls: Theme.Controls?` plus `seekBarPNG`, `volumePNG` and `digitsPNG: Data?`.

- [ ] **Step 1: Write the failing tests**

Append to `SkinControlsTests.swift`:

```swift
struct SkinSpritesTests {
    typealias S = SkinSheets
    func decode(_ png: Data?) throws -> RGBAImage { try #require(png.flatMap { ThemeImage.cgImage($0) }.flatMap(RGBAImage.init)) }
    func rgba(_ c: S.RGB) -> UInt32 { UInt32(c.0) << 24 | UInt32(c.1) << 16 | UInt32(c.2) << 8 | 0xFF }

    @Test func seekBarKeepsGrooveAndBothHandles() throws {
        let strip = try decode(SkinSprites.seekBarPNG(from: S.posbar()))
        #expect(strip.width == 307 && strip.height == 10)
        #expect(strip[10, 5] == rgba(S.groove) && strip[250, 5] == rgba(S.handle) && strip[280, 5] == rgba(S.handlePressed))
    }

    @Test func aNarrowPosbarReusesTheHandleAsPressed() throws {
        let strip = try decode(SkinSprites.seekBarPNG(from: S.posbar(width: 280)))
        #expect(strip.width == 307 && strip[280, 5] == rgba(S.handle))
        #expect(SkinSprites.seekBarPNG(from: S.posbar(width: 270)) == nil)
    }

    /// Review focus 4: frames without handles are kept.
    @Test func volumeKeepsItsFramesWithOrWithoutHandles() throws {
        #expect(try decode(SkinSprites.volumePNG(from: S.volume())).height == 433)
        #expect(try decode(SkinSprites.volumePNG(from: S.volume(height: 420))).height == 420)
        #expect(SkinSprites.volumePNG(from: S.volume(height: 400)) == nil)
    }

    @Test func digitsPreferNumsEx() throws {
        #expect(try decode(SkinSprites.digitsPNG(numbers: S.numbers(), numsEx: nil)).width == 99)
        #expect(try decode(SkinSprites.digitsPNG(numbers: S.numbers(), numsEx: S.numbers(minus: true))).width == 108)
        #expect(SkinSprites.digitsPNG(numbers: nil, numsEx: nil) == nil)
    }

    @Test func importCarriesControlsAndImages() throws {
        let files: [String: Data] = [
            "pledit.txt": Data(SkinFixture.classicPledit.utf8), "main.bmp": S.main(), "cbuttons.bmp": S.cbuttons(),
            "shufrep.bmp": S.shufrep(), "posbar.bmp": S.posbar(), "VOLUME.BMP": S.volume(), "nums_ex.bmp": S.numbers(minus: true),
        ]
        let theme = try SkinThemeMapper.theme(fromArchive: SkinFixture.wsz(files), fileName: "t.wsz", installedFonts: [])
        #expect(theme.controls?.isUsable == true)
        #expect(theme.images.seekBar != nil && theme.images.volume != nil && theme.images.digits != nil)
        var missing = files; missing["VOLUME.BMP"] = nil
        let partial = try SkinThemeMapper.theme(fromArchive: SkinFixture.wsz(missing), fileName: "t.wsz", installedFonts: [])
        #expect(partial.images.volume == nil && partial.images.seekBar != nil && partial.controls != nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/GreedifyKit && swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `cannot find 'SkinSprites' in scope`.

- [ ] **Step 3: Implement SkinSprites**

Create `Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/SkinSprites.swift`:

```swift
import Foundation

/// Crops a classic skin's seek bar, volume and digit sheets into the PNGs a theme keeps (skinned controls spec §2, §3.3).
enum SkinSprites {
    static let grooveWidth = 248, handleWidth = 29, handleX = 248, pressedHandleX = 278, barHeight = 10, seekStripWidth = 307
    static let volumeWidth = 68, volumeMinHeight = 418, volumeFullHeight = 433
    static let digitWidth = 9, digitHeight = 13, digitsWidth = 99, digitsWithMinusWidth = 108

    static func decode(_ data: Data?) -> RGBAImage? { data.flatMap { ThemeImage.cgImage($0) }.flatMap(RGBAImage.init) }
    static func png(_ image: RGBAImage) -> Data? { image.cgImage().flatMap(ThemeImage.png) }

    /// A 307×10 strip: groove, handle, pressed handle. A posbar too narrow for the pressed handle reuses the normal one.
    static func seekBarPNG(from data: Data) -> Data? {
        guard let src = decode(data),
              let base = src.crop(x: 0, y: 0, width: handleX + handleWidth, height: barHeight),
              let handle = base.crop(x: handleX, y: 0, width: handleWidth, height: barHeight) else { return nil }
        var strip = RGBAImage(width: seekStripWidth, height: barHeight, fill: 0)
        strip.paste(base, x: 0, y: 0)
        strip.paste(src.crop(x: pressedHandleX, y: 0, width: handleWidth, height: barHeight) ?? handle, x: pressedHandleX, y: 0)
        return png(strip)
    }

    /// The 28 frames, plus the handles when the sheet is tall enough to hold them.
    static func volumePNG(from data: Data) -> Data? {
        guard let src = decode(data), src.height >= volumeMinHeight,
              let sheet = src.crop(x: 0, y: 0, width: volumeWidth, height: min(src.height, volumeFullHeight)) else { return nil }
        return png(sheet)
    }

    /// `nums_ex.bmp` (with a minus) wins over `numbers.bmp`.
    static func digitsPNG(numbers: Data?, numsEx: Data?) -> Data? {
        if let strip = decode(numsEx)?.crop(x: 0, y: 0, width: digitsWithMinusWidth, height: digitHeight) { return png(strip) }
        if let strip = decode(numbers)?.crop(x: 0, y: 0, width: digitsWidth, height: digitHeight) { return png(strip) }
        return nil
    }
}
```

- [ ] **Step 4: Read the sheets in WinampSkin**

In `WinampSkin.swift`, add these fields after `pixelFontPNG`:

```swift
    /// Button colours sampled from `cbuttons.bmp`, `shufrep.bmp` and `main.bmp` (skinned controls spec §3.2).
    public var controls: Theme.Controls?
    /// `posbar.bmp`, `volume.bmp` and the digits, cropped (skinned controls spec §3.3).
    public var seekBarPNG: Data?
    public var volumePNG: Data?
    public var digitsPNG: Data?
```

In `init(archive:)`, replace:

```swift
        let main = read("main.bmp")
        frameColor = main.flatMap(SkinBitmap.init(data:)).flatMap(Self.frameColor(of:))
```

with:

```swift
        let main = read("main.bmp")
        let mainBitmap = main.flatMap(SkinBitmap.init(data:))
        frameColor = mainBitmap.flatMap(Self.frameColor(of:))
        controls = SkinControlPalette.make(cbuttons: read("cbuttons.bmp").flatMap(SkinBitmap.init(data:)),
                                           shufrep: read("shufrep.bmp").flatMap(SkinBitmap.init(data:)), main: mainBitmap)
        seekBarPNG = read("posbar.bmp").flatMap(SkinSprites.seekBarPNG(from:))
        volumePNG = read("volume.bmp").flatMap(SkinSprites.volumePNG(from:))
        digitsPNG = SkinSprites.digitsPNG(numbers: read("numbers.bmp"), numsEx: read("nums_ex.bmp"))
```

Also update the type's doc comment `/// The color sources of a classic Winamp 2 skin (spec §3). Nothing else in the archive is read.` to `/// What Greedify reads from a classic Winamp 2 skin: colours, main.bmp and text.bmp (themes and theme images specs), and the control sprites (skinned controls spec).`

- [ ] **Step 5: Carry them into the theme**

In `SkinThemeMapper.swift`, replace:

```swift
        theme.images = Theme.Images(backdrop: Theme.Images.accept(skin.backdropPNG),
                                    pixelFont: Theme.Images.accept(skin.pixelFontPNG))
```

with:

```swift
        theme.images = Theme.Images(backdrop: Theme.Images.accept(skin.backdropPNG),
                                    pixelFont: Theme.Images.accept(skin.pixelFontPNG),
                                    seekBar: Theme.Images.accept(skin.seekBarPNG),
                                    volume: Theme.Images.accept(skin.volumePNG),
                                    digits: Theme.Images.accept(skin.digitsPNG))
        theme.controls = skin.controls
```

- [ ] **Step 6: Run all tests**

Run: `cd Packages/GreedifyKit && swift test 2>&1 | grep -E "✘|Test run with"`
Expected: all pass. The existing `WinampSkinTests` compare whole `WinampSkin` values; new fields default to nil, so fixtures without the sheets still match. If one fails because its fixture now yields `controls`, add the expected fields to that fixture's expectation rather than weakening the check.

- [ ] **Step 7: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/Winamp/ Packages/GreedifyKit/Tests/GreedifyKitTests/SkinControlsTests.swift
git commit -m "feat(theme): import a skin's control sprites and palette" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 5: SkinControlImages (load-time slicing and smoothing)

**Files:**
- Create: `Packages/GreedifyKit/Sources/GreedifyKit/Theme/SkinControlImages.swift`
- Test: `Packages/GreedifyKit/Tests/GreedifyKitTests/SkinControlsTests.swift` (append)

**Interfaces:**
- Consumes: `RGBAImage` and `PixelScaler.scale4x` (Task 1), `Theme.Images` (Task 2), `SkinSprites` constants (Task 4).
- Produces: `public struct SkinControlImages: Sendable` with:
  - the constants `scale = 4` and `volumeFrameCount = 28`;
  - `groove`, `handle`, `handlePressed: CGImage?`;
  - `volumeFrames: [CGImage]`, holding 28 or none;
  - `volumeHandle`, `volumeHandlePressed: CGImage?`;
  - `digits: [CGImage]`, holding 10 or none;
  - `minus: CGImage?` and `digitInk: ThemeColor?`;
  - `public static let empty` and `public init(_ images: Theme.Images)`;
  - `public static func volumeFrameIndex(for fraction: Double) -> Int`.

- [ ] **Step 1: Write the failing tests**

Append to `SkinControlsTests.swift`:

```swift
struct SkinControlImagesTests {
    typealias S = SkinSheets
    func rgba(_ c: S.RGB) -> UInt32 { UInt32(c.0) << 24 | UInt32(c.1) << 16 | UInt32(c.2) << 8 | 0xFF }
    func images(volumeHeight: Int = 433, minus: Bool = true) -> Theme.Images {
        Theme.Images(seekBar: SkinSprites.seekBarPNG(from: S.posbar()), volume: SkinSprites.volumePNG(from: S.volume(height: volumeHeight)),
                     digits: SkinSprites.digitsPNG(numbers: nil, numsEx: S.numbers(minus: minus)))
    }
    func first(_ image: CGImage?) -> UInt32? { image.flatMap(RGBAImage.init).map { $0[0, 0] } }

    @Test func slicesAndScalesEveryPart() throws {
        let c = SkinControlImages(images())
        #expect(c.groove?.width == 992 && c.groove?.height == 40)
        #expect(c.handle?.width == 116 && c.handlePressed?.height == 40)
        #expect(first(c.groove) == rgba(S.groove) && first(c.handle) == rgba(S.handle) && first(c.handlePressed) == rgba(S.handlePressed))
        #expect(c.volumeFrames.count == 28 && c.volumeFrames.allSatisfy { $0.width == 272 && $0.height == 52 })
        #expect(first(c.volumeFrames[27]) == UInt32(9 * 27) << 24 | 0x40 << 16 | 0x40 << 8 | 0xFF)
        #expect(c.volumeHandle?.width == 56 && c.volumeHandlePressed?.height == 44)
        #expect(c.digits.count == 10 && c.digits.allSatisfy { $0.width == 36 && $0.height == 52 })
        #expect(c.minus != nil)
        #expect(c.digitInk == S.color(S.ink))
    }

    @Test func handlelessVolumeAndMinuslessDigits() {
        let c = SkinControlImages(images(volumeHeight: 420, minus: false))
        #expect(c.volumeFrames.count == 28 && c.volumeHandle == nil && c.volumeHandlePressed == nil)
        #expect(c.digits.count == 10 && c.minus == nil)
    }

    /// Review focus 3: before the images decode (or without them) every part is missing, so views fall back.
    @Test func emptyHasNoParts() {
        for c in [SkinControlImages.empty, SkinControlImages(Theme.Images())] {
            #expect(c.groove == nil && c.handle == nil && c.volumeFrames.isEmpty && c.digits.isEmpty && c.digitInk == nil)
        }
    }

    /// Review focus 2: the ends and anything out of range stay inside the 28 frames.
    @Test func volumeFrameIndexStaysInRange() {
        #expect(SkinControlImages.volumeFrameIndex(for: 0) == 0)
        #expect(SkinControlImages.volumeFrameIndex(for: 1) == 27)
        #expect(SkinControlImages.volumeFrameIndex(for: 0.5) == 14)
        #expect(SkinControlImages.volumeFrameIndex(for: -0.2) == 0)
        #expect(SkinControlImages.volumeFrameIndex(for: 1.3) == 27)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Packages/GreedifyKit && swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `cannot find 'SkinControlImages' in scope`.

- [ ] **Step 3: Implement**

Create `Packages/GreedifyKit/Sources/GreedifyKit/Theme/SkinControlImages.swift`:

```swift
import CoreGraphics
import Foundation

/// A skin's control sprites, sliced from the theme's images and smoothed 4× (skinned controls spec §4–§5).
/// Built off the main actor with the theme's other images; a missing part means "draw that control the plain way".
public struct SkinControlImages: Sendable {
    public static let scale = 4
    public static let volumeFrameCount = 28

    public var groove: CGImage?
    public var handle: CGImage?
    public var handlePressed: CGImage?
    /// All 28 frames, or none.
    public var volumeFrames: [CGImage] = []
    public var volumeHandle: CGImage?
    public var volumeHandlePressed: CGImage?
    /// Digits 0–9, or none.
    public var digits: [CGImage] = []
    public var minus: CGImage?
    /// The digits' lit colour, for what the skin has no sprite for (the colon).
    public var digitInk: ThemeColor?

    public static let empty = SkinControlImages()
    private init() {}

    public init(_ images: Theme.Images) {
        typealias K = SkinSprites
        if let strip = K.decode(images.seekBar) {
            groove = Self.part(strip, 0, 0, K.grooveWidth, K.barHeight)
            handle = Self.part(strip, K.handleX, 0, K.handleWidth, K.barHeight)
            handlePressed = Self.part(strip, K.pressedHandleX, 0, K.handleWidth, K.barHeight)
        }
        if let sheet = K.decode(images.volume) {
            let frames = (0..<Self.volumeFrameCount).compactMap { Self.part(sheet, 0, $0 * 15, K.volumeWidth, 13) }
            volumeFrames = frames.count == Self.volumeFrameCount ? frames : []
            volumeHandlePressed = Self.part(sheet, 0, 422, 14, 11)
            volumeHandle = Self.part(sheet, 15, 422, 14, 11)
        }
        if let strip = K.decode(images.digits) {
            let cells = (0..<10).compactMap { Self.part(strip, $0 * K.digitWidth, 0, K.digitWidth, K.digitHeight) }
            digits = cells.count == 10 ? cells : []
            if strip.width >= K.digitsWithMinusWidth { minus = Self.part(strip, K.digitsWidth, 0, K.digitWidth, K.digitHeight) }
            digitInk = Self.ink(strip)
        }
    }

    /// The frame for a slider position 0…1: the nearest of the 28.
    public static func volumeFrameIndex(for fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * Double(volumeFrameCount - 1)).rounded())
    }

    static func part(_ image: RGBAImage, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGImage? {
        image.crop(x: x, y: y, width: w, height: h).map(PixelScaler.scale4x)?.cgImage()
    }

    /// Digit 8's most common colour other than the blank cell's (the LED background).
    static func ink(_ strip: RGBAImage) -> ThemeColor? {
        guard strip.width >= SkinSprites.digitsWidth, strip.height >= SkinSprites.digitHeight else { return nil }
        let paper = strip[90, 0]
        var counts: [UInt32: Int] = [:]
        for y in 0..<SkinSprites.digitHeight {
            for x in 72..<81 where strip[x, y] != paper { counts[strip[x, y], default: 0] += 1 }
        }
        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return ThemeColor(r8: Int(best >> 24), g8: Int(best >> 16 & 0xFF), b8: Int(best >> 8 & 0xFF))
    }
}
```

- [ ] **Step 4: Run all tests**

Run: `cd Packages/GreedifyKit && swift test 2>&1 | grep -E "✘|Test run with"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/GreedifyKit/Sources/GreedifyKit/Theme/SkinControlImages.swift Packages/GreedifyKit/Tests/GreedifyKitTests/SkinControlsTests.swift
git commit -m "feat(theme): slice and smooth a skin's control sprites at load" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 6: App wiring and the flat bar

**Files:**
- Create: `App/Views/Shared/SkinControls.swift`
- Modify: `App/Views/Shared/ResolvedTheme.swift`
- Modify: `App/Views/Shared/ThemeComponents.swift` (ThemedSurface, delete `ThemedTile`/`themedTile`/`BackdropStrip`)
- Modify: `App/Views/Main/PlayerBar.swift` (remove the three `.themedTile()` calls)

**Interfaces:**
- Consumes: `Theme.Controls` (Task 2), `SkinControlImages` (Task 5).
- Produces:
  - `struct SkinControls: Sendable` (app) with:
    - `faceTop`, `faceBottom`, `highlight`, `shadow`, `pressedFaceTop`, `pressedFaceBottom`, `panel: Color`;
    - `glyph`, `pressedGlyph`, `on: Color?`;
    - `images: SkinControlImages`;
    - `init?(_ c: Theme.Controls?, images: SkinControlImages)`.
  - `ResolvedTheme.controls: SkinControls?` and `ThemeImages.controlImages: SkinControlImages?`.

- [ ] **Step 1: Create SkinControls**

Create `App/Views/Shared/SkinControls.swift`:

```swift
import GreedifyKit
import SwiftUI

/// An imported skin's control colours and smoothed sprites (skinned controls spec §5). Nil on themes without them.
struct SkinControls: Sendable {
    var faceTop, faceBottom, highlight, shadow, pressedFaceTop, pressedFaceBottom, panel: Color
    /// nil: the skin's glyph didn't contrast with its face, so the theme's text colour is used.
    var glyph, pressedGlyph, on: Color?
    var images: SkinControlImages

    init?(_ c: Theme.Controls?, images: SkinControlImages) {
        guard let c, let top = c.faceTop, let bottom = c.faceBottom, let panel = c.panel else { return nil }
        faceTop = Color(top); faceBottom = Color(bottom); self.panel = Color(panel)
        highlight = Color(c.highlight ?? top.lifted(0.25, lighter: true))
        shadow = Color(c.shadow ?? bottom.lifted(0.25, lighter: false))
        pressedFaceTop = Color(c.pressedFaceTop ?? bottom)
        pressedFaceBottom = Color(c.pressedFaceBottom ?? top)
        glyph = c.glyph.map { Color($0) }
        pressedGlyph = (c.pressedGlyph ?? c.glyph).map { Color($0) }
        on = c.on.map { Color($0) }
        self.images = images
    }
}
```

- [ ] **Step 2: Resolve it**

In `ResolvedTheme.swift`:

After `var plan: BackdropPlan?`, add:

```swift
    /// The skin's control colours and sprites (skinned controls spec §5); nil for themes without them. The colours
    /// apply at once; the sprites arrive with `ThemeImages`, and until then each control draws the plain way.
    var controls: SkinControls?
```

At the end of `init(_:images:)` (after the `if let images, !entry.isSystem { … }` block), add:

```swift
        if !entry.isSystem { controls = SkinControls(t.controls, images: images?.controlImages ?? .empty) }
```

In `struct ThemeImages`, add a field and build it in `init(_ theme:)`:

```swift
    var controlImages: SkinControlImages?
```

```swift
        if theme.controls != nil { controlImages = SkinControlImages(theme.images) }
```

- [ ] **Step 3: The flat bar**

In `ThemeComponents.swift`, replace `backdropOrFill` with:

```swift
    /// The bar is the skin's panel colour when it has skin controls, else the plain surface; the art never tiles there.
    @ViewBuilder private var backdropOrFill: some View {
        if kind == .bar { theme.controls?.panel ?? theme.surface } else { fill }
    }
```

Delete the whole `// MARK: Skinned player bar` section: the `themedTile()` extension, `ThemedTile`, and `BackdropStrip`. Keep `PixelText` below it.

In `App/Views/Main/PlayerBar.swift`, delete the three `.themedTile()` lines. The third reads `.themedTile() // after the frame, so the tile's padding never eats the 250 pt minimum`; delete the whole line.

- [ ] **Step 4: Build**

Run: `xcodegen generate >/dev/null && xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`. If `grep -rn "themedTile\|BackdropStrip" App` finds anything, remove it.

- [ ] **Step 5: Commit**

```bash
git add App/Views/Shared/SkinControls.swift App/Views/Shared/ResolvedTheme.swift App/Views/Shared/ThemeComponents.swift App/Views/Main/PlayerBar.swift
git commit -m "feat(theme): resolve skin controls; the player bar is a flat panel, never tiled" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 7: Vector skin buttons

**Files:**
- Modify: `App/Views/Shared/SkinControls.swift` (append)
- Modify: `App/Views/Shared/ThemeComponents.swift` (`BevelEdges` colours)
- Modify: `App/Views/Shared/Shared.swift` (`TransportControls`, `LikeButton`)
- Modify: `App/Views/Main/PlayerBar.swift`

**Interfaces:**
- Consumes: `ResolvedTheme.controls` (Task 6).
- Produces:
  - `enum SkinControlSize { case play, button, largePlay, largeButton }`;
  - `struct SkinButtonFace: View` (controls, pressed);
  - `struct SkinButtonStyle: ButtonStyle`;
  - `extension View { func skinnedControl(_ size: SkinControlSize, active: Bool = false) -> some View }`;
  - `LikeButton(track:skinned:)`;
  - `BevelEdges(pressed:width:light:dark:)`.

- [ ] **Step 1: Let BevelEdges take colours**

In `ThemeComponents.swift`, change `BevelEdges` to:

```swift
/// Winamp-style 3D edge: light top-left, dark bottom-right, swapped while pressed.
struct BevelEdges: View {
    let pressed: Bool
    let width: CGFloat
    var light: Color = .white.opacity(0.55)
    var dark: Color = .black.opacity(0.55)

    var body: some View {
        Canvas { context, size in
            var topLeft = Path()
            topLeft.move(to: CGPoint(x: 0, y: size.height))
            topLeft.addLine(to: .zero)
            topLeft.addLine(to: CGPoint(x: size.width, y: 0))
            var bottomRight = Path()
            bottomRight.move(to: CGPoint(x: size.width, y: 0))
            bottomRight.addLine(to: CGPoint(x: size.width, y: size.height))
            bottomRight.addLine(to: CGPoint(x: 0, y: size.height))
            // Strokes are centred on the edge and the canvas clips the outer half, so 2× width shows `width`.
            context.stroke(topLeft, with: .color(pressed ? dark : light), lineWidth: width * 2)
            context.stroke(bottomRight, with: .color(pressed ? light : dark), lineWidth: width * 2)
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: The button style**

Append to `App/Views/Shared/SkinControls.swift`:

```swift
/// Button sizes in points (skinned controls spec §5.3); the popover uses the large ones.
enum SkinControlSize {
    case play, button, largePlay, largeButton

    var size: CGSize {
        switch self {
        case .play: CGSize(width: 44, height: 32)
        case .button: CGSize(width: 32, height: 24)
        case .largePlay: CGSize(width: 56, height: 40)
        case .largeButton: CGSize(width: 40, height: 30)
        }
    }

    var glyphSize: CGFloat {
        switch self {
        case .play: 14
        case .button: 12
        case .largePlay: 18
        case .largeButton: 15
        }
    }
}

/// A skin button's face: the skin's gradient and 1 pt bevel, the bevel inverted while pressed.
struct SkinButtonFace: View {
    let controls: SkinControls
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        shape
            .fill(LinearGradient(colors: pressed ? [controls.pressedFaceTop, controls.pressedFaceBottom] : [controls.faceTop, controls.faceBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { BevelEdges(pressed: pressed, width: 1, light: controls.highlight, dark: controls.shadow) }
            .clipShape(shape)
    }
}

/// A vector button dressed in the skin: its face, bevel and glyph colours; `active` (shuffle on, lyrics shown…)
/// tints the glyph with the skin's lit colour.
struct SkinButtonStyle: ButtonStyle {
    let controls: SkinControls
    let size: SkinControlSize
    let active: Bool
    let fallbackGlyph: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let normal = (pressed ? controls.pressedGlyph : controls.glyph) ?? fallbackGlyph
        configuration.label
            .font(.system(size: size.glyphSize, weight: .semibold))
            .foregroundStyle(active ? controls.on ?? normal : normal)
            .frame(width: size.size.width, height: size.size.height)
            .background(SkinButtonFace(controls: controls, pressed: pressed))
            .contentShape(Rectangle())
    }
}

extension View {
    /// With skin controls, the button becomes a vector skin button; otherwise the view is left as it is.
    func skinnedControl(_ size: SkinControlSize, active: Bool = false) -> some View {
        modifier(SkinnedControl(size: size, active: active))
    }
}

private struct SkinnedControl: ViewModifier {
    @Environment(\.theme) private var theme
    let size: SkinControlSize
    let active: Bool

    func body(content: Content) -> some View {
        if let controls = theme.controls {
            content.buttonStyle(SkinButtonStyle(controls: controls, size: size, active: active, fallbackGlyph: theme.text))
        } else {
            content
        }
    }
}
```

- [ ] **Step 3: Transport controls**

In `Shared.swift`, replace the body of `TransportControls` with:

```swift
    var body: some View {
        let player = model.player
        HStack(spacing: large ? 40 : 22) {
            Button { Task { await player.previous() } } label: { Image(systemName: "backward.fill") }
                .help("Previous")
                .skinnedControl(large ? .largeButton : .button)
            Button { Task { await player.togglePlayPause() } } label: { playLabel(player.isPlaying) }
                .help(player.isPlaying ? "Pause" : "Play")
                .skinnedControl(large ? .largePlay : .play)
            Button { Task { await player.next() } } label: { Image(systemName: "forward.fill") }
                .help("Next")
                .skinnedControl(large ? .largeButton : .button)
        }
        .font(.system(size: large ? 22 : 15))
        .buttonStyle(.plain)
        .disabled(model.isOffline)
    }

    /// A skin button draws its own face, so the label is just the glyph; otherwise the filled round (or bevel square) button.
    @ViewBuilder func playLabel(_ playing: Bool) -> some View {
        if theme.controls != nil {
            Image(systemName: playing ? "pause.fill" : "play.fill")
        } else {
            // Explicit colours: `.fill(.primary)` next to `.foregroundStyle(...)` resolved to the
            // same colour as the icon, making the button invisible.
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: large ? 20 : 14))
                .foregroundStyle(theme.isSystem ? Color(nsColor: .windowBackgroundColor) : theme.background)
                .frame(width: large ? 48 : 34, height: large ? 48 : 34)
                .background(playShape.fill(theme.isSystem ? Color(nsColor: .labelColor) : theme.text))
                .overlay { if theme.buttonStyle == .bevel && !theme.isSystem { BevelEdges(pressed: false, width: 1) } }
                .clipShape(playShape)
        }
    }
```

- [ ] **Step 4: LikeButton**

In `Shared.swift`, replace `LikeButton`'s properties and body with:

```swift
    let track: Track
    /// In the player bar the like button is a skin button; in song rows it stays a plain heart.
    var skinned = false

    var body: some View {
        let liked = model.library.isLiked(track)
        let button = Button { Task { await model.library.toggleLike(track) } } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
        }
        .foregroundStyle(liked ? theme.accent : theme.textSecondary)
        .help(liked ? "Remove from Liked Songs" : "Save to Liked Songs")
        // A button style set on the button itself outranks one set outside it, so `.plain` only when not skinned.
        if skinned, theme.controls != nil { button.skinnedControl(.button, active: liked) } else { button.buttonStyle(.plain) }
    }
```

- [ ] **Step 5: Player bar buttons**

In `PlayerBar.swift`:
- `if let track = player.track { LikeButton(track: track) }` → `if let track = player.track { LikeButton(track: track, skinned: true) }`
- the shuffle button: add `.skinnedControl(.button, active: player.state?.shuffleState == true)` after `.help("Shuffle")`
- the repeat button: add `.skinnedControl(.button, active: (player.state?.repeatState ?? .off) != .off)` after `.help("Repeat")`
- the lyrics button: add `.skinnedControl(.button, active: model.showLyrics)` after `.help("Lyrics")`
- the queue button: insert `.skinnedControl(.button)` after `.themed(.secondary).help("Queue")` and before `.popover(isPresented: $showQueue)`
- the settings button: add `.skinnedControl(.button)` after `.themed(.secondary).help("Settings")`

- [ ] **Step 6: Build**

Run: `xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add App/Views/Shared/SkinControls.swift App/Views/Shared/ThemeComponents.swift App/Views/Shared/Shared.swift App/Views/Main/PlayerBar.swift
git commit -m "feat(theme): vector player buttons in the skin's colours" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 8: Skinned seek bar, volume and digits

**Files:**
- Modify: `App/Views/Shared/ThemeComponents.swift` (`ThemedSlider`)
- Modify: `App/Views/Shared/SkinControls.swift` (append `SkinDigits`)
- Modify: `App/Views/Shared/Shared.swift` (`ProgressBar`)
- Modify: `App/Views/Main/PlayerBar.swift` (volume slider)

**Interfaces:**
- Consumes: `SkinControls`, `SkinButtonFace` (Tasks 6–7), `SkinControlImages.volumeFrameIndex` and `.scale` (Task 5).
- Produces: `enum SliderSkin { case plain, seek, volume }`, `ThemedSlider(value:range:skin:onEditingChanged:)`, and `struct SkinDigits: View` (text, images, ink, height).

- [ ] **Step 1: Slider skins**

In `ThemeComponents.swift`, replace the whole `ThemedSlider` with:

```swift
enum SliderSkin { case plain, seek, volume }

/// A slider drawn from the theme; System keeps the native mini `Slider`. With skin controls, `.seek` draws the
/// skin's groove and handle and `.volume` its fill frames (skinned controls spec §5.4–§5.5).
struct ThemedSlider: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    var skin: SliderSkin = .plain
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false

    static let seekHeight: CGFloat = 20
    static let seekHandle = CGSize(width: 58, height: 20)
    static let volumeHeight: CGFloat = 16
    static let volumeHandle = CGSize(width: 17, height: 14)

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
    }

    var body: some View {
        if theme.isSystem {
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged).controlSize(.mini)
        } else if skin == .seek, let c = theme.controls, let groove = c.images.groove {
            skinned(c, height: Self.seekHeight, handleSize: Self.seekHandle, handle: c.images.handle, pressed: c.images.handlePressed) {
                // The 4× image drawn at 2 points per source pixel; the groove's 4 px ends keep their shape.
                Image(decorative: groove, scale: CGFloat(SkinControlImages.scale) / 2)
                    .resizable(capInsets: EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .interpolation(.high)
            }
        } else if skin == .volume, let c = theme.controls, c.images.volumeFrames.count == SkinControlImages.volumeFrameCount {
            let frame = c.images.volumeFrames[SkinControlImages.volumeFrameIndex(for: fraction)]
            skinned(c, height: Self.volumeHeight, handleSize: Self.volumeHandle, handle: c.images.volumeHandle,
                    pressed: c.images.volumeHandlePressed) {
                Image(decorative: frame, scale: 1).resizable().interpolation(.high)
            }
        } else {
            plain
        }
    }

    /// Track, handle (the skin's, or a small vector knob when it has none) and drag, all in the handle's width.
    private func skinned<Track: View>(_ c: SkinControls, height: CGFloat, handleSize: CGSize, handle: CGImage?, pressed: CGImage?,
                                      @ViewBuilder track: () -> Track) -> some View {
        let trackView = track()
        return GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let x = CGFloat(fraction) * max(0, geo.size.width - handleSize.width)
            ZStack(alignment: .leading) {
                trackView.frame(width: geo.size.width, height: height)
                Group {
                    if let image = (dragging ? pressed : nil) ?? handle {
                        Image(decorative: image, scale: 1).resizable().interpolation(.high)
                    } else {
                        SkinButtonFace(controls: c, pressed: dragging)
                    }
                }
                .frame(width: handleSize.width, height: handleSize.height)
                .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let f = min(max((drag.location.x - handleSize.width / 2) / max(1, geo.size.width - handleSize.width), 0), 1)
                        value = range.lowerBound + Double(f) * span
                    }
                    .onEnded { _ in dragging = false; onEditingChanged(false) }
            )
        }
        .frame(height: height)
    }

    private var plain: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let knob: CGFloat = 10
            let x = CGFloat(fraction) * max(0, geo.size.width - knob)
            let bevel = theme.buttonStyle == .bevel
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: bevel ? 0 : 2).fill(theme.divider).frame(height: 4)
                RoundedRectangle(cornerRadius: bevel ? 0 : 2).fill(theme.accent).frame(width: x + knob / 2, height: 4)
                Group {
                    if bevel {
                        Rectangle().fill(theme.raised).overlay(BevelEdges(pressed: dragging, width: 1)).frame(width: knob, height: 12)
                    } else {
                        Circle().fill(theme.text).frame(width: knob, height: knob)
                    }
                }
                .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let f = min(max((drag.location.x - knob / 2) / max(1, geo.size.width - knob), 0), 1)
                        value = range.lowerBound + Double(f) * span
                    }
                    .onEnded { _ in dragging = false; onEditingChanged(false) }
            )
        }
        .frame(height: 14)
    }
}
```

- [ ] **Step 2: SkinDigits**

Append to `App/Views/Shared/SkinControls.swift`:

```swift
/// A time in the skin's digit sprites (skinned controls spec §5.6). The colon, which skins have no sprite for,
/// is two squares in the digits' ink. Every character has a fixed width, so the layout never jumps.
struct SkinDigits: View {
    let text: String
    let images: SkinControlImages
    let ink: Color
    var height: CGFloat = 13

    var body: some View {
        let unit = height / 13
        HStack(spacing: unit) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                if let d = character.wholeNumberValue, images.digits.indices.contains(d) {
                    Image(decorative: images.digits[d], scale: 1).resizable().interpolation(.high).frame(width: 9 * unit, height: height)
                } else if character == "-", let minus = images.minus {
                    Image(decorative: minus, scale: 1).resizable().interpolation(.high).frame(width: 9 * unit, height: height)
                } else {
                    Canvas { context, _ in
                        for y in [4.0, 8.0] {
                            context.fill(Path(CGRect(x: unit, y: y * unit, width: 1.5 * unit, height: 1.5 * unit)), with: .color(ink))
                        }
                    }
                    .frame(width: 3.5 * unit, height: height)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
```

- [ ] **Step 3: ProgressBar**

In `Shared.swift`, in `ProgressBar.body`, replace the `HStack(spacing: 8) { … }` with:

```swift
            HStack(spacing: 8) {
                time(Int(pos))
                ThemedSlider(value: Binding(get: { pos }, set: { dragMs = $0 }), range: 0...max(1, duration), skin: .seek) { editing in
                    if !editing, let ms = dragMs {
                        Task { await player.seek(toMs: Int(ms)); dragMs = nil }
                    }
                }
                time(Int(duration))
            }
```

and add to `ProgressBar`:

```swift
    /// The skin's digits when it has them, else monospaced text.
    @ViewBuilder func time(_ ms: Int) -> some View {
        if let c = theme.controls, c.images.digits.count == 10 {
            SkinDigits(text: formatTime(ms), images: c.images, ink: c.images.digitInk.map { Color($0) } ?? theme.text)
        } else {
            Text(formatTime(ms)).monospacedDigit()
        }
    }
```

- [ ] **Step 4: Volume slider**

In `PlayerBar.swift`, change:

```swift
                ThemedSlider(value: $volume, range: 0...100) { editing in
```

to:

```swift
                ThemedSlider(value: $volume, range: 0...100, skin: .volume) { editing in
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add App/Views/Shared/ThemeComponents.swift App/Views/Shared/SkinControls.swift App/Views/Shared/Shared.swift App/Views/Main/PlayerBar.swift
git commit -m "feat(theme): the skin's seek bar, volume ramp and digits" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```

---

### Task 9: Real run, memory, docs

**Files:**
- Modify: `CLAUDE.md` (the "Themes" bullet under "Changes since the plan")
- Modify: `docs/superpowers/specs/2026-09-30-skinned-controls-design.md` (the `Status:` line)
- Modify: `docs/verification.md` (append a section)

- [ ] **Step 1: Full test run**

Run: `cd Packages/GreedifyKit && swift test 2>&1 | grep -E "✘|Test run with"`
Expected: all pass.

- [ ] **Step 2: Memory before installing**

Run: `scripts/measure-memory.sh`. Record Greedify's footprint with the window open and the currently selected skin.

- [ ] **Step 3: Install**

Check `osascript -e 'tell application "Greedify" to player state as string'`. If it says `playing`, ask the user before installing. Then run `scripts/install.sh`.

- [ ] **Step 4: The user re-imports the three skins**

Ask the user to re-import `~/Downloads/base-2.91.wsz`, `~/Downloads/Winamp5_Classified_v5.5.wsz` and `~/Downloads/diablo_ii.wsz` in Settings → Themes. Old imports have no `controls` data. Then check each new theme file has the new keys:

```bash
for f in ~/Library/Application\ Support/Greedify/Themes/*.greedifytheme; do printf "%s: " "$(basename "$f")"; python3 -c "import json,sys; t=json.load(open(sys.argv[1])); print('controls' in t, sorted(t.get('images',{}).keys()))" "$f"; done
```

Expected: the re-imported files print `True` and include `digits`, `seekBar` and `volume`.

- [ ] **Step 5: Switch live, resize, zoom**

Run:

```bash
defaults write com.alperen.greedify debugHooks -bool YES
```

Restart Greedify (`pkill -x Greedify; open /Applications/Greedify.app`). Then, for each re-imported theme, post the theme, resize and zoom hooks. The theme id is the file name from Step 4's listing; the one below is only an example:

```bash
post(){ swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(.init(\"com.alperen.greedify.debug.$1\"), object: ${2:-nil}, userInfo: nil, deliverImmediately: true)"; }
post showMain; post theme '"base-2.91 3.greedifytheme"'; sleep 2; post resize '"900x600"'; sleep 1; post zoom; sleep 2; post zoom
```

Expected: `pgrep -x Greedify` still prints a pid after every theme, meaning no crash. Afterwards run:

```bash
defaults delete com.alperen.greedify debugHooks
```

- [ ] **Step 6: The user judges the look**

No screenshots can be taken from the session. Ask the user to check, for each skin, in the player bar and the popover:
- the bar is a flat panel with no tiled Winamp window;
- the buttons are the skin's colours, and pressing one inverts its bevel;
- shuffle, repeat and lyrics light up in the skin's lit colour;
- the seek bar is the skin's groove and handle;
- the volume shows the skin's ramp;
- the times use the skin's digits, including `1:02:03` on a long podcast or mix.

- [ ] **Step 7: Memory after**

Run: `scripts/measure-memory.sh` with a re-imported skin selected and the window open. Expected: within a few MB (under 5 MB) of Step 2.

- [ ] **Step 8: Docs**

In `CLAUDE.md`, in the **Themes** bullet under "Changes since the plan", replace `and `FontMatcher` near-matches the pledit.txt font.` with:

```
`FontMatcher` near-matches the pledit.txt font. Skins also style the player's controls: `SkinControlPalette` samples button colours from cbuttons/shufrep/main (`Theme.Controls`), `SkinSprites` keeps the posbar, volume and digit sheets, and `SkinControlImages` smooths them 4× with Scale2x (`PixelScaler`) off the main actor; the app draws vector `SkinButtonStyle` buttons (`.skinnedControl`), skinned `ThemedSlider`s and `SkinDigits`. The bar is a flat panel; main.bmp is never tiled. Spec: `docs/superpowers/specs/2026-09-30-skinned-controls-design.md`.
```

In the spec, change `Status: approved design, not implemented` to `Status: implemented`.

Append to `docs/verification.md` a section `## Skinned player controls (2026-09-30)` with:
- the test count;
- the memory before and after (Steps 2 and 7);
- the crash check result (Step 5);
- the user's verdict per skin (Step 6).

- [ ] **Step 9: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-09-30-skinned-controls-design.md docs/verification.md
git commit -m "docs: skinned player controls — implemented and verified" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JQEWQtyd6dpy5PsWventYZ"
```
