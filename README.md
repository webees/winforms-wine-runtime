# winforms-wine-runtime

**English** · [简体中文](README.zh-CN.md)

[![CI](https://github.com/webees/winforms-wine-runtime/actions/workflows/ci.yml/badge.svg)](https://github.com/webees/winforms-wine-runtime/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/webees/winforms-wine-runtime?sort=date)](https://github.com/webees/winforms-wine-runtime/releases)
[![Image](https://img.shields.io/badge/ghcr.io-winforms--wine--runtime-blue)](https://github.com/webees/winforms-wine-runtime/pkgs/container/winforms-wine-runtime)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Run **.NET 8 WinForms** desktop applications — including **WebView2**, **SunnyUI** and
**Magick.NET** — inside a Linux container, and reach them from any browser.

The image is a thin, verified runtime: Wine 10, KasmVNC, the WebView2 Fixed
Version runtime, CJK font substitution, and the MSVC runtime Chromium needs.
Your application is copied in as a self-contained `win-x64` publish output.

```
browser ── :6901 ──► Xkasmvnc :99 ──► Wine 10 ──► YourApp.exe
                      (X server +          ├─ .NET 8 (self-contained)
                       WebP/JPEG/H.264     ├─ WebView2 Fixed Version 135
                       encoder + web UI)   ├─ SunnyUI
                                           └─ Magick.NET
```

One process owns the display, the encoder and the web client. There is no
`Xvfb` + `x11vnc` + `websockify` chain on the desktop path: KasmVNC's X server
encodes damage regions in C++, mixes WebP and JPEG per rectangle, and upgrades
the media path to H.264 when FFmpeg and a large changed area make it worthwhile.

## Why

- **Cost** — 300–500 MB per session instead of 4–8 GB for a Windows VM.
- **Licensing** — Wine needs no Windows licence; Windows client editions do not
  permit multi-session hosting anyway.
- **Deployment** — the same `docker run` / Kubernetes primitives you already use.

## Quick start

```bash
make build-demo
# Local-only tag; the published runtime is a CalVer tag.
docker run --rm -p 6901:6901 \
  -e ENABLE_VNC=1 -e VNC_PASSWORD=change-me \
  -v wine-prefix:/wine -v app-data:/data \
  ghcr.io/webees/winforms-wine-runtime:dev-demo
```

Open <https://localhost:6901>, accept the self-signed certificate, type the
password, and the self-test application appears on a 1600×900 desktop. Set
`-e KASMVNC_SSL=0` when a TLS-terminating proxy sits in front of the container.

The published GHCR package is the **runtime** — it contains no application. The
`-demo` tag exists only for local verification and CI, and is the only build
that adds the self-test app (`--target demo`); a plain `docker build .`
produces the app-free runtime. `dev` and `dev-demo` are local-only tags and are
never pushed.

> **Releases use CalVer:** `vYYYY.MM.DD` in Git, `YYYY.MM.DD` in GHCR. `2` and
> `latest` are moving aliases; pin the exact date tag or a digest in production.
> See [docs/versioning.md](docs/versioning.md).

## Use it for your own application

```dockerfile
FROM ghcr.io/webees/winforms-wine-runtime:2026.11.17.1
COPY publish/ /app/
ENV APP=YourApp.exe
```

```bash
dotnet publish -c Release -r win-x64 --self-contained true -o publish
docker build -t your-app .
docker run --rm -p 6901:6901 -e ENABLE_VNC=1 -e VNC_PASSWORD=change-me your-app
```

`APP` may be omitted when `/app` contains a single application `.exe`; runtime
helpers such as `createdump.exe` are ignored when guessing.

## Ports

| Port | Protocol | Default | Purpose |
|---|---|---|---|
| `6901` | TCP | published | KasmVNC web client, WebSocket and desktop |

`6901` is the only port. `KASMVNC_LISTEN` defaults to `0.0.0.0`; the container
refuses to start without `VNC_PASSWORD` unless `KASMVNC_ALLOW_NO_AUTH=1` is set
explicitly. See [docs/ports-and-volumes.md](docs/ports-and-volumes.md).

## Persistence

| Path | Contents | Recommended |
|---|---|---|
| `/wine` | Wine prefix (`C:\`), fonts, registry, WebView2 profile default | named volume or PVC |
| `/data` | Application data and self-test output | named volume, or bind mount |
| `/app` | Published application | read-only bind mount or image layer |

The prefix is initialised on first start when `/wine` is empty (about 20 s), so a
fresh volume is safe. Keep `/wine` across restarts to avoid re-initialisation and
to preserve per-user settings.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `APP` | first `*.exe` in `/app` | Executable to launch: a bare file name under `/app` or an absolute Linux path; Windows paths such as `C:\...` are rejected |
| `APP_ARGS` | empty | Extra command-line arguments, split on whitespace (no quote handling) |
| `SCREEN` | `1600x900x24` | Desktop geometry and colour depth |
| `ENABLE_VNC` | `0` | `1` starts KasmVNC |
| `VNC_PASSWORD` | empty | HTTP basic auth password, minimum 6 characters |
| `KASMVNC_PORT` | `6901` | Web client, WebSocket and desktop port |
| `KASMVNC_LISTEN` | `0.0.0.0` | Address KasmVNC binds |
| `KASMVNC_SSL` | `1` | `1` serves HTTPS with a self-signed certificate |
| `KASMVNC_CERT` | empty | PEM with certificate and key, overrides the self-signed one |
| `KASMVNC_ALLOW_NO_AUTH` | `0` | `1` allows an unauthenticated desktop |
| `KASMVNC_FRAME_RATE` | `30` | Encoder frame rate ceiling |
| `KASMVNC_QUALITY_MIN` / `KASMVNC_QUALITY_MAX` | `7` / `8` | Dynamic JPEG/WebP quality floor and ceiling (0–9) |
| `KASMVNC_VIDEO_CODEC` | `auto` | `auto`, `h264`, `h265`, `av1`, or a `*_vaapi` variant |
| `KASMVNC_RECT_THREADS` | `0` | Encoder thread count, `0` = automatic |
| `KASMVNC_PREFER_BANDWIDTH` | `0` | `1` trades quality for bandwidth (lower quality steps, more compression) |
| `WEBVIEW2_USER_DATA_FOLDER` | unset | Not set by the image; applications should pass `userDataFolder` to `CreateAsync` (the self-test uses `Z:\data\wv2`) |

Auto-detection scans only the top level of `/app` (not recursively) and skips
runtime helpers such as `createdump.exe` and `*.vshost.exe`. Point `APP` at a
subdirectory with a relative name, e.g. `sub/YourApp.exe`.

## WebView2: one required line of code

Under Wine the WebView2 loader does not discover a Fixed Version runtime by
itself, and `WEBVIEW2_BROWSER_EXECUTABLE_FOLDER` is not honoured either: the
loader only uses the runtime when the application passes the folder explicitly.

```csharp
var dir = Environment.GetEnvironmentVariable("WEBVIEW2_BROWSER_EXECUTABLE_FOLDER"); // C:\webview2
var env = await CoreWebView2Environment.CreateAsync(
    dir, userDataFolder, new CoreWebView2EnvironmentOptions());
await webView.EnsureCoreWebView2Async(env);
```

`C:\webview2` is a fixed path inside the image, so `dir` can also be hard-coded.
Touching `C:\webview2` directly with Windows APIs requires the prefix, not the
host.

## WebView2 version policy

The image ships the **Fixed Version** runtime (NuGet `webview2.runtime.x64`), not
the Evergreen installer, because the installer cannot run under Wine.

Wine 10 currently supports runtimes **≤ 135.0.3179.98**; 136 and later start a
renderer but never complete navigation or the `postMessage` bridge. Do not bump
`WEBVIEW2_VERSION` without running `scripts/bisect-webview2.sh` and the self-test.

## What is verified

`docker run ... --selftest --strict` executes a four-step report:

| Step | Assertion |
|---|---|
| `sunnyui` | `UIForm`, `UIDataGridView` and CJK text render |
| `magick` | `Magick.NET-Q8` draws and encodes a PNG |
| `webview2` | Chromium navigates, executes JS, `postMessage` round-trips |
| `webview2-shot` | `CapturePreviewAsync` returns a non-empty PNG |

Latest run (Ubuntu 26.04 / Wine 10.0 / WebView2 `135.0.3179.98`, 12 vCPU, no GPU):
all four steps pass in 10–15 s; `webview2` accounts for most of it.

CI runs this suite plus `scripts/bench.sh` on every push and fails the build if
`report.json` reports a failure or the score drops below 90.

## Limits

- **One session per container.** The Wine prefix and the WebView2 user-data
  folder cannot be shared by concurrent processes (WebView2 takes an exclusive
  lock). Scale by adding containers, not sessions.
- **amd64 only.** Wine on arm64 cannot run a `win-x64` .NET application without
  a full x86-64 emulator; the project does not publish arm64 images.
- **No GPU.** Rendering falls back to software unless you pass `/dev/dri` and
  change `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`.
- **No Windows shell.** There is no Explorer or taskbar in the container. CJK
  input relies on the KasmVNC client's IME mode, or on pasting text; it does not
  go through a Windows IME.
- **Web desktop only.** KasmVNC's web client is not compatible with generic VNC
  viewers: the HTTP endpoint is the only supported entry point.

## Security

The container executes arbitrary Windows code under Wine. Wine is **not** a
sandbox: an application that escapes its UI can read the whole container
filesystem. Treat each container as you would a desktop you do not trust —
drop capabilities, publish only `6901`, keep TLS on (or terminate it in front),
and never mount host paths you would not expose. See [SECURITY.md](SECURITY.md).

## Build arguments

| Argument | Default | Meaning |
|---|---|---|
| `UBUNTU_VERSION` | `26.04` | Base distribution; 22.04 and 24.04 ship Wine 6.0 and 9.0, which cannot load .NET 8 |
| `UBUNTU_DIGEST` | `sha256:d66b…` | Digest pin for the base image; `UBUNTU_VERSION` supplies the tag |
| `DOTNET_SDK_IMAGE` | `mcr.microsoft.com/dotnet/sdk:8.0` | Builds the self-test application |
| `DOTNET_SDK_DIGEST` | `sha256:1b95…` | Digest pin for the SDK image |
| `WEBVIEW2_VERSION` | `135.0.3179.98` | Fixed Version runtime, see the version policy above |
| `WEBVIEW2_SHA256` | `a6647e…` | NuGet package checksum; bump it together with `WEBVIEW2_VERSION` |
| `KASMVNC_VERSION` | `1.5.2` | KasmVNC release; the pinned SHA-256 only matches 1.5.2, so overriding it requires updating the checksum |
| `KASMVNC_VIDEO` | `1` | Install FFmpeg for the WebCodecs H.264/H.265/AV1 path |
| `WINE64_ONLY` | `1` | Drop 32-bit Wine (`i386-windows`, `syswow64`), about 1.2 GB |
| `IMAGE_VERSION` | `dev` | `org.opencontainers.image.version` label |
| `SOURCE_REVISION` | `unknown` | `org.opencontainers.image.revision` label |
| `TARGETARCH` | `amd64` | Set by BuildKit; only `amd64` is accepted |

## Build locally

```bash
make build          # runtime + self-test targets
make test           # run the self-test suite in a container
make bench          # measure size, start-up, memory and write bench.json
make score          # grade bench.json, exit non-zero below 90
make baseline       # tracked files, lines and bytes plus the largest files
make score-test     # unit tests for the scoring rubric
make lint           # shellcheck, hadolint, actionlint, action pins, docs sync, score tests
```

On an arm64 host every target runs under QEMU emulation, which is supported but
much slower; CI and production use native x86-64.

## Documentation

- [docs/architecture.md](docs/architecture.md) — layers, boot sequence, design decisions
- [docs/versioning.md](docs/versioning.md) — CalVer policy and release workflow
- [docs/ports-and-volumes.md](docs/ports-and-volumes.md) — networking and persistence
- [docs/network-tuning.md](docs/network-tuning.md) — latency, TCP, MTU and KasmVNC tuning
- [docs/troubleshooting.md](docs/troubleshooting.md) — known failures and fixes
- [docs/benchmark.md](docs/benchmark.md) — measured baseline and scoring
- [docs/quality.md](docs/quality.md) — engineering rubric, checks and 100-point gate

## License

MIT for this repository. Bundled components (Wine, WebView2 runtime, KasmVNC,
fonts) keep their own licences; **KasmVNC is GPL-2.0**, which matters when you
redistribute the image — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

中文说明见 [README.zh-CN.md](README.zh-CN.md)。
