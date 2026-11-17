# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/bench.sh` measures image size, cold start, first window, idle memory,
  authentication and TLS, and writes a JSON report; `scripts/score.py` grades
  it out of 100 and fails below 90. CI and release both gate on that score.
- `scripts/check-docs.sh` verifies environment variables, build arguments,
  ports, links and the scoring table against the code.
- `docs/benchmark.md` records the measurement method, the 100-point rubric and
  the reference baselines behind the release gate.

### Changed

- Slimmer image: one layer for the Wine prefix, `xvfb-run` for build-time
  checks, and unused packages (`xz-utils`, `scrot`, `procps`, extra font
  families) removed.
- `scripts/selftest.sh`, `scripts/bench.sh` and `scripts/bisect-webview2.sh`
  take the target platform from `PLATFORM`; the archive default is
  `linux/amd64`.

### Fixed

- The `org.opencontainers.image.base.name` label now includes the Ubuntu
  version; `UBUNTU_VERSION` was not declared inside the build stage, so the
  label ended with a bare `ubuntu:`.
- `scripts/bench.sh` names its containers per run, so a parallel run or a
  retry cannot collide; `scripts/selftest.sh` emits the parsed summary through
  `SUMMARY_FILE` instead of `bench.sh` carrying a second JSON parser.
- `scripts/bench.sh` fails when no application window appears instead of
  reporting a zero-millisecond window time, and keeps the self-test report and
  screenshots only when `--evidence` is given.
- `SCREEN` accepts `WIDTHxHEIGHT` and defaults the depth to 24; malformed values
  fail at startup instead of starting a desktop the web client cannot open.
- The KasmVNC password file and self-signed certificate live under
  `/tmp/.kasmvnc`, so `--read-only` works with only `/tmp`, `/wine` and `/data`
  writable. A failed credential write now aborts startup instead of leaving the
  desktop in an undefined auth state.

## [2.0.0] - 2026-11-17

### Changed

- **Breaking:** the desktop path is now KasmVNC 1.5.2 instead of
  Xvfb + x11vnc + noVNC. One process (`Xkasmvnc`) owns the display, the encoder
  and the web client, so frames are damage-driven instead of polled, rectangles
  mix WebP and JPEG per update, and large changed areas can use WebCodecs
  H.264/H.265/AV1.
- **Breaking:** the published port is `6901` (was `6080`) and `5900` no longer
  exists. `NOVNC_PORT`, `VNC_PORT` and `VNC_LISTEN` are replaced by
  `KASMVNC_PORT`, `KASMVNC_*` and `KASMVNC_SSL`.
- **Breaking:** the container serves HTTPS with a generated self-signed
  certificate by default. Set `KASMVNC_SSL=0` behind a TLS-terminating proxy.

### Added

- HTTP basic authentication derived from `VNC_PASSWORD`, and a hard refusal to
  start unauthenticated without `KASMVNC_ALLOW_NO_AUTH=1`.
- Encoder tuning knobs: `KASMVNC_FRAME_RATE`, `KASMVNC_QUALITY_MIN/MAX`,
  `KASMVNC_RECT_THREADS`, `KASMVNC_VIDEO_CODEC`.
- `KASMVNC_VIDEO` build argument installing FFmpeg so the WebCodecs path has a
  `libavcodec` to `dlopen()`.

### Removed

- `x11vnc`, `noVNC` and `websockify` from the image.

## [1.0.0] - 2026-11-17

### Added

- Runtime base image `ghcr.io/webees/winforms-wine-runtime` for `win-x64`
  self-contained .NET 8 WinForms applications.
- Wine 10 on Ubuntu 26.04, Xvfb, x11vnc and noVNC, with healthcheck.
- WebView2 Fixed Version runtime 135.0.3179.98 exposed as `C:\webview2`, plus
  the MSVC runtime Chromium requires.
- CJK font substitution through `C:\windows\Fonts` and the `FontSubstitutes`
  registry key.
- `demo` target with a four-step self-test (`sunnyui`, `magick`, `webview2`,
  `webview2-shot`) producing `report.json` and PNG evidence.
- CI (lint, build, self-test, image scan), release workflow publishing to GHCR
  with SBOM and provenance, and scheduled cleanup of workflow runs, artifacts
  and package versions.
- `WINE64_ONLY` build argument (default on) that removes `syswow64` and saves
  about 1.2 GB.

### Security

- VNC binds loopback by default and refuses a non-loopback bind without
  `VNC_PASSWORD`.
- `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` documents `--no-sandbox` as a
  requirement of Wine, not a convenience.

[Unreleased]: https://github.com/webees/winforms-wine-runtime/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/webees/winforms-wine-runtime/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/webees/winforms-wine-runtime/releases/tag/v1.0.0
