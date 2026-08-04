# Magic Mouse Toolkit UI/design considerations

> **[SUPERSEDED] This document is an early-stage exploration as of 2026-07-02 and does not apply to the current implementation.**
> Directions such as "undecorated, plain macOS standard look," "480×520pt," and
> "explore with Stitch" were all dropped following the Liquid Glass direction
> finalized on 2026-07-06. **The current source of truth is [DESIGN.md](./DESIGN.md)
> and `Sources/DesignSystem.swift`.** The following is kept only as a historical record.

Written 2026-07-02. Fleshes out the "Settings UI" requirements from
[SPEC.md](./SPEC.md). The implementation will be SwiftUI (integrated with
AppKit), and since the plan was to explore the design in Stitch, this also
serves to organize the premises to hand off to the Stitch-side work (DESIGN.md).

## Design direction

- Aim for **the plain look of native macOS SwiftUI components**, not a
  "polished custom design"
- Avoid custom skinning such as colors, corner radii, or shadows in general.
  Rely on the standard styling of native components like `Toggle`, `Slider`,
  `Stepper`, `Form`, and `Section`
- Reference: the undecorated, functional layouts common in the System
  Settings app itself (which this session has been operating in throughout)
  and in the settings screens of menu-bar-resident utilities such as
  Rectangle and AltTab
- Automatically follow dark mode/light mode (use system colors such as
  `Color(.labelColor)`, with no custom color palette)

## Screen layout

### 1. Menu bar dropdown (when clicking the resident icon)

A simple `NSMenu` (a native AppKit menu, not SwiftUI, following MouseToucher/MiddleClick):

```
✓ Enabled
────────────
Open Settings…
────────────
Version 1.0
About This App…
────────────
Quit                    ⌘Q
```

### 2. Settings window

A single window divided into sections (no tabs; laid out vertically with
`Form` + `Section`, close to the look of a single pane in macOS System
Settings). Window size is roughly 480×520pt, non-resizable (typical for a
utility app's settings screen).

```
┌─────────────────────────────────┐
│  Magic Mouse Toolkit Settings          │
├─────────────────────────────────┤
│  ○ Enable                  [Toggle]│
│                                   │
│  ── Gestures ──────────────────  │
│  One-finger tap = left/right click [Toggle]│
│  Two-finger tap = left click    [Toggle]│
│  Two-finger click = middle click[Toggle]│
│                                   │
│  ── Detection range ───────────  │
│  Horizontal [====●────●====] 0-100%│
│  Vertical   [========●==●==] 0-100%│
│  (higher value = further forward) │
│                                   │
│  ── Sensitivity ────────────────  │
│  Tap detection time  [Slider] 0.16s│
│  Movement tolerance  [Slider]      │
│  Scroll-misfire guard [Slider]      │
│                                   │
│  ── Debug ──────────────────────  │
│  ▸ Live tap coordinate display (collapsible) │
│                                   │
└─────────────────────────────────┘
```

## Component mapping (native SwiftUI)

| Element | SwiftUI component | Notes |
|---|---|---|
| Enable/disable, each gesture on/off | `Toggle` (`.toggleStyle(.switch)`) | The system-standard switch style. No decoration |
| Sensitivity parameters | `Slider` + value label | The standard `Slider(value:in:) { Text(...) }` form. The numeric value is shown only as a `Text` next to the Slider |
| Detection range (X/Y each min-max) | Two `Slider`s in tandem, or a custom-built `RangeSlider` equivalent | SwiftUI has no built-in "range slider," so placing a min Slider and a max Slider side by side is the simplest and keeps the native feel intact (consistent with the policy of not building an elaborate custom track UI) |
| Section dividers | `Form` + `Section(header:)` | The very structure of the macOS standard settings screen |
| Debug coordinate display | `DisclosureGroup` + `Text` (monospaced font) | Made collapsible so it stays out of view during normal use |
| Overall window | Wrap a `Form` in an `NSHostingController` and host it in a regular `NSWindow` | The standard pattern for opening a window from a menu bar app |

## Notes on building this "in Stitch"

Stitch excels at producing web/HTML-style mockups, so exporting it directly
tends to produce an "app-like but not macOS-native" look — card shadows,
gradients, custom rounded toggles, and so on. **This needs care given this
project's requirement (looking exactly like native SwiftUI)**:

- When building in Stitch, don't use the `taste-design` skill (which aims for
  a premium, non-generic UI), since it runs counter to this project's
  direction of avoiding decoration
- Instead, explicitly specify in the Stitch prompt something like: "macOS
  native System Settings look, SF Pro font, native macOS switch toggles, no
  shadows, no gradients, no rounded cards, flat grouped list style like macOS
  Preferences"
- Treat Stitch's output (HTML/CSS) purely as **a reference for layout and
  information design**; when implementing, replace it with native SwiftUI
  components per the component-mapping table above (don't code up Stitch's
  look as-is)
- When producing `DESIGN.md`, also spell out that colors "follow system
  colors" and that "no corner radii or shadows are used," so there's no
  ambiguity downstream

## Typography and color

- Font: use `Font.system(...)` (San Francisco) as-is. No custom font specified
- Font size: default Control Size inside `Form` (matches the look of the
  macOS settings screens)
- Colors: use only `Color(.controlAccentColor)` (e.g., the color when a
  toggle is on), `Color(.labelColor)`, and `Color(.secondaryLabelColor)`. No
  custom brand color
- Icon: use SF Symbols for the menu bar icon (e.g., `computermouse.fill`,
  following MouseToucher); no custom icon is created

## Open questions

- Whether to do a preview that visualizes the detection range — "overlay the
  current range settings as a rectangle on a Magic-Mouse-shaped figure" (same
  open question as in SPEC.md). Given this session's simple-first direction,
  it may be reasonable to defer this for the initial implementation and rely
  on numeric sliders alone
- Whether the settings window should use `Form` style (iOS-like grouped list)
  or simply stack `VStack`s → `Form` is recommended since it's closer to the
  native macOS "System Settings" look
