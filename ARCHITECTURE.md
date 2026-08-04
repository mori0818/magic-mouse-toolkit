# Magic Mouse Toolkit architecture

Magic Mouse Toolkit is a menu bar app that reads Magic Mouse multi-touch input and
converts it into clicks, scrolling, cursor movement, and keyboard macros via CGEvent.

## Runtime

- Swift 6
- macOS 26 SDK
- AppKit + SwiftUI
- Built directly with `swiftc`
- arm64 / x86_64 Universal Binary
- Bundle ID: `com.mori0818.magicmousetoolkit`

## Third-party provenance

See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for detailed copyright
notices and licenses.

### MouseToucher

[MouseToucher](https://github.com/meatpaste/mousetoucher) is MIT licensed.
Magic Mouse Toolkit's early prototype used it as a starting point for the
following areas:

- C bridge declarations for `MultitouchSupport.framework`
- Device enumeration via `MTDeviceCreateList` and `MTDeviceIsBuiltIn`
- The Universal Binary build approach using `swiftc` and `lipo`
- Initial setup for requesting Accessibility permissions
- The initial design of the tap-detection state machine

The current code adds device retain/release, Bluetooth reconnection, IOKit
attach/detach notifications, shared state across callbacks, scroll vetoes,
macros, virtual trackpad mode, and more, and has substantially redesigned the
file structure and implementation. Even so, because the provenance remains
material, MouseToucher's copyright notice and MIT License continue to be
included.

### MiddleClick

[MiddleClick](https://github.com/artginzburg/MiddleClick) is GPL-3.0 licensed.
Its approach of rewriting the type and button number of the same CGEvent and
resending it as a middle click — rather than discarding and reposting the
physical click event — was referenced and adapted here.

Magic Mouse Toolkit is distributed in its entirety under GPL-3.0-only to
preserve compatibility with this provenance.

## Components

### `MultitouchDevice.swift`

- Enumerates devices from MultitouchSupport
- Determines a Magic Mouse's family ID and built-in attribute
- Monitors the built-in trackpad solely to distinguish input sources
- Retains/releases device references
- Handles sleep/wake, Bluetooth reconnection, and IOKit attach/detach notifications

### `TouchGestureManager.swift` / `TapRecognizer.swift`

- Tracks touch frames
- Determines one-, two-, and three-finger gestures
- Suppresses false taps during scrolling, physical clicks, and inertia
- Reads settings from `SettingsSnapshot`; does not read UserDefaults inside MT callbacks

### `EventInterceptor.swift`

Handles the following through a single CGEventTap:

- Monitoring physical clicks
- Converting a two-finger physical click into a middle click
- Monitoring scroll state
- Separating scroll ownership while in virtual trackpad mode
- Passing through native inertial scrolling

Inside the CGEventTap callback, it is a safety requirement not to allocate,
write to file logs, or read UserDefaults.

### `TrackpadModeController.swift`

- Converts relative movement on the Magic Mouse surface into cursor movement
- Generates events on a dedicated 120 Hz queue
- Stops cursor tracking during two-finger scrolling
- Switches modes via a three-finger double tap

### `MacroRecorder.swift` / `ActionExecutor.swift`

- Records key events with a listen-only CGEventTap
- Automatically stops after 200 events or 60 seconds
- Saves to on-device UserDefaults
- Plays back on a dedicated serial queue
- Interrupts a previous playback via a generation number when retriggered

The public release removes the unused code paths for arbitrary shell
commands, launching arbitrary apps, and generic keystrokes, exposing only
macros and trackpad-mode switching.

### `PermissionMonitor.swift`

Rather than relying solely on the TCC cache of `AXIsProcessTrusted()`, this
monitors permission state by checking whether a test CGEventTap can be
created. When permission is lost, it fully tears down EventInterceptor.

See [SAFETY.md](./SAFETY.md) for user-facing safety requirements.

### `PointerSpeedManager.swift`

Changes the system's `HIDMouseAcceleration` via the IOHIDEventSystemClient
SPI. It keeps the original value in UserDefaults and restores it on normal
termination.

### `Logger.swift`

Writes diagnostic information to the unified log and to
`~/Library/Logs/MagicMouseToolkit.log`. The file log rotates to
`MagicMouseToolkit.log.old` at roughly 1 MiB.

## Build and signing

`build.sh` compiles arm64 and x86_64 separately and combines them into a
Universal Binary with `lipo`.

- `SIGN_ID` unspecified: ad-hoc signing
- `SIGN_ID` specified and present in Keychain: signs with the specified identity

To distribute a public binary, Developer ID Application signing and Apple
notarization must be performed separately. Private keys and certificates are
not included in the repository.

## Private API boundary

This project depends on the following private APIs:

- `/System/Library/PrivateFrameworks/MultitouchSupport.framework`
- `MTDevice*`
- `MTRegisterContactFrameCallback`
- `IOHIDEventSystemClient*`
- `HIDMouseAcceleration`

As a result, it is not suitable for the Mac App Store and may lose
compatibility with future versions of macOS.
