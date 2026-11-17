# Ports and volumes

## Ports

| Container port | Env | Published by default | Notes |
|---|---|---|---|
| `6901/tcp` | `KASMVNC_PORT` | yes | KasmVNC web client, WebSocket and desktop |

KasmVNC serves the static client, the WebSocket and the RFB stream on the same
port. A reverse proxy in front of it must forward `Upgrade`/`Connection` headers
and allow long-lived connections; otherwise the page loads and the canvas stays
black. It also needs to accept the self-signed certificate when `KASMVNC_SSL=1`,
or you set `KASMVNC_SSL=0` and terminate TLS at the proxy.

The web endpoint is protected by HTTP basic auth derived from `VNC_PASSWORD`.
Because an open desktop is an obvious foot-gun, the entrypoint refuses to start
without a password unless you opt out explicitly:

```bash
# fails fast
docker run -e ENABLE_VNC=1 image

# works
docker run -e ENABLE_VNC=1 -e VNC_PASSWORD=secret image

# deliberate, unauthenticated; only behind an authenticating proxy
docker run -e ENABLE_VNC=1 -e KASMVNC_ALLOW_NO_AUTH=1 image
```

`KASMVNC_SSL=1` (the default) encrypts the session between the browser and the
container, which is what you want when `6901` is published directly. Set it to
`0` only when a proxy terminates TLS.

There is **no second listener**: KasmVNC multiplexes the web client, the
WebSocket and RFB on `6901`, and `-SecurityTypes None` means the RFB stream is
only reachable through the authenticated HTTP endpoint. Do not publish `5900`;
nothing listens there.

## Reverse proxies and Cloudflare Access

Two patterns work, and they are mutually exclusive:

| Front end | Container settings | Notes |
|---|---|---|
| TLS-terminating proxy that forwards `Authorization` untouched | `KASMVNC_SSL=0`, `VNC_PASSWORD=…` | Proxy must accept the `Upgrade`/`Connection` headers and allow long-lived connections. |
| Cloudflare Access, oauth2-proxy, Authelia, or any proxy that **consumes** `Authorization` | `KASMVNC_SSL=0`, `KASMVNC_ALLOW_NO_AUTH=1` | The proxy is the only gate; never publish `6901` when using this pattern. |

A proxy that strips or rewrites `Authorization` while the container still has
basic auth enabled will make every request fail with `401`. KasmVNC also
blacklists an address for 10 seconds after 5 consecutive authentication
failures, which parallel asset requests can trigger — that is upstream
behaviour, not an image bug.

### Applications that open ports

WinForms applications occasionally host an HTTP endpoint. Those ports are not
declared by this image and are not covered by `EXPOSE`; add `-p` (or a
`Service`) for the specific port your application binds. For anything
UDP-based, or for applications that expect to *receive* arbitrary inbound ports,
use `--network host`.

## Volumes

| Path | Persist? | Why |
|---|---|---|
| `/wine` | Yes | Prefix: registry, `C:\` profile, fonts, WebView2 profile, per-user settings |
| `/data` | Yes | Application data; also the recommended output directory for files |
| `/app` | No | Immutable application payload |

### First start

An empty `/wine` is initialised automatically. Expect roughly 20 s of extra
start-up before the application window appears. The healthcheck only probes the
desktop, so it can report healthy while that first-boot copy is still running.

### Upgrades

Wine prefixes are forward compatible within a major series but not guaranteed
across major upgrades. After a major Wine bump, either start from an empty
volume or keep the old prefix and test first; a corrupted prefix shows up as
missing `gdiplus.dll`, failing `Bitmap.Save()`, or applications that start once
and then crash.

`wineboot -u` only runs when `/wine/system.reg` is missing. The CJK font
mappings and the MSVC DLLs are re-applied on every start, so a prefix created by
an earlier CalVer image is refreshed without deleting user data.

### Permissions

The container runs as root because Wine writes throughout the prefix. Bind
mounts must therefore be writable by UID 0, or owned by a user that maps to it:

```bash
mkdir -p data && chown -R 0:0 data
docker run -v "$PWD/data:/data" ...
```

## Recommended compose

```yaml
services:
  app:
    # Pin a CalVer release; `2` and `latest` are moving aliases.
    # Build your own image from it and COPY the application into /app.
    image: ghcr.io/webees/winforms-wine-runtime:2026.11.17
    ports: ["6901:6901"]
    environment:
      ENABLE_VNC: "1"
      VNC_PASSWORD: ${VNC_PASSWORD:?set VNC_PASSWORD}
      SCREEN: 1920x1080x24
    volumes:
      - wine-prefix:/wine
      - app-data:/data
    shm_size: 1gb
    restart: unless-stopped

volumes:
  wine-prefix:
  app-data:
```

`shm_size: 1gb` matters: Chromium allocates shared memory for its renderer and
the default 64 MB `/dev/shm` causes renderer crashes or blank pages.

Start with 1 CPU / 2 GiB requested and 2 CPU / 4 GiB as the limit. An idle
session uses 200–300 MiB, but a WebView2 page with large images, or Magick.NET
decoding them, can multiply that.
