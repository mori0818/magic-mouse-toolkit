# Safety

Magic Mouse Toolkit uses CGEventTap, which monitors and transforms system-wide
input, and Apple's private MultitouchSupport API. It has been verified on real
hardware for normal use, but operations that forcibly change permissions or
processes require caution.

## Accessibility permission

While Magic Mouse Toolkit is running, do not do the following:

- Turn off Magic Mouse Toolkit's accessibility permission in System Settings
- Remove Magic Mouse Toolkit from the accessibility list
- Reset permissions with `tccutil reset`
- Toggle the permission ON/OFF repeatedly in a short time

Revoking permission while an app holding a CGEventTap is running can cause
clicks and keyboard input to stop responding on the macOS side.

When changing permissions:

1. Quit Magic Mouse Toolkit normally from the menu bar
2. Confirm in Activity Monitor that `MagicMouseToolkit` has terminated
3. Change the permission in System Settings
4. Launch Magic Mouse Toolkit

If input stops responding, quit Magic Mouse Toolkit using another available
input path. If that does not recover it, restart macOS.

## Cursor speed

The speed boost temporarily changes the system-wide `HIDMouseAcceleration`.
It is restored to its original value on normal quit.

If the speed remains altered after a force quit:

1. Quit Magic Mouse Toolkit
2. Move the "System Settings → Mouse → Tracking speed" slider once
3. If needed, turn off Magic Mouse Toolkit's speed boost and restart it

## Macro recording

While recording, all keyboard events are monitored via a listen-only
CGEventTap. Recorded data is stored only on the local device, but you should
not record while entering passwords or other secret information.

## Development and verification

Even when modifying input-related code, do not use permission ON/OFF toggling
as a regression test. For changes around EventInterceptor, PermissionMonitor,
and MultitouchDevice, first build, review the code, and verify the normal
quit path.
