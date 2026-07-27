# Contributing

Contributions are welcome.

## Development setup

Requirements:

- macOS 26 or later
- Xcode or a Swift toolchain containing the macOS 26 SDK
- Apple Magic Mouse for physical gesture testing

Build:

```sh
./build.sh
```

The default build uses ad-hoc signing. To use an existing signing identity:

```sh
SIGN_ID="Your Signing Identity" ./build.sh
```

## Workflow

1. Create a focused feature branch.
2. Keep changes limited to one feature or fix.
3. Run `./build.sh`.
4. Describe the physical-device checks you performed.
5. Open a pull request with the motivation, implementation, risks, and checks.

## Input-safety rules

- Read [SAFETY.md](./SAFETY.md) before changing CGEventTap, permissions, or
  MultitouchSupport code.
- Do not use accessibility permission toggling as a routine test.
- Do not run `tccutil reset` in tests or setup scripts.
- Keep MT and CGEventTap callbacks allocation-free and free of file logging.
- Do not add code that silently records or transmits keyboard input.

## Licensing

Contributions are accepted under GPL-3.0-only. Preserve third-party copyright
and license notices. If code is based on another project, identify the source
and license in the pull request and update `THIRD_PARTY_NOTICES.md` when needed.
