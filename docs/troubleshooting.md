# Troubleshooting

## The desktop is black in the browser

1. Check the container is running: `docker ps`.
2. Check health: `docker inspect --format '{{.State.Health.Status}}' <container>`.
3. Read logs: `docker logs <container>`. `[entrypoint] KasmVNC listening on`
   must appear, and `/tmp/kasmvnc.log` inside the container holds the encoder
   log.
4. If a proxy sits in front of `6901`, confirm WebSocket upgrade is allowed and
   that it accepts the self-signed certificate, or set `KASMVNC_SSL=0` and
   terminate TLS at the proxy.

## `KasmVNC failed to start`

The entrypoint prints the last 40 lines of `/tmp/kasmvnc.log`. The common cause
is a missing password file: set `VNC_PASSWORD`, or `KASMVNC_ALLOW_NO_AUTH=1`
when an authenticating proxy is in front.

## Video looks like JPEG instead of H.264

The WebCodecs path needs `libavcodec` and only engages on large changed areas.
Check what was loaded:

```bash
docker exec <container> ldconfig -p | grep libavcodec
```

A `libavcodec.so.` line means the encoder can be `dlopen()`ed at runtime. The
adapter is loaded lazily and is not logged; `/tmp/kasmvnc.log` only reports
hardware acceleration (`... capability: none` is expected without `/dev/dri`).
Rebuild with `--build-arg KASMVNC_VIDEO=1` (the default) if the library is
missing.

## `WebView2 did not post 'ready' within 60 s`

Three causes, in order of likelihood:

1. **The application did not pass the runtime folder.** The loader cannot
   discover a Fixed Version runtime under Wine. Pass
   `Environment.GetEnvironmentVariable("WEBVIEW2_BROWSER_EXECUTABLE_FOLDER")` as
   the `browserExecutableFolder` argument of `CoreWebView2Environment.CreateAsync`.
   The symptom is `WebView2RuntimeNotFoundException`.
2. **Runtime above the Wine ceiling.** Check the reported version:

```bash
docker exec <container> ls /opt/webview2 | head
```

Anything above `135.0.3179.98` is unsupported today. Rebuild with
`--build-arg WEBVIEW2_VERSION=135.0.3179.98`.

3. **`msedge.dll` missing.** The Dockerfile guards against it, but a
custom `FROM` layer can delete it. Verify with
`test -f /opt/webview2/msedge.dll`.

## `msedgewebview2.exe` exits with code 13

Same two causes as above: missing `msedge.dll`, or a version above the ceiling.
There is no diagnostic output; the exit code is the only signal.

## CJK text renders as boxes

Two different renderers are involved and they need different things.

**WinForms / GDI+** enumerates fonts through GDI. The font must exist in
`C:\windows\Fonts` and, for family names the application asks for by name, a
`FontSubstitutes` entry must point at it. fontconfig alone is not enough. Both
are done in the image:

```bash
cp your.ttf /wine/drive_c/windows/Fonts/
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' \
  /v "Microsoft YaHei" /d "Your Font" /f
```

**WebView2 / Chromium** enumerates fonts through DirectWrite, which under Wine
does not load `.ttc` collections such as `wqy-microhei.ttc`. A `.ttf` **is**
visible. The image therefore also installs `DroidSansFallbackFull.ttf`; in HTML
use an explicit family instead of relying on `sans-serif`:

```css
body { font-family: "Droid Sans Fallback", "DejaVu Sans", sans-serif; }
```

`@font-face` with a `.ttc` file does not work either. If you need a specific
typeface in embedded HTML, ship a `.ttf` inside your application and reference
it with a relative URL.

Copying the `.ttf` into `C:\windows\Fonts` is still not enough for DirectWrite:
the font must also be registered, which is what the Windows font installer does:

```bash
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
  /v "Droid Sans Fallback (TrueType)" /d DroidSansFallbackFull.ttf /f
```

Write these keys **after** `wineboot` has finished and `wineserver` has exited;
keys written during prefix creation are discarded.

## `Bitmap.Save()` throws a generic GDI+ error

The Wine prefix is inconsistent. It happens when a build layer kills
`wineserver` instead of waiting for it (`wineserver -w`). Rebuild the image, or
start the container with an empty `/wine` volume.

## The application starts once and then crashes on restart

The WebView2 user-data folder is left locked or half-written. Pass a unique
`userDataFolder` to `CoreWebView2Environment.CreateAsync` for each session (the
self-test uses `/data/wv2`), or start with a fresh `/data`.

## `win-x64` application fails with `ERROR_MOD_NOT_FOUND`

The application was not published self-contained. Publish with
`-r win-x64 --self-contained true`; framework-dependent publishes need a .NET
runtime inside the container, which this image intentionally does not install.

## 32-bit dependencies

The default image is 64-bit Wine only. Rebuild with
`--build-arg WINE64_ONLY=0` when you need `syswow64`.

## Diagnostics

```bash
docker run --rm --entrypoint /bin/bash image -lc '
  wine --version
  ls -l /opt/webview2/msedge.dll
  ls /wine/drive_c/windows/Fonts
  fc-match "Microsoft YaHei"
'
```
