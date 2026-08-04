# Magic Mouse Toolkit Implementation Spec (Code-Aligned Edition)

Created: 2026-07-02. The goal is that implementation can be completed by reading only this document (implementer assumed to be Sonnet 5).
For background and history, see SPEC.md / ARCHITECTURE.md; for design tokens, see DESIGN.md.

## 0. Phases

- **Phase 1 (prototype, scope of this document)**: All features + a simple UI (a native-looking Form using DESIGN.md's tokens). Through functional verification and calibration
- **Phase 2**: Reskin to the Liquid Glass design (structured so this only requires swapping token values in DesignSystem.swift and introducing GlassWindow)

## 1. Countermeasures against false tap/scroll triggers — 4-layer defense (the core of this spec)

Estimation from touch coordinates alone (distance/velocity thresholds) inherently leaves boundary misjudgments. So we **use the OS's own scroll determination (the `.scrollWheel` event) as the ground-truth signal**. Since a CGEventTap is always attached for middle-click conversion anyway, adding `.scrollWheel` to the set of monitored events costs almost nothing extra.

A tap is only recognized if it passes **every one of the following layers**:

### Layer 1: Contact geometry (touch-coordinate based, the conventional approach)
- Contact duration ≤ `tapMaxDuration`
- Straight-line distance (start point → end point) ≤ `tapMaxStraightDistance`
- Cumulative path length (sum of per-frame movement) ≤ `tapMaxPathLength`
- Observed peak instantaneous speed (max norm of `MTTouch.normalized.velocity`) ≤ `tapMaxVelocity`
- Contact frame count ≥ `tapMinFrames` (excludes momentary grazes/noise frames. Since Magic Mouse touch frames run at roughly 90Hz, this requires contact of 3 frames ≈ 33ms or more)

### Layer 2: Scroll veto (uses the OS's scroll determination)
- If a `.scrollWheel` event was observed between touch-start and the moment of tap judgment, or within `scrollVetoWindow` (default 0.25s) looking back from the judgment moment, the tap **does not register**
- Recording of scrollWheel is passive (events pass through unmodified). `ScrollMonitor` only retains the last-observed timestamp

### Layer 3: Momentum-scroll veto
- A touch that began while `.scrollWheel`'s `kCGScrollWheelEventMomentumPhase` was began/continued (i.e., during momentum scrolling) has **its entire contact excluded from tap candidacy** (the `beganDuringMomentum` flag is set, guaranteeing non-registration on release)
- Reason: on Magic Mouse, "stopping momentum scroll with a finger" happens routinely in daily use, and this is the single most common pattern behind false clicks

### Layer 4: Physical-button veto
- While a physical button is held down (between leftMouseDown and Up), and within `buttonVetoWindow` (default 0.1s) after buttonUp, taps do not register
- Reason: a finger is also detected as a touch during a physical click, so this prevents a double click formed from "physical click + synthesized tap"

### Known limitations (to be documented in the README)
- If you tap the Magic Mouse while another device such as a trackpad is scrolling, Layer 2 will falsely veto (one click gets ignored). This is a rare two-handed-operation case and the error is fail-safe, so it's accepted
- Since Layer 2 depends on a scroll event actually occurring, the very small movements right before a scroll starts are handled by Layer 1 instead (division of responsibility)

## 2. Project structure

```
MagicMouseToolkit/
├── build.sh
├── Info.plist
├── MagicMouseToolkit.entitlements    (unused. Ad-hoc distribution, no App Sandbox)
├── Sources/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── MultitouchBridge.h       (also consolidates the HID system SPI declarations, due to the single-bridging-header constraint)
│   ├── MultitouchDevice.swift
│   ├── TouchGestureManager.swift
│   ├── TapRecognizer.swift
│   ├── EventInterceptor.swift
│   ├── SynthesizedClick.swift
│   ├── ActionKind.swift         (Codable model for tap assignments; includes RecordedKeyEvent)
│   ├── ActionExecutor.swift     (executes ActionKind; includes reentrancy guard logic for macro playback)
│   ├── MacroRecorder.swift      (three-finger-tap macro recording, listen-only CGEventTap)
│   ├── PointerSpeedManager.swift(tracking-speed boost, IOHIDEventSystemClient SPI)
│   ├── Settings.swift
│   ├── DesignSystem.swift       (implementation of DESIGN.md's tokens)
│   └── SettingsView.swift
└── docs (SPEC.md and other existing docs)
```

## 3. Build and signing

### build.sh
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Magic Mouse Toolkit.app"
BIN="MagicMouseToolkit"
SIGN_ID="${SIGN_ID:-}"              # ad-hoc signing if unspecified

SWIFT_FILES=(Sources/*.swift)
FLAGS=(-import-objc-header Sources/MultitouchBridge.h
       -F /System/Library/PrivateFrameworks -framework MultitouchSupport
       -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit -O)

mkdir -p build
# Phase 2's Liquid Glass (glassEffect) is a macOS 26+ API, so the deployment target is raised
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target arm64-apple-macos26.0  -o build/$BIN-arm64
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target x86_64-apple-macos26.0 -o build/$BIN-x86_64
lipo -create build/$BIN-arm64 build/$BIN-x86_64 -output build/$BIN

rm -rf "build/$APP"
mkdir -p "build/$APP/Contents/MacOS"
cp Info.plist "build/$APP/Contents/"
cp build/$BIN "build/$APP/Contents/MacOS/"
codesign --force --sign "$SIGN_ID" "build/$APP"
echo "Built: build/$APP"
```
- Export the environment variable `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"` at the top of build.sh (per CLAUDE.md defaults)
- Always verify behavior via `open -a "build/Magic Mouse Toolkit.app"` (the launchd parent). Running the binary directly from the terminal bypasses TCC

### Info.plist (required keys)
| Key | Value |
|---|---|
| CFBundleIdentifier | com.mori0818.magicmousetoolkit |
| CFBundleName / CFBundleDisplayName | Magic Mouse Toolkit |
| CFBundleExecutable | MagicMouseToolkit |
| CFBundleVersion / ShortVersionString | 1.0 |
| LSUIElement | true |
| NSHighResolutionCapable | true |

## 4. MultitouchBridge.h (full contents)

```c
#ifndef MultitouchBridge_h
#define MultitouchBridge_h
#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
  int32_t frame;
  double timestamp;
  int32_t identifier;
  int32_t state;          // 4 = Touching
  int32_t fingerId, handId;
  MTVector normalized;    // both position/velocity normalized 0.0-1.0 (larger Y = further forward)
  float size;
  int32_t zero1;
  float angle, majorAxis, minorAxis;
  MTVector absolute;
  int32_t zero2, zero3;
  float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches,
                                         int numTouches, double timestamp, int frame);

CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef);
OSStatus MTDeviceGetFamilyID(MTDeviceRef, int32_t *familyId);

#endif
```
- Touch state constant: only `4 (Touching)` is treated as "in contact." Touches in any other state are not counted toward the per-frame finger count
- The `MTTouch` layout is identical to the one verified on real hardware in the MouseToucher fork. If `position` returns anomalous values (outside the 0-1 range), suspect a layout mismatch and first check the validity of `timestamp` and `identifier` in the logs

## 5. Device management — MultitouchDevice.swift

```swift
final class MultitouchDeviceManager {
    static let shared = MultitouchDeviceManager()
    private var activeDevices: [MTDeviceRef] = []
    func start()    // enumerate → filter → register
    func stop()     // unregister all + MTDeviceStop
    func restart()  // stop() → start() after 0.5s (handles device reconnection)
}
```

- **Filter condition (Magic Mouse only)**: `MTDeviceIsBuiltIn(dev) == false` and `MTDeviceGetFamilyID` succeeds with `familyId == 112 || familyId == 113`
  - 112/113 = the Magic Mouse family. **On first launch, always log the actual familyId** (so that a mismatch on Magic Mouse 2 / USB-C models can be spotted immediately). If the filter yields zero devices, surface "No device passed the familyId filter. Detected familyIds: [...]" in the menu bar status display
  - Fallback setting `deviceFilterStrict` (default true). Setting it to false falls back to the old behavior of using only `!MTDeviceIsBuiltIn` (an escape hatch for units whose familyId doesn't match expectations)
- Callbacks are C function pointers and cannot capture context; forward from a global function to `TouchGestureManager.shared`
- **Reconnection handling**: `NSWorkspace.shared.notificationCenter`'s `didWakeNotification` combined with `IOServiceAddMatchingNotification` (matching on AppleMultitouchDevice) would be complex, so **the prototype simplifies this**: subscribe to didWake notifications, and provide a "Redetect Device" menu-bar item that calls `restart()`. Automatic BT-reconnection detection is deferred to Phase 2

## 6. Settings — Settings.swift

Backed by `UserDefaults.standard`. Every property posts `NotificationCenter.default.post(name: .settingsChanged)` from its `didSet`. Readers (TouchGestureManager / EventInterceptor) copy all values into a local `SettingsSnapshot` struct upon receiving the notification, and hold onto that (UserDefaults is never read inside a callback — for speed and safety).

| Property | UserDefaults key | Type | Default | UI range |
|---|---|---|---|---|
| enabled | mmt.enabled | Bool | true | — |
| oneFingerTapEnabled | mmt.tap1.enabled | Bool | true | — |
| twoFingerTapEnabled | mmt.tap2.enabled | Bool | true | — |
| middleClickEnabled | mmt.middle.enabled | Bool | true | — |
| rightZoneMinX | mmt.zone.rightMinX | Double | 0.6 | 0–1 |
| zoneMinX / zoneMaxX | mmt.zone.minX / maxX | Double | 0.0 / 1.0 | 0–1 |
| zoneMinY / zoneMaxY | mmt.zone.minY / maxY | Double | 0.0 / 1.0 | 0–1 |
| tapMaxDuration | mmt.tap.maxDuration | Double | 0.16 | 0.05–0.5 s |
| tapMaxStraightDistance | mmt.tap.maxStraight | Double | 0.09 | 0.01–0.3 |
| tapMaxPathLength | mmt.tap.maxPath | Double | 0.07 | 0.01–0.3 |
| tapMaxVelocity | mmt.tap.maxVelocity | Double | 1.5 | 0.2–8.0 /s |
| tapMinFrames | mmt.tap.minFrames | Int | 3 | 1–10 |
| scrollVetoWindow | mmt.veto.scroll | Double | 0.25 | 0–1.0 s |
| buttonVetoWindow | mmt.veto.button | Double | 0.10 | 0–0.5 s |
| twoFingerSyncWindow | mmt.tap2.syncWindow | Double | 0.06 | 0.02–0.2 s |
| deviceFilterStrict | mmt.device.strict | Bool | true | — |

- The default of 1.5 for `tapMaxVelocity` is provisional. It's the target for calibration via the debug display (§9)
- Register initial values at launch via `UserDefaults.standard.register(defaults:)`

## 7. Tap recognition — TouchGestureManager.swift + TapRecognizer.swift

### Shared state (read by EventInterceptor)
```swift
struct TouchSharedState {          // protected by os_unfair_lock
    var fingerCount: Int = 0       // number of fingers in state==4 for the current frame
    var lastFrameAt: CFTimeInterval = 0   // time the last touch frame was received (CACurrentMediaTime)
}
```

### Touch frame processing (MT callback, background thread)
1. Reference `SettingsSnapshot`. If `enabled == false`, only update fingerCount and return
2. Update shared state (fingerCount, lastFrameAt)
3. Map each touch by its `identifier` key into `activeTouches: [Int32: TouchTrack]` and update

```swift
struct TouchTrack {
    let id: Int32
    let startTime: Double          // timestamp of the MT frame
    let startPos: MTPoint
    var lastPos: MTPoint
    var pathLength: Float = 0      // Σ|Δpos|
    var maxVelocity: Float = 0     // max ‖normalized.velocity‖
    var frames: Int = 1
    var beganDuringMomentum: Bool  // whether ScrollMonitor.momentumActive was true at start (Layer 3)
    var vetoed: Bool = false       // set true once a Layer-1 threshold violation is confirmed mid-contact (no further updates needed)
}
```

4. For touches present in the frame: update the track. `pathLength += hypot(Δx, Δy)`, `maxVelocity = max(...)`. If a threshold is exceeded, set `vetoed = true`
5. **An identifier present in the previous frame but absent in the current frame = a release**. Judgment happens on release (see next section)
6. If any frame is observed with 3 or more simultaneous fingers, set `vetoed = true` on every track at that point

### Tap judgment on release (TapRecognizer)
```
Registration condition (all AND):
  !track.vetoed
  !track.beganDuringMomentum                          // Layer 3
  duration = releaseTime - startTime ≤ tapMaxDuration
  |endPos - startPos| ≤ tapMaxStraightDistance
  pathLength ≤ tapMaxPathLength
  maxVelocity ≤ tapMaxVelocity
  frames ≥ tapMinFrames
  startPos is within the zone [zoneMinX,zoneMaxX]×[zoneMinY,zoneMaxY]
  ScrollMonitor.lastScrollAt < startTime - scrollVetoWindow   // Layer 2 (before start)
  ScrollMonitor.lastScrollAt < now → no scroll occurred during contact   // Layer 2 (during contact)
  EventInterceptor.buttonDown == false                 // Layer 4
  now - EventInterceptor.lastButtonUpAt > buttonVetoWindow
```
(Layer 2 may be implemented with the simplification: "does not register if `lastScrollAt` was ever updated on or after `startTime - scrollVetoWindow`")

- **One-finger tap**: on registration, synthesize a right click if `endPos.x > rightZoneMinX`, otherwise a left click
- **Two-finger tap**: synthesize a single left click when two tracks satisfy (a) start-time difference ≤ `twoFingerSyncWindow`, (b) both have been released and both meet the registration condition, and (c) release-time difference ≤ `twoFingerSyncWindow * 2`. **Once a two-finger tap registers, do not fire a one-finger tap for the same two tracks** (hold off one-finger judgment for up to `twoFingerSyncWindow*2` until the second release. Implementation: don't fire a released track immediately — queue it in `pendingRelease`, and use delayed judgment where (i) its partner appears → fire the two-finger tap, or (ii) it times out → fire the one-finger tap. Reuse a single `DispatchSourceTimer` for this)
  - Note: this hold-off applies only when two-finger tap is enabled. If `twoFingerTapEnabled == false`, fire the one-finger tap immediately (zero delay)
- Click synthesis is done via `SynthesizedClick.post(button:at:)` (§8). The firing position is the **current cursor position** (the location from `CGEvent(source: nil)`)

## 8. Event tap — EventInterceptor.swift + SynthesizedClick.swift

### One CGEventTap serving three roles
```swift
CGEvent.tapCreate(
  tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: (1 << CGEventType.leftMouseDown.rawValue)
                  | (1 << CGEventType.leftMouseUp.rawValue)
                  | (1 << CGEventType.scrollWheel.rawValue),
  callback: interceptorCallback, userInfo: nil)
```
Callback discipline: **no allocation, no logging, no reading UserDefaults**. Only reading SettingsSnapshot and shared state, plus rewriting integer fields, is allowed.

Branching logic (pseudocode):
```
case .tapDisabledByTimeout, .tapDisabledByUserInput:
    CGEventTapEnable(tap, true); return event            // self-recovery
case .scrollWheel:                                        // acts as ScrollMonitor
    lastScrollAt = now
    phase = event[.scrollWheelEventMomentumPhase]
    momentumActive = (phase == 1 || phase == 2)           // began/continued
    return event                                          // pass through unmodified
case .leftMouseDown:
    if event[.eventSourceUserData] == kMCEventSignature: return event   // pass through our own synthesized events
    buttonDown = true
    if middleClickEnabled
       && shared.fingerCount == 2
       && (now - shared.lastFrameAt) < 0.08 {             // device-correlation guard
        convertingToMiddle = true
        event.type = .otherMouseDown
        event[.mouseEventButtonNumber] = 2                // center
    }
    return event
case .leftMouseUp:
    if event[.eventSourceUserData] == kMCEventSignature: return event
    buttonDown = false; lastButtonUpAt = now
    if convertingToMiddle {                               // if down decided the conversion, up must convert too
        convertingToMiddle = false
        event.type = .otherMouseUp
        event[.mouseEventButtonNumber] = 2
    }
    return event
```
- When `enabled == false` or `middleClickEnabled == false`: since there's no need to keep recording scrollWheel (taps are disabled, or the veto target is disabled), **disable the tap entirely (`CGEventTapEnable(false)`) when master enable is OFF**. When only middleClick is OFF but tapping is enabled, keep the tap alive (needed for Layer 2), but pass Down/Up through unmodified
- If tap creation fails (no permission) → route to AppDelegate's permission flow (§10)

### SynthesizedClick.swift
```swift
enum SynthesizedClick {
    static let signature: Int64 = 0x4D43_4C4B          // "MCLK"
    static func post(button: CGMouseButton) {
        let loc = CGEvent(source: nil)!.location
        let src = CGEventSource(stateID: .hidSystemState)
        src?.userData = signature                       // self-identification (EventInterceptor passes it through)
        let (down, up): (CGEventType, CGEventType) = ...  // left/right/other depending on button
        CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: up,   mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
    }
}
```
- No delay is inserted between down and up (verified fine in MouseToucher testing)
- Note: `CGEventSource.userData` is readable on the event side via the `.eventSourceUserData` field

## 9. UI — SettingsView.swift (prototype version)

Build using only DESIGN.md's tokens (`DesignSystem.swift`). Do not write literal font sizes, colors, or spacing directly into views.

Structure (`Form` + `Section`, window 440×620, not resizable):
1. **General**: master enable toggle
2. **Gestures**: toggles for one-finger tap / two-finger tap / middle click + a slider for the right-click zone's starting X
3. **Active range**: 4 sliders for X min/max and Y min/max (shown as %)
4. **Sensitivity**: 5 sliders for tapMaxDuration / MaxStraight / MaxPath / MaxVelocity / MinFrames (current value shown right-aligned in a monospaced font)
5. **False-trigger countermeasures**: scrollVetoWindow / buttonVetoWindow / twoFingerSyncWindow
6. **Debug** (DisclosureGroup, updates only while open):
   - Current finger count and latest touch coordinates (x, y)
   - **Breakdown of the judgment for the most recent tap attempt**: side-by-side measured values and thresholds for each condition, color-coded to show which layer/condition it failed at (e.g., `path 0.11 > 0.07 ✗`). This is the primary tool for calibrating the velocity threshold
   - Recent events: the last 10 entries of history such as "Tap registered (left)," "Scroll veto," "Momentum veto," etc.
   - Debug data handoff: TouchGestureManager pushes to `DebugFeed.shared` (an ObservableObject, a 10-entry ring buffer) **only while the DisclosureGroup is open** (toggle the `DebugFeed.isActive` flag in the view's onAppear/onDisappear. Overhead while closed is a single flag check)
7. **Reset**: a "Restore sensitivity to defaults" button

Menu bar (NSMenu, AppKit):
```
✓ Enabled                  (toggle, master enable)
──────────
Open Settings…
Redetect Device            (MultitouchDeviceManager.restart)
──────────
About Magic Mouse Toolkit
Quit ⌘Q
```
Icon: SF Symbols `computermouse.fill` (template image). The settings window is created lazily and released on close (`NSWindow.isReleasedWhenClosed` doesn't play well with SwiftUI hosting, so set it to false and release by assigning the reference to nil).

## 10. AppDelegate — launch sequence

1. `UserDefaults.register(defaults:)`
2. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — if not yet authorized, wait for authorization by polling every 2 seconds (**discard the timer once authorized**; this is the only timer)
3. Once authorized: `MultitouchDeviceManager.shared.start()` → `EventInterceptor.shared.start()`
4. Set up the menu bar icon
5. Subscribe to `didWakeNotification` → `MultitouchDeviceManager.restart()`

## 11. Threading and synchronization

| Data | Writer | Reader | Protection |
|---|---|---|---|
| TouchSharedState (fingerCount, lastFrameAt) | MT callback thread | Event tap (main RunLoop) | os_unfair_lock (nanosecond-scale hold time) |
| lastScrollAt / momentumActive / buttonDown / lastButtonUpAt / convertingToMiddle | Event tap | MT callback thread | same as above (may share the same lock) |
| SettingsSnapshot | Main (swapped in on notification receipt) | Both callbacks | whole-struct swap + lock |
| DebugFeed | MT callback → dispatched to main | SwiftUI | emission itself is suppressed via the isActive flag |

## 12. Test checklist (real hardware)

1. Core behavior before glass/window concerns: one-finger tap = left click, right click in the right zone, two-finger tap = left click, two-finger physical click = middle click (verify via e.g. closing a tab in Finder)
2. **False-trigger scenarios** (no click should occur in any of these): slow scroll start / quick flick / back-and-forth scroll / stopping momentum scroll with a finger / tapping while physically clicking / operating a trackpad (should not respond at all)
3. Clicks/scrolling from other mice or trackpads must be completely unaffected
4. Settings changes take effect immediately (no rebuild or restart)
5. Behavior after waking from sleep; behavior of "Redetect Device"
6. Rebuild → re-sign → permissions must not be revoked
7. Idle CPU in the single digits % and memory ≤15MB in Activity Monitor
8. CGEventTap self-recovery: must not stop functioning under high load (verify over extended operation)

## 13. Handoff points for Phase 2

- Visual changes are confined to changing token values in `DesignSystem.swift` plus adding `GlassWindow.swift` (a borderless NSWindow subclass). SettingsView's layout structure is reused as-is
- Liquid Glass verification: validate `.glassEffect()` standalone in a borderless transparent window before integrating

## 14. Three-finger tap = macro recorder / tracking-speed boost (implemented 2026-07-10)

This section records the key points of the already-implemented macro recorder and tracking-speed boost.

### Macro recorder (three-finger tap)
- Added `ActionKind.macro([RecordedKeyEvent])`. `RecordedKeyEvent` is a Codable holding `keyCode/flags/isDown/isFlagsChanged/offset`
- `MacroRecorder` (`ObservableObject`): records keyDown/keyUp/flagsChanged via a dedicated listen-only CGEventTap. Auto-stops at a cap of 200 events/60 seconds. Self-synthesized events (`SynthesizedClick.signature`) are excluded
- `ActionExecutor.perform(.macro)`: replays `CGEvent`s according to `offset` on a dedicated serial queue. A generation counter protected by `os_unfair_lock` ensures that re-triggering during playback immediately cancels the previous playback (prevents duplicate playback)
- The default action for three-finger tap was changed to an empty macro (`.macro([])`). The old default of a Mission Control keystroke was removed
- Settings UI: added recording start/stop, clear, and event-count display to the "Three-finger tap (macro)" section

### Tracking-speed boost
- `PointerSpeedManager`: directly rewrites `HIDMouseAcceleration` (the value behind the System Settings slider, IOFixed 16.16) via the `IOHIDEventSystemClient` SPI (`IOHIDEventSystemClientCreateSimpleClient` / `CopyProperty` / `SetProperty`), applying it immediately. The initial value is captured at launch so it can be restored
- The SPI declarations are consolidated into the existing single bridging header `MultitouchBridge.h` (since `swiftc -import-objc-header` only accepts one)
- Added `AppSettings.pointerSpeedBoost: Double`, reflected in `SettingsSnapshot`
- Settings UI: added a "Cursor Speed Boost" slider

### Build and real-hardware verification
- Ran `./build.sh`; all sources, including the two features above, compile successfully. No errors other than the existing `onChange(of:perform:)` deprecation warning. Confirmed through generation and signing of `build/Magic Mouse Toolkit.app`
- Macro recording/playback and the speed boost have been verified on real hardware
- Virtual trackpad, two-finger scroll, native momentum, and input separation from the built-in trackpad have also been verified on real hardware
- Toggling Accessibility permission mid-run can trigger a known macOS input freeze, so it is excluded from regression testing. See `SAFETY.md` for safety requirements
