# Internationalization (Japanese/English localization) implementation procedure

Created: 2026-07-27. This document was written after verifying it against the actual current code (`main` branch, `ce0998e`) (checked against real source).
The goal is that the localization work can be completed by reading only this document. Rewriting the README's announcement text is out of scope (a separate task).

## 0. Current state (checked against real source)

- **Build method**: no Xcode project. `build.sh` calls `swiftc` directly to compile arm64/x86_64 separately and combines them with `lipo`.
  This means `.lproj` files are not automatically compiled or bundled. **Resources must be bundled manually.**
- **Localization infrastructure**: `NSLocalizedString` / `.strings` / `.xcstrings` currently do not exist at all. `Info.plist` also has neither
  `CFBundleDevelopmentRegion` nor `CFBundleLocalizations` set.
- **Distribution of Japanese strings** (across all 19 files in `Sources/`, 552 lines contain Japanese):
  - Of these, **382 lines are comments only** (out of scope for translation; left in Japanese as developer notes)
  - The remaining **roughly 170 lines are in-code strings** (UI display or log output), which are the candidates for conversion

## 1. Scope (targets and non-targets for this conversion)

### In scope (to be wrapped with NSLocalizedString)

Only strings the user actually sees on screen. Locations confirmed by inspecting the real source:

| File | Content | Approx. count |
|---|---|---|
| `Sources/AppDelegate.swift` | Menu-bar item titles (lines 164, 169, 174, 179, 186, 193, 197, 203, 209) and dynamic status strings (lines 262-263, 268-269, 276-277) | ~18 locations |
| `Sources/SettingsView.swift` | `Text` / `Button` / `Toggle` / `Picker` / `caption` / `SliderRow` labels throughout the settings screen | ~90 locations |
| `Sources/TrackpadModeHUD.swift` | line 69, `"トラックパッドモード beta"` | 1 location |
| `Sources/TapRecognizer.swift` | `TapFailureReason`'s 10 cases (lines 16-26) and the label/actual/threshold strings in `record()` calls | ~25 locations |
| `Sources/TouchGestureManager.swift` | 3 locations of `DebugFeed.shared.pushEvent(...)` (lines 357, 379, 385) | 3 locations |

Since these also appear in the debug live display the user sees in screenshots (the "Recent Events" and "Judgment Breakdown" panes),
the `TapFailureReason` and `pushEvent` text is easy to overlook but is included in scope.

### Out of scope (not touched this time)

- Japanese messages in `MMTLog.log(...)` calls (developer-facing diagnostic logs that only go to `~/Library/Logs/MagicMouseToolkit.log` and never appear in the UI).
  Will be broken out as a separate task if needed in the future.
- Comments (382 lines).
- Documentation text such as `README.md` (out of scope this time per the user's instruction; to be handled as a separate task once the code work is done).

## 2. Points requiring caution (enum rawValues doubling as display strings)

Real-source inspection found two spots where an enum's `rawValue` is used directly as the on-screen display string.
**Since these are not persisted (no `Codable`/`UserDefaults`), rewriting them is safe in itself**, but
translating `rawValue` directly into English would break the display logic wherever existing code references `.rawValue` (effectively yielding empty strings),
so we separate "identifier-purpose rawValue" from "display-purpose string."

- `Sources/SettingsView.swift` lines 68-71, `BoundActionKind` (`case macro = "マクロ"` etc.)
  → Change `rawValue` to an ASCII identifier and add `var localizedTitle: String`, with the UI referencing that instead.
  It's used only by `ForEach(BoundActionKind.allCases)` and `Identifiable`'s `id` (line 212), so no other logic is affected (confirmed).
- `Sources/TapRecognizer.swift` lines 16-26, `TapFailureReason`
  → Likewise, turn `rawValue` into an identifier and add `var localizedDescription: String`.
  The only reference sites are the `.rawValue` calls at `TouchGestureManager.swift` lines 277, 278, 330, 337 (confirmed),
  which should be replaced with `.localizedDescription`.

## 3. Infrastructure setup

1. **Add to Info.plist**:
   ```xml
   <key>CFBundleDevelopmentRegion</key>
   <string>ja</string>
   <key>CFBundleLocalizations</key>
   <array>
       <string>ja</string>
       <string>en</string>
   </array>
   ```
2. **New resource directories**: `Resources/ja.lproj/Localizable.strings`, `Resources/en.lproj/Localizable.strings`
   (create as empty files; the ja version will be generated via genstrings in §4)
3. **Modify `build.sh`**: add copying of Resources to the `.app` bundle-generation section
   (currently the part that creates `Contents/MacOS` and does `cp Info.plist`):
   ```sh
   mkdir -p "build/$APP/Contents/Resources"
   cp -R Resources/ja.lproj Resources/en.lproj "build/$APP/Contents/Resources/"
   ```
4. Since `build.yml`'s "Validate scripts and plist" step only runs `plutil -lint Info.plist`,
   it should still pass after adding the keys (no additional CI changes expected to be needed).

## 4. Code conversion / translation flow

1. Wrap the in-scope locations from §1 with `NSLocalizedString("original Japanese text", comment: "description of where it appears on screen")`.
   Use the Japanese original text itself as the key (following Apple's standard `genstrings` workflow; do not mint new keys).
2. For places using `String(format:)` (e.g. `SettingsView.swift` lines 187, 341, 349, etc., and `TapRecognizer.swift` lines 64-134),
   wrap the format string itself with `NSLocalizedString`. Where word order may differ in English, use positional specifiers like `%1$@`.
3. For the two spots from §2, once `rawValue` has been turned into an identifier, call `NSLocalizedString` inside `localizedTitle` / `localizedDescription`.
4. Once all locations have been wrapped, extract:
   ```sh
   genstrings -o Resources/ja.lproj Sources/*.swift
   ```
   The generated `Resources/ja.lproj/Localizable.strings` is UTF-16, so verify the encoding before committing,
   e.g. via `iconv -f UTF-16 -t UTF-8`.
5. Create `Resources/en.lproj/Localizable.strings` and add the English translation for each key from `ja.lproj` (manual translation).

## 5. Build and verification steps

1. Build with `./build.sh`.
2. Verify the English UI: launch with `open "build/Magic Mouse Toolkit.app" --args -AppleLanguages "(en)"` and visually check
   the three areas: the menu bar, the settings screen, and the debug live display (including the tap-judgment breakdown pane).
3. Also verify no strings are missing in Japanese (the default) (immediately after `genstrings`, ja should equal the original text, so there should be no diff).
4. `codesign --verify --deep --strict` is already verified by an existing step in `build.yml`, so no additional action is needed.

## 6. Suggested approach

Since converting all ~170 locations at once would make review difficult, proceed incrementally file by file:

1. Separate out identifiers for `TapFailureReason` / `BoundActionKind` (§2) — do this first since other files depend on it
2. `AppDelegate.swift` (menu)
3. `SettingsView.swift` (settings screen; since the count is high, split into first/second half if needed)
4. `TrackpadModeHUD.swift` / `TouchGestureManager.swift` (the rest)
5. Infrastructure setup from §3, run genstrings from §4, translate
6. Verification (§5)

Branch off `feature/localization` from the public repository's `main` (this is a separate lineage from the private development repository
`~/Documents/Claude/MagicControl`; since `main` is currently the source of truth in the public repository, branch directly from there).
