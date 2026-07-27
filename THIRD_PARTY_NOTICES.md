# Third-party notices

Magic Control contains or is derived from ideas and portions of the following
open-source projects.

## MouseToucher

Repository: <https://github.com/meatpaste/mousetoucher>

License: MIT

Copyright (c) 2025 Roger Hughes

MouseToucher was used as the starting point for parts of the private
MultitouchSupport bridge declarations, device enumeration approach, direct
`swiftc`/`lipo` build flow, permission setup, and the early tap-recognition
prototype. Magic Control has substantially restructured and extended these
areas, but retains this notice because the provenance is material.

Current provenance by area:

| Magic Control area | MouseToucher relationship | Current state |
|---|---|---|
| `Sources/MultitouchBridge.h` | API declarations and touch-structure layout derived from the MouseToucher bridge | Renamed, corrected, reduced, and extended with family ID and IOHID SPI declarations |
| `Sources/MultitouchDevice.swift` | External-device enumeration and built-in-device filtering originated in MouseToucher | Reworked with family filtering, retain/release, sleep handling, reconnect retries, IOKit notifications, and source separation |
| `Sources/TouchGestureManager.swift` / `TapRecognizer.swift` | Early tap-recognition prototype was informed by MouseToucher | Replaced by a larger state machine with multi-finger groups, vetoes, macros, and trackpad mode |
| `Sources/SynthesizedClick.swift` | Initial CGEvent click-posting approach was informed by MouseToucher | Reworked with event signatures, right-click support, and diagnostics |
| `Sources/AppDelegate.swift` | Initial menu-bar and Accessibility setup was informed by MouseToucher | Reworked around settings, permission monitoring, sleep lifecycle, macros, and device state |
| `build.sh` | Direct `swiftc` plus `lipo` Universal Binary flow was informed by MouseToucher | Rewritten for the current source tree, macOS 26, configurable signing, retries, SwiftUI, QuartzCore, and IOKit |
| `Info.plist` / `main.swift` | Standard macOS app-bundle boilerplate follows the same shape | Product-specific identifiers and current deployment target |

A source comparison against MouseToucher `main` at commit `edc96506` found no
large unchanged Swift implementation block in the current Magic Control tree.
The remaining relationship is best described as limited direct textual reuse
plus material architectural and prototype provenance. It is intentionally
credited rather than minimized.

### MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## MiddleClick

Repository: <https://github.com/artginzburg/MiddleClick>

License: GNU General Public License v3.0

MiddleClick informed the CGEventTap approach used to transform a physical
mouse click into a middle click and was quoted in early architecture
documentation. Magic Control is distributed under GPL-3.0-only so that the
license remains compatible with this provenance. The GPL text is included in
[LICENSE](./LICENSE).

## Apple frameworks and trademarks

Magic Mouse, macOS, AppKit, SwiftUI, IOKit, and MultitouchSupport are Apple
technologies or trademarks. Apple does not endorse this project.
MultitouchSupport and the IOHIDEventSystemClient functions used here are not
public APIs and may change without notice.
