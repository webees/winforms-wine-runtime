# Architecture

## Layers

| Layer | Contents | Reason |
|---|---|---|
| OS | Ubuntu 26.04 | Ships Wine 10; Wine 9 (24.04) cannot load .NET 8 assemblies |
| Display | Xvfb `:99` | No GPU, no desktop environment; a fixed 1600×900 surface |
| Remote | x11vnc + noVNC | Browser-native access, no client install |
| Runtime | Wine 10, prefix at `/wine` | Runs `win-x64` self-contained .NET 8 |
| Vendor | WebView2 Fixed Version, MSVC runtime, CJK fonts | Things Wine does not provide |
| App | `/app` | Copied by the consumer image |

## Boot sequence

1. `tini` reaps zombies and forwards signals.
2. `entrypoint.sh` starts Xvfb and waits for `xdpyinfo` to succeed.
3. If `/wine/system.reg` is missing, `wineboot -u` initialises the prefix, then
   `wineserver -w` waits for the server to exit cleanly.
4. When `ENABLE_VNC=1`, x11vnc binds `VNC_LISTEN:VNC_PORT` and websockify
   bridges `NOVNC_PORT` to it.
5. The entrypoint `exec`s Wine with the application, so the app is PID 2 and
   receives signals from `tini`.

## Build-time decisions

**WebView2 Fixed Version, not Evergreen.** The Evergreen bootstrapper requires a
real Windows service stack; it fails silently under Wine. The Fixed Version is a
plain directory and is redirected with
`WEBVIEW2_BROWSER_EXECUTABLE_FOLDER=C:\webview2`.

**Version ceiling 135.0.3179.98.** Later runtimes start
`msedgewebview2.exe` and a renderer but never finish navigation. This is
reproducible and independent of `--single-process`, `--in-process-gpu`,
`--use-angle=swiftshader` or GPU flags.

**`msedge.dll` is mandatory.** NuGet package `webview2.runtime.x64` bundles the
Chromium core up to 151; from 152 it moved to `webview2.runtime.x64.core`.
Without `msedge.dll` the process exits with code 13 without output, so the
Dockerfile fails the build instead of shipping a broken image.

**Fonts, three ways.** GDI+ (WinForms) and DirectWrite (Chromium inside
WebView2) look in different places, and neither reads fontconfig:

- `C:\windows\Fonts` + `FontSubstitutes` covers WinForms.
- `HKLM\...\CurrentVersion\Fonts` registration is what DirectWrite enumerates.
  Merely copying the file is invisible to the embedded browser.
- DirectWrite does not load `.ttc` collections under Wine, so
  `DroidSansFallbackFull.ttf` is installed alongside `wqy-microhei.ttc`.

Fonts are installed **after** the prefix exists. Registry writes made while
`wineboot` is running are lost when Wine flushes its registry at exit — a bug
that only shows up as tofu inside the embedded browser.

**MSVC runtime copy.** `msedgewebview2.exe` needs `vcruntime140*`, `msvcp140*`
and `vccorlib140*`; Wine's built-ins are incomplete. The DLLs shipped inside the
WebView2 package are copied into `system32`.

**`wineserver -w` before exiting a build layer.** Killing the server while a
layer finishes corrupts the prefix in a way that only shows up later as
`Bitmap.Save()` failing with a generic GDI+ error.

**`WINE64_ONLY=1` by default.** Removing `i386-windows` and `syswow64` saves
about 1.6 GB and does not affect `win-x64` .NET applications.

## Runtime model

Each container is one desktop session. The WebView2 user-data folder holds a
singleton lock, and the Wine prefix is not designed for concurrent writers, so
horizontal scaling means more containers behind your ingress.
