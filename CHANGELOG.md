# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); releases use
[CalVer](https://calver.org/) as `vYYYY.MM.DD`.

## [Unreleased]

### Changed

- The image is 1.13 GiB instead of 2.58 GiB. Wine's PE builtins are stripped
  (450 MB), the prefix links them instead of duplicating them (596 MB),
  WebView2 ships only the `en-US`/`zh-CN` locales and no DRM, PDF, telemetry,
  updater or GPU compiler components, the Perl runtime is gone, and so is the
  Mesa software rasteriser. New build
  arguments `WEBVIEW2_TRIM` and `MESA_TRIM` (both default `1`) restore any of
  these. Direct3D and OpenGL need `MESA_TRIM=0`.

## [2026.11.22.1] - 2026-11-22

### Changed

- Lower default memory use: .NET heap capped at 256 MiB without server GC or
  tiered PGO, WebView2 limited to one renderer process and a 256 MiB JS heap.
  Measured idle RSS drops from 217 MiB to 150 MiB with no other regression.

## [2026.11.19.2] - 2026-11-19

### Changed

- `docs/versioning.md` documents the fine-grained `RELEASE_TOKEN` releases need.

## [2026.11.19.1] - 2026-11-19

### Added

- Pushes to `main` with new `Unreleased` entries now release without a manual
  step: bump `scripts/version.sh`, merge the `chore(release): v<version>` pull
  request, tag and publish. Needs a `RELEASE_TOKEN` secret; pull requests opened
  by `GITHUB_TOKEN` never run workflows.
- CalVer dates follow `Asia/Shanghai` (`CALVER_TZ`), so a release made after
  local midnight is no longer rejected as future-dated.
- `scripts/quality.py` grades the repository against a 100-point rubric
  covering hygiene, shell, Python, supply chain, runtime hardening,
  governance, documentation, verification and leanness. `docs/quality.md`
  documents every check; `make quality` fails below 100.
- `scripts/test_rubrics.py` unit-tests both rubrics, and CI uploads
  `quality.json` as an artifact.
- `pyproject.toml` pins the `ruff` configuration used by `make lint`.
- The rubric now also checks empty/bloated files, Dependabot grouping and PR
  limits, the health-check boot window, the no-password warning, scoped
  workflow tokens, manual-only tag deletion, Markdown link integrity,
  environment-table parity, file and directory naming, the retired `2` alias,
  and the size of the tracked tree.

### Changed

- The default desktop is a low-bandwidth profile: `1280x720x24`, 15 fps, dynamic
  quality 5-8, one encoder thread and bandwidth preference; the self-test matches.
- Every dimension in both rubrics is now scored out of 100 and the overall
  score is their mean, so 100 requires every dimension at 100.
- Base images are pinned by digest (`UBUNTU_DIGEST`, `DOTNET_SDK_DIGEST`), and
  the WebView2 NuGet package is verified against `WEBVIEW2_SHA256`.
- GitHub Actions are pinned to 40-character commit SHAs with a `# vX` comment;
  the `supply-chain` checks enforce both.
- `make lint` now runs `shfmt`, `ruff`, the rubric tests and the quality gate.
- The docs auditor moved into `scripts/quality.py`: environment, argument,
  port, benchmark and image references are scored checks instead of a separate
  `check-docs.sh`.
- `make baseline` is a one-line recipe, and the health check is inline in the
  Dockerfile; `baseline.sh`, `check-docs.sh`, `check-action-pins.sh` and
  `healthcheck.sh` are gone.
- `.github/workflows/cleanup-actions.yml` is now `cleanup-runs.yml`, matching
  the concurrency group and what the job actually prunes.
- Both READMEs start with a language switch and share the same section set;
  release references are updated to `2026.11.17.1`.
- The `2` moving alias is no longer published or documented. The cleanup
  workflow can unlink retired tags on manual dispatch, with a `dry_run` input.

## [2026.11.17.1] - 2026-11-17

### Added

- `KASMVNC_PREFER_BANDWIDTH` lets the encoder trade quality for bytes on
  metered or lossy links.
- `docs/network-tuning.md` documents latency sources, host TCP settings, MTU
  handling, reverse-proxy requirements and per-link presets.

### Changed

- WebView2 starts with background networking, component updates, sync,
  crash reporting, first-run and background throttling disabled: no outbound
  traffic the application did not ask for, and timers keep running while the
  VNC tab is in the background.
- The Wine prefix is re-provisioned only when the image fingerprint changes
  instead of on every start. A registry import replaces eleven `wine reg add`
  calls, and an unchanged prefix skips the step entirely.
- Encoder settings are validated at startup instead of failing later inside
  KasmVNC.

## [2026.11.17] - 2026-11-17

First CalVer release, replacing the retired 1.x noVNC image.

### Added

- `scripts/bench.sh` measures image size, cold start, first window, idle memory,
  authentication and TLS, and writes a JSON report; `scripts/score.py` grades
  it out of 100 and fails below 90. CI and release both gate on that score.
- `scripts/check-docs.sh` verifies environment variables, build arguments,
  ports, links and the scoring table against the code.
- `docs/benchmark.md` records the measurement method, the 100-point rubric and
  the reference baselines behind the release gate.
- HTTP basic authentication derived from `VNC_PASSWORD`, and a hard refusal to
  start unauthenticated without `KASMVNC_ALLOW_NO_AUTH=1`.
- Encoder tuning knobs: `KASMVNC_FRAME_RATE`, `KASMVNC_QUALITY_MIN/MAX`,
  `KASMVNC_RECT_THREADS`, `KASMVNC_VIDEO_CODEC`.
- `KASMVNC_VIDEO` build argument installing FFmpeg so the WebCodecs path has a
  `libavcodec` to `dlopen()`.

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
- The Chinese README now mirrors the English one: the WebView2 requirement, the
  version policy, local build targets and the documentation index are no longer
  English-only.
- Slimmer image: one layer for the Wine prefix, `xvfb-run` for build-time
  checks, and unused packages (`xz-utils`, `scrot`, `procps`, extra font
  families) removed.
- `scripts/selftest.sh`, `scripts/bench.sh` and `scripts/bisect-webview2.sh`
  take the target platform from `PLATFORM`; the archive default is
  `linux/amd64`.
- Publish immutable `YYYY.MM.DD` image tags with moving `2` and `latest`
  aliases; `dev` and `dev-demo` remain local-only build tags.

### Fixed

- `scripts/check-docs.sh` now rejects documentation that tells users to pull the
  local `:dev` tag or a Windows path for `APP`, and checks the CalVer policy.
- `scripts/selftest.sh` resolves a relative `OUT_DIR` before handing it to
  `docker run` and reports a missing `report.json` explicitly instead of
  failing inside `cat`.
- The self-test window cannot start a second run while one is in flight, and
  reports grid columns instead of an always-zero row count.
- Cleanup workflows reject non-numeric `keep_runs`/`max_age_days` instead of
  silently deleting every run when the input parses to `NaN`.
- `.dockerignore` also excludes benchmark output, evidence directories and
  Python bytecode, so they cannot drift into the build context.
- `SECURITY.md` lists the current CalVer release as the supported version.
- Re-apply the CJK font mappings and MSVC DLLs on every start, so a `/wine`
  volume created by an older image is upgraded instead of silently keeping
  stale fonts and DLLs.
- Fail with a clear message when `APP` is a Windows path or when prefix setup
  fails, instead of resolving an unreachable `C:\...` path.
- Probe KasmVNC with `ss` in the healthcheck; bash `/dev/tcp` does not handle
  IPv6 literals reliably and ignored a custom `KASMVNC_LISTEN`.
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
- Builds fail fast on any architecture other than `amd64`: the WebView2 runtime
  is x64-only, so the previous `arm64` path produced an image that could not run
  the target applications.
- `examples/docker-compose.yml` honours `KASMVNC_SSL` from `.env` instead of
  hard-coding TLS on.
- CI's action-pinning check now also inspects `uses:` lines that are not the
  first element of a step, which is how `release.yml` declares its actions.
- `scripts/bench.sh` derives the container port from one variable instead of
  repeating `6901`, and `scripts/bisect-webview2.sh` removes its ~4 GiB image
  unless `KEEP_IMAGE=1` is set.
- The self-test builds its report in one pass over a step list; the unused
  `SELFTEST_OUT` fallback and the null guards for controls that are always
  created are gone.
- Action pinning lives in `scripts/check-action-pins.sh`, shared by `make lint`
  and CI, and `cleanup-actions.yml` prunes runs, caches and artifacts in one
  validated script step instead of three copies.
- `make baseline` reports tracked files, lines, bytes and the largest files, so
  size changes are comparable across commits.
- The default Docker stage is the app-free runtime again: only `--target demo`
  adds the self-test application, and CI fails if `/app` is not empty in the
  published image.

### Removed

- `x11vnc`, `noVNC` and `websockify` from the image.
- `docs/images/` screenshots; the self-test table documents the same evidence.

[Unreleased]: https://github.com/webees/winforms-wine-runtime/compare/v2026.11.22.1...HEAD
[2026.11.22.1]: https://github.com/webees/winforms-wine-runtime/releases/tag/v2026.11.22.1
[2026.11.19.2]: https://github.com/webees/winforms-wine-runtime/releases/tag/v2026.11.19.2
[2026.11.19.1]: https://github.com/webees/winforms-wine-runtime/releases/tag/v2026.11.19.1
[2026.11.17.1]: https://github.com/webees/winforms-wine-runtime/releases/tag/v2026.11.17.1
[2026.11.17]: https://github.com/webees/winforms-wine-runtime/releases/tag/v2026.11.17
