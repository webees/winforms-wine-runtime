# Security policy

## Supported versions

Only the latest minor release receives security fixes.

| Version | Supported |
|---|---|
| 1.x | ✅ |
| < 1.0 | ❌ |

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

- VNC binds `127.0.0.1` unless an operator explicitly changes `VNC_LISTEN`,
  and a non-loopback bind without `VNC_PASSWORD` aborts start-up.
- noVNC is the only published port; there is no other listening service.
- The image runs as root because Wine writes across the prefix. Compensate with
  `--read-only` plus writable `/wine`, `/data`, `/tmp`, dropped capabilities, and
  a read-only `/app` mount.
- `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` contains `--no-sandbox`, required
  because Chromium's sandbox needs kernel primitives Wine does not provide. This
  makes the embedded browser weaker than a native Chromium sandbox; treat remote
  content loaded in the WebView as fully privileged.

## Out of scope

- Vulnerabilities in the Windows application you copy into the image.
- Vulnerabilities that require an attacker to already control the container.
- Wine's inability to run a specific Windows API (a compatibility bug, not a
  security issue).
