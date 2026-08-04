# Magic Mouse Toolkit

Magic Mouse Toolkit is an open-source macOS utility that adds configurable gestures
and a virtual trackpad mode to Apple Magic Mouse.

The UI supports Japanese and English (follows the system's `AppleLanguages` setting).

## Features

- Left/right click via one-finger tap
- Left click via two-finger tap
- Middle click via two-finger physical click
- Play back a recorded keyboard macro with a three-finger tap
- Virtual trackpad mode: stroke the Magic Mouse surface with one finger
- Two-finger scrolling and native inertia while in virtual trackpad mode
- Toggle modes with a three-finger double tap
- Input isolation from the MacBook's built-in trackpad
- Magic Mouse battery level display
- Cursor speed boost
- Tap zone, sensitivity, and scroll settings configurable from the UI

## Requirements

- macOS 26 or later
- Apple Magic Mouse
- Xcode, or a Swift toolchain that includes the macOS 26 SDK, to build
- Accessibility permission for click synthesis, macros, and input remapping

This app uses Apple's private `MultitouchSupport.framework` and IOKit SPIs.
It may stop working after a future macOS update and is not intended for the Mac App Store.

## Safety

**Do not turn off or remove Accessibility permission from System Settings while Magic Mouse Toolkit is running.**

Changing this permission while an app using CGEventTap is running can freeze macOS system input.
If you need to change the permission, quit Magic Mouse Toolkit normally from the menu bar first.
Do not use `tccutil reset` as part of normal setup or troubleshooting.

See [SAFETY.md](./SAFETY.md) for details.

## Build

```sh
git clone https://github.com/mori0818/magic-mouse-toolkit.git
cd magic-mouse-toolkit
./build.sh
open "build/Magic Mouse Toolkit.app"
```

If `SIGN_ID` is not set, an ad-hoc signature is used.

```sh
SIGN_ID="Developer ID Application: Example (TEAMID)" ./build.sh
```

You can also specify a local self-signed certificate via `SIGN_ID`. Do not commit
certificates or private keys to the repository. Changing the signature may cause macOS
to ask you to re-grant Accessibility permission — in that case too, quit the old app
before changing the permission.

## Privacy

- The app itself has no telemetry, analytics SDKs, or network transmission.
- While recording a macro, keyboard key codes, modifier keys, press state, and timing
  are saved to UserDefaults on-device. No strings or input content are sent externally.
- Do not record a macro while entering passwords or secrets.
- Diagnostic logs are saved to `~/Library/Logs/MagicMouseToolkit.log` and rotate at
  about 1 MiB. Logs may contain operational metadata such as gesture decisions and coordinates.

## System-wide settings

The cursor speed boost temporarily changes the system-wide `HIDMouseAcceleration` value.
It's restored on normal quit, but if the speed stays changed after a force quit, quit
Magic Mouse Toolkit and then move the "System Settings → Mouse → Tracking speed" slider
to restore it.

## Documentation

- [SAFETY.md](./SAFETY.md) — Safety information on permission changes, input freezes, and speed settings
- [SPEC.md](./SPEC.md) — Feature specification
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Architecture and third-party code provenance
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) — Implementation details
- [UI_DESIGN.md](./UI_DESIGN.md) — UI and design policy
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) — Third-party code and licenses
- [CONTRIBUTING.md](./CONTRIBUTING.md) — How to contribute
- [SECURITY.md](./SECURITY.md) — How to report vulnerabilities

## Third-party work

Magic Mouse Toolkit started in part from MouseToucher's MIT-licensed code and design,
and references/adapts MiddleClick's GPL-3.0 implementation. See
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for provenance and full license text.

## License

Magic Mouse Toolkit is licensed under the GNU General Public License v3.0 only.
See [LICENSE](./LICENSE).
