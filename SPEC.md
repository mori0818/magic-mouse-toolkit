# Magic Mouse Toolkit Specification

## Background and purpose

Add the following two custom operations to Magic Mouse:
1. Click (left/right) via tap
2. Middle click via a two-finger operation

Testing with existing commercial/OSS tools (MiddleClick, MouseToucher)
revealed the following issues:

- **MiddleClick**: also responds to the trackpad, so it cannot be restricted
  to Magic Mouse only
- **MouseToucher**: Magic Mouse-specific (already has logic built in to
  exclude the built-in trackpad). However, it had the following operational
  problems:
  - Every adjustment of sensitivity/response range requires rewriting the
    source code and rebuilding
  - With ad-hoc signing, rebuilding changes the code-signing hash (cdhash),
    which can cause macOS to prompt for re-approval of accessibility
    permission. See `SAFETY.md` for the safe procedure of quitting the app
    before changing permissions
  - No middle-click functionality

To solve these, we will integrate the functionality of both tools and
**newly develop our own app whose settings can be changed from the UI
(no rebuild required)**.

## Operating environment

- macOS (Universal Binary supporting both Apple Silicon and Intel)
- Magic Mouse (Bluetooth connection)
- Target devices are external multitouch devices only (the built-in trackpad
  is detected and excluded via `MTDeviceIsBuiltIn`)

## Functional requirements

### 1. One-finger tap → left click / right click

- Lightly tapping the Magic Mouse surface with one finger produces a normal
  left click
- If the X coordinate of the tap position exceeds a (variable) threshold, it
  is treated as a right click (carried over from the existing tool: default
  X > 0.6)
- Conditions for judging a tap:
  - Contact duration is at or below the "maximum tap duration"
  - The amount of finger movement during contact is at or below the
    "movement tolerance"
  - To avoid misidentifying a tap as a scroll operation, the finger's
    cumulative movement distance and instantaneous speed are also used in
    the judgment (see "Scroll misfire prevention" below)

### 2. Two-finger tap → left click

- Tapping with two fingers at nearly the same time is treated as a left
  click
- Applies the same effective range and sensitivity judgment as the
  one-finger tap (initial policy; to be verified)

### 3. Two-finger click (physical press) → middle click

- When the Magic Mouse body is physically pressed down (a normal click
  action) while two fingers are resting on it, that input is **replaced
  with a middle click**
- Implementation approach: monitor system-level physical click events
  (`leftMouseDown`/`leftMouseUp`) with a `CGEventTap`. If the number of
  multitouch contact fingers at the moment the click occurs is two, swallow
  the original left-click event and instead synthesize and dispatch a
  middle-click event (`otherMouseDown`/`otherMouseUp`)
- If there is one finger (normal click) or three or more fingers, the event
  is passed through unchanged

### 4. Effective range (tap response zone) adjustable from the UI

- The Magic Mouse surface is handled in normalized coordinates (0.0–1.0),
  and a click is only registered if the position where the tap **started**
  falls within this rectangular range
- The following can be adjusted from the UI, in percent units (0–100%):
  - X direction: minimum and maximum values (horizontal range)
  - Y direction: minimum and maximum values (vertical range; verified that a
    higher Y value corresponds to the front — the tip end reached by
    extending the finger)
- Changes take effect immediately without restarting the app (saved to
  UserDefaults, and read in real time by the running instance)

### 5. Sensitivity adjustable numerically from the UI

"Sensitivity" is a collective term for several internal parameters. It is
adjusted in the UI via sliders, etc.

| Parameter | Description | Default (reference: final value from MouseToucher testing) |
|---|---|---|
| Maximum tap duration | If contact duration exceeds this, the tap is not registered (seconds) | 0.16 |
| Cursor movement tolerance | Upper limit of cursor movement amount during a tap (screen coordinate system) | 0.045 |
| Finger straight-line movement tolerance | Upper limit of the straight-line distance from the tap start point to the current point (surface normalized coordinates 0–1) | 0.09 |
| Finger cumulative movement distance tolerance | Upper limit of the total path length the finger traveled during a tap (countermeasure for back-and-forth scrolling, surface normalized coordinates 0–1) | 0.07 |
| Instantaneous speed tolerance | Upper limit of the maximum instantaneous speed observed during a tap (surface normalized coordinates/second, countermeasure for flick scrolling) | Needs calibration (measurement was interrupted in the previous session) |

In the UI, these will be individually adjustable via fine-grained sliders
(the idea of consolidating them into a single slider for an "easy mode" is
deferred for now and will be considered further if requested).

### 6. Scroll misfire prevention

To distinguish tap judgment from scroll judgment, the following are used in
combination (knowledge gained from existing MouseToucher testing):

- Straight-line movement distance check (start point → end point)
- Cumulative movement distance check (handles cases where back-and-forth
  scrolling brings the start and end points close together)
- Instantaneous speed check (uses the `velocity` field of MTTouch. A fast
  flick scroll can have a high speed even when the movement distance is
  small, allowing it to slip through the distance-based judgment. This
  detects that case)

### 7. Settings UI

- Menu-bar resident app (no Dock icon, `LSUIElement`)
- Clicking the menu bar icon shows the following menu:
  - Toggle enabled/disabled
  - "Open Settings…" → shows the settings window
  - Launch at login (toggle; or manage as before via the Login Items in
    System Settings)
  - About this app
  - Quit
- Settings window (SwiftUI):
  - Effective range settings: X min/max, Y min/max (percent sliders). If
    possible, consider a preview that overlays the rectangle in real time on
    a graphic of the Magic Mouse for visual confirmation (a simplified
    display is acceptable for the initial implementation)
  - Sensitivity settings: adjust the above 5 parameters via sliders or
    numeric input
  - For debugging: live display of tap coordinates (to assist calibration;
    shows the current X/Y coordinates and whether the most recent tap was
    inside/outside the zone)

## Non-functional requirements

### Stabilizing accessibility permission

- Use a **stable self-signed certificate** for code signing (a self-signed
  certificate with a fixed Common Name, not ad-hoc)
- This ensures that permission (TCC) is not revoked when rebuilding to add
  sensitivity adjustments or new features
- Record the certificate setup procedure in the README/comments (reuse the
  procedure already verified with MouseToucher)

### Permission requests

- Accessibility permission (`AXIsProcessTrustedWithOptions`): required for
  synthesizing clicks from taps, and for the event tap/replacement of
  physical clicks
- If permission is not granted on first launch, display an alert prompting
  the user to open System Settings (carried over from existing MouseToucher)

## Open items / to be discussed

- Whether the effective range for the two-finger tap (left click) is shared
  with the one-finger tap, or configurable separately
- Whether support for three-finger gestures is needed (not included in this
  scope; alternative candidates such as BetterTouchTool have been considered
  separately)
- The specific default value for the instantaneous speed tolerance
  (calibration needed; to be determined by collecting logs on real hardware)
- Feasibility and priority of implementing the range preview overlaid on the
  Magic Mouse shape in the settings window

## Development approach

1. Review and agreement on this specification
2. Implement core logic (multitouch detection, tap/click judgment, settings
   loading)
3. Implement the settings UI (SwiftUI)
4. Implement two-finger physical click → middle click conversion
   (CGEventTap)
5. Calibrate sensitivity and range on real hardware (verify while adjusting
   from the UI, no rebuild required)
6. Consider disabling/uninstalling MiddleClick and MouseToucher
