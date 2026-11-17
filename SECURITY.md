# Security policy

## Supported versions

Only the newest CalVer release receives security fixes.

| Version | Supported |
|---|---|
| `2026.11.17` (latest) | ✅ |
| older CalVer releases | ❌ |
| 1.x (retired noVNC image) | ❌ |

## Reporting a vulnerability

Open a [private security advisory](https://github.com/webees/winforms-wine-runtime/security/advisories/new)
with reproduction steps. Please do not file a public issue. We aim to
acknowledge reports within seven days.

## Threat model

This image runs **arbitrary Windows binaries** under Wine. That has two
consequences:

1. **Wine is not a sandbox.** A malicious application can read and write
   anything the container user can reach, including `/wine`, `/data` and any
   mounted secret. Do not mount host paths or Docker sockets into a container
   running untrusted code.
2. **The desktop is a session, not a boundary.** If several users must be
   isolated from each other, give each one a container and a distinct network
   policy; never share a prefix or a WebView2 user-data folder.

Default posture, and what the project maintains:

- The desktop refuses to start without `VNC_PASSWORD` unless the operator sets
  `KASMVNC_ALLOW_NO_AUTH=1`; the password is stored as an HTTP basic-auth
  credential, not as a VNC password.
- `KASMVNC_SSL=1` is the default, so the browser session is encrypted end to end
  even when `6901` is published directly.
- `6901` is the only published port; there is no other listening service.
- The image runs as root because Wine writes across the prefix. Compensate with
  `--read-only` plus writable `/wine`, `/data`, `/tmp`, dropped capabilities, and
  a read-only `/app` mount.
- `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` contains `--no-sandbox`, required
  because Chromium's sandbox needs kernel primitives Wine does not provide. This
  makes the embedded browser weaker than a native Chromium sandbox; treat remote
  content loaded in the WebView as fully privileged.
- KasmVNC's HTTP endpoint is the only supported client; do not expect generic
  VNC viewers or port scanners to be rejected on a second port, because there
  is no second port.

## Out of scope

- Vulnerabilities in the Windows application you copy into the image.
- Vulnerabilities that require an attacker to already control the container.
- Wine's inability to run a specific Windows API (a compatibility bug, not a
  security issue).
