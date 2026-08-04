# Magic Mouse Toolkit Design System (DESIGN.md)

Created 2026-07-02 / fully revised 2026-07-28.
**The source of truth is `Sources/DesignSystem.swift`. This document explains its intent and the empirical basis behind it.**
If values disagree, the code is correct. Never write literal values in views — always go through `DS.*` tokens.

The original two-stage plan of "Phase 1 (native) → Phase 2 (Liquid Glass reskin)"
was completed on 2026-07-06. Everything below describes the current (post-Phase-2) implementation.

## Design concept

**"Turn the surface glass of the Magic Mouse 2 (white) directly into the window itself"**

- A standard `.titled` window + a transparent title bar + an empty unified `NSToolbar`. The traffic-light controls and title bar are not custom-built
- `glassEffect(.regular)` is spread across the full window, with a **white plate** placed on top inset 8pt from every edge.
  This 8pt band is what reads as the "glass rim"
- Decoration is limited to what's needed for the physical representation of glass. **No shadows, gradients, or multiple accent colors**
- The white plate is fixed white (`window.appearance = .aqua` locks the appearance to light). Text uses tokens that follow the system appearance

## Token conventions (self-imposed rules)

1. One token per role. **Only one ladder per role** — never create duplicate tokens
   (e.g., top content padding is `contentTop`, one value only. Don't add more per page type)
2. Never use spacing values that fall outside the 4/8 grid (`DS.Space`). The only exception is `DS.Plate`
3. Only `.regular` and `.semibold` font weights (never `.medium`)
4. No shadows. Don't mix corner-radius styles (continuous / circular)
5. Only one accent color, `DS.Color.accent`. **The only place it is explicitly `.tint`ed is `Toggle`**
6. **Layout values are never decided by eye.** Determine them from pixel measurements on @2x captures or from font-metric measurements,
   and leave the basis as a comment on the token

## Token definitions (`Sources/DesignSystem.swift`)

### Colors `DS.Color`

| Token | Value | Usage |
|---|---|---|
| `labelPrimary` | `.primary` | Labels/headings on control rows |
| `labelSecondary` | `.secondary` | Captions, units, numeric values |
| `accent` | `.controlAccentColor` | `Toggle` only (the sole accent) |
| `debugPass` / `debugFail` | systemGreen / systemRed | ✓ / ✗ judgment in the live display |
| `plateBase` | white 0.78 | The white plate's base; edges show a slight translucency |
| `plateCore` | white 0.82 | The white core, inset 26pt from the edge and blurred(18) |
| `cardFill` | rgb(241,241,241) | Live-display cards |

Compositing `plateBase` + `plateCore` yields a center of ≈0.96 (nearly white) and an edge of ≈0.78 (the glass beneath shows through).
A center-anchored `RadialGradient` is **not used** because it produces circular banding on large screens (the fade is instead distance-from-edge based).

### Spacing `DS.Space`

`xs 4 / s 8 / m 12 / l 16 / xl 24 / xxl 32`. Only use this ladder — never create one-off values per use case.

### Plate geometry `DS.Plate` — **do not touch**

| Token | Value | Meaning |
|---|---|---|
| `inset` | 8 | Width of the glass rim (how far the white plate sits inside the edges) |
| `fadeWidth` | 26 | How far the white core is pulled in from the plate edge = the fade band |
| `fadeBlur` | 18 | Edge blur applied to the white core |
| `radius` | 16 | Corner radius of the white plate (**must always use `style: .continuous`**) |

**Principle of concentric corner radii**: the inner corner radius = the outer window's corner radius − the inset.
Since macOS 26's `.titled` window uses a continuous (squircle) curve with a measured curvature range of ≈28pt,
a continuous radius of 16pt against an 8pt inset makes the rim width look uniform (measured 7.5–8.5pt) at both corners and edges.
Using `circular` would make the rim look thin at the corners.

### Corner radius `DS.Radius`

Only `card = 10`. Aside from the plate geometry, this is the only corner radius used anywhere in the app.

### Typography `DS.Font` (5 tokens)

| Token | Definition | Usage |
|---|---|---|
| `pageTitle` | 13 / semibold | Page heading "Advanced Settings," back-button icon |
| `sectionHeader` | 11 / semibold | Section headers, column headings |
| `body` | 13 | Labels on control rows, HUD body text |
| `caption` | 11 | Supplementary captions, card body text |
| `value` | 12 / monospaced | Slider values, measured values in live displays |

The Figma comp's 10pt / 7pt were too small on real hardware, so they were raised to macOS's standard legible sizes (2026-07-10).

### Layout `DS.Layout`

| Token | Value | Basis |
|---|---|---|
| `windowSize` | 700 × 392 | contentSize. The unified title bar adds 66pt on top for a total measured height of 458 |
| `contentLeading` / `contentTrailing` | 32 (`Space.xxl`) | Left/right symmetric. Shortened from 40→32 (2026-07-28 real-hardware feedback) |
| `mainColumnWidth` | 328 | 32 + **328** + 44 + 264 + 32 = 700 |
| `columnGap` | 44 | From the right edge of the left column to the left edge of the card |
| `liveCardSize` | 264 × 340 | Must fit within the plate. No overflow allowed |
| `contentTop` | 8 (`Space.s`) | Distance from the bottom of the title bar (safe area). **Shared across all pages** |
| `formBuiltInInset` | 30 | `Form(.grouped)`'s built-in inset. **@2x measured value** |
| `formInsetCompensation` | `contentLeading − 30` = 2 | Correction to align the left/right edges of the Advanced Settings page with the main screen |
| `rowHeight` | 26 | Fixed height for control rows. Fixed mechanically so wrapping never causes wobble |
| `sliderLabelWidth` | 176 | Longest label, en "2-finger simultaneity window" measured at 175.2pt → rounded up to the next 8-grid step |
| `valueWidth` | 64 | Longest value, en "0.25 sec" measured at 59.3pt → rounded up to the next 8-grid step |

**Height breakdown**: `contentTop 8 + heading 15 + gap 12 + card 340 = 375` + bottom padding 9 + rim 8 = 392.
When tightening the top, also measure the bottom edge, and shrink the height tokens until top and bottom are comparable (top 8 / bottom 9.5pt).

**Left edge of `Form(.formStyle(.grouped))` (macOS 26, 700pt width, @2x measured, 2026-07-28)**

| Element | Left edge |
|---|---|
| Section header text | 30pt |
| Contents of rows within a group card (labels, captions) | 30pt |
| **The group card's background rectangle itself** | **20pt** (10pt further out than the headers/rows) |

The only baseline that can be shared is the 30 that headers and rows have in common. **Only the card background always overflows 10pt outward,
and this cannot be reconciled while keeping Form's structure intact** (reconciling it would require restructuring into a `VStack` with a custom card).
By giving the custom header (back button + page title) `contentLeading`, and giving the Form `formInsetCompensation`,
all text ends up on the same left line (32pt).

## Component conventions

- **Toggle**: `Toggle` + `.toggleStyle(.switch)` + `.controlSize(.small)` + `.tint(DS.Color.accent)`
- **Buttons**: standardize on `.bordered` **only**, and express hierarchy purely through `controlSize`
  (primary = `.regular` / secondary/lower-level settings = `.small`). `.borderedProminent` is not used
- **Slider rows**: share `SliderRow` across every slider. Fixed via `lineLimit(1)` + `frame(height: rowHeight)`.
  **The value column contains only "number + unit"** (qualifiers like "25% from the tip" belong on the row label side).
  Putting variable-length text in a fixed-width value column causes that row alone to wrap, breaking the rhythm of rows across sections
- **Sections**: the Advanced Settings page uses `Form` + `Section(header:)` + `.formStyle(.grouped)` +
  `.scrollContentBackground(.hidden)`. The main screen uses a flat `VStack`
- **Live display**: numeric values always use `DS.Font.value` (monospaced). Judgments are shown as ✓/✗ + `debugPass`/`debugFail`
- No custom-drawn controls are created

## Prohibited

- Literal values specified directly in views (`.padding(13)`, `Color.gray`, `.font(.system(size: 12))`, etc.)
- Third-party fonts or color assets
- Shadows, multiple accent colors, `.borderedProminent`
- Leaving a trailing `Spacer(minLength: 0)` at the end of a fixed-width two-column `HStack`.
  Since `spacing` applies to every adjacent pair, the gap ends up counted twice, and the overflowing `HStack`
  gets center-aligned, making the left/right margins asymmetric. Keep margins symmetric via the outer `padding` instead
- Deciding layout by eye. After implementation, verify actual left/right and top/bottom coordinates numerically via @2x captures

## Localization and layout

The first argument to `NSLocalizedString` **is the Japanese literal itself, used as the key** (shared key across both ja/en `.strings` files, currently 117 entries).
Since changing the wording changes the key, whenever a layout adjustment touches the displayed string,
you must update `Resources/{ja,en}.lproj/Localizable.strings` for both languages at the same time and verify the keys match up (0 missing, 0 unused).

Determine fixed-width column widths only after measuring fonts **across all languages** (don't decide by looking at Japanese alone).
In fact, English labels run longer than Japanese ones, and `sliderLabelWidth` is bottlenecked by English.

## Verification steps

1. `./build.sh` (no Xcode project. SourceKit's "Cannot find ... in scope" is a false positive from per-file independent indexing)
2. `open "build/Magic Mouse Toolkit.app"` → confirm it's running with `pgrep -x MagicMouseToolkit`
3. Take an @2x capture with `screencapture -l <windowID>` (px ÷ 2 = pt) and measure left/right/top/bottom edges and row heights in pixels
4. Cross-check localization keys (the first argument across `Sources/*.swift` vs. both `.strings` files converted with `plutil -convert json`)
