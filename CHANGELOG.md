# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
  about 1.6 GB.

### Security

- VNC binds loopback by default and refuses a non-loopback bind without
  `VNC_PASSWORD`.
- `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` documents `--no-sandbox` as a
  requirement of Wine, not a convenience.

[Unreleased]: https://github.com/webees/winforms-wine-runtime/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/webees/winforms-wine-runtime/releases/tag/v1.0.0
