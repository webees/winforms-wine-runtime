# Ports and volumes

## Ports

| Container port | Env | Published by default | Notes |
|---|---|---|---|
| `6080/tcp` | `NOVNC_PORT` | yes | noVNC static site and WebSocket |
| `5900/tcp` | `VNC_PORT` | no | Native VNC, bound to `127.0.0.1` |

noVNC is a static page plus a WebSocket. Any reverse proxy in front of it must
forward `Upgrade`/`Connection` headers and allow long-lived connections;
otherwise the page loads and the canvas stays black.

The VNC server has no password unless `VNC_PASSWORD` is set. Because that is an
obvious foot-gun, the entrypoint refuses to bind a non-loopback address without
a password:

```bash
# fails fast
docker run -e ENABLE_VNC=1 -e VNC_LISTEN=0.0.0.0 image

# works
docker run -e ENABLE_VNC=1 -e VNC_LISTEN=0.0.0.0 -e VNC_PASSWORD=secret image
```

If you need to reach the desktop from the network, prefer publishing `6080`
through a TLS-terminating proxy over exposing `5900`.

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
start-up and a healthcheck that reports `starting` until the prefix exists.

### Upgrades

Wine prefixes are forward compatible within a major series but not guaranteed
across major upgrades. After a major Wine bump, either start from an empty
volume or keep the old prefix and test first; a corrupted prefix shows up as
missing `gdiplus.dll`, failing `Bitmap.Save()`, or applications that start once
and then crash.

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
    image: ghcr.io/webees/winforms-wine-runtime:1
    ports: ["6080:6080"]
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
