# Security policy

## Reporting a vulnerability

Please do not disclose security or privacy vulnerabilities in a public issue.
Use GitHub's private vulnerability reporting or a private Security Advisory for
this repository.

Include:

- affected commit or version
- macOS and device version
- reproduction steps
- expected and actual behavior
- whether Accessibility or Input Monitoring permissions were involved
- relevant logs with personal information removed

Do not reproduce permission-related input freezes without first reading
[SAFETY.md](./SAFETY.md).

## Scope

Security-sensitive areas include:

- CGEventTap creation and event transformation
- keyboard macro recording and playback
- accessibility permission monitoring
- shell or process execution
- system pointer-speed modification
- release signing and update distribution

The project does not currently provide automatic updates or network services.
