# Network tuning

KasmVNC carries the desktop over one TCP port (HTTPS + WebSocket). End-to-end
latency is the sum of:

1. network RTT (usually the dominant term on intercontinental links),
2. server-side encoding time per changed region,
3. the frame-rate cap (`1 / KASMVNC_FRAME_RATE` worst case),
4. browser decode and paint.

Nothing in the image changes kernel settings; a container cannot do that
without extra privileges. Tune the host once and the image knobs per workload.

## Image knobs

| Variable | Default | Effect |
|---|---|---|
| `SCREEN` | `1600x900x24` | Fewer pixels is the cheapest bandwidth win |
| `KASMVNC_FRAME_RATE` | `30` | Upper bound on updates per second; KasmVNC's own default is 60 |
| `KASMVNC_QUALITY_MIN` / `KASMVNC_QUALITY_MAX` | `7` / `8` | JPEG/WebP quality, 0-9; higher is sharper and larger |
| `KASMVNC_PREFER_BANDWIDTH` | `0` | `1` lets the encoder trade quality for bytes |
| `KASMVNC_RECT_THREADS` | `0` | Encoder threads, `0` = automatic |
| `KASMVNC_VIDEO_CODEC` | `auto` | `auto` or an explicit `h264` / `h265` / `av1` variant |

Presets:

| Link | Settings |
|---|---|
| LAN, < 20 ms | `KASMVNC_FRAME_RATE=60 KASMVNC_QUALITY_MIN=8 KASMVNC_QUALITY_MAX=9` |
| Internet, 30-150 ms | defaults |
| Lossy or metered | `KASMVNC_FRAME_RATE=15 KASMVNC_PREFER_BANDWIDTH=1 KASMVNC_QUALITY_MAX=7` + `SCREEN=1280x720x24` |

`KASMVNC_FRAME_RATE` only caps updates; a static WinForms window sends
nothing, so a higher cap costs nothing while the UI is idle.

## UDP transport

KasmVNC 1.5 can negotiate an optional WebRTC/UDP data channel next to the
WebSocket. It needs ICE/STUN and a UDP path the browser can reach; a NAT'd
container does not provide that by default, and the desktop does not depend on
it. Treat it as experimental: keep the TCP WebSocket as the supported path.

## Host TCP stack

For links with more than ~40 ms RTT, BBR with `fq` keeps throughput up without
growing buffers (bufferbloat), and MTU probing avoids PMTU black holes:

```ini
# /etc/sysctl.d/90-wfr-net.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_mtu_probing = 1
```

```bash
sysctl --system
sysctl -n net.ipv4.tcp_congestion_control   # bbr
```

Containers on the default bridge use the host stack, so this is a one-time
host change. `net.ipv4.tcp_congestion_control` is namespaced and can also be
set per container with `sysctls:` once the `tcp_bbr` module is loaded.

## MTU and tunnels

Tunnels (WireGuard, Tailscale) reduce the usable MTU; a mismatch shows up as
small requests working while large frames stall or reset.

- Tailscale: 1280 by default; do not raise it above the underlay limit.
- WireGuard: 1420 for a 1500-byte underlay.
- Diagnose with `ping -M do -s 1400 <host>`; lower the size until it passes.
- `net.ipv4.tcp_mtu_probing=1` handles silent PMTU black holes.
- On a router in the path:
  `iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu`.

## Reverse proxy and tunnel in front

Prefer publishing 6901 directly with the built-in TLS. When a proxy is
required, it must not buffer or shorten the WebSocket:

```nginx
location / {
    proxy_pass https://127.0.0.1:6901;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_buffering off;
    proxy_request_buffering off;
}
```

Cloudflare Tunnel works because it forwards WebSocket upgrades; check the
tunnel's idle timeout and keep it above the client's keep-alive interval.
Terminating TLS at the proxy means `KASMVNC_SSL=0` inside the container.

## Verify

```bash
mtr -rwzbc 20 <host>
curl -sS -o /dev/null -w 'connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer}\n' \
  https://<host>:6901/
ss -tin state established '( dport = :6901 )'  # client: rtt, cwnd, retransmits
ss -tn state established '( sport = :6901 )'   # inside the container
```
