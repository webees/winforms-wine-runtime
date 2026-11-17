# Benchmark and score

The runtime is measured by `scripts/bench.sh` and graded by `scripts/score.py`.
Both run against a built image; the demo target is required because the
self-test is part of the score.

```bash
make build                     # runtime + demo images at :dev / :dev-demo
make bench                     # writes bench.json
make score                     # exit non-zero below 90

# keep the self-test report and screenshots next to the numbers
./scripts/bench.sh --out bench.json --evidence evidence
```

The report is plain JSON, so a baseline can be stored and compared in review.
`ci.yml` and `release.yml` run exactly this and fail below 90 points.

## What is measured

| Metric | How | Why it matters |
|---|---|---|
| `image`, `platform`, `cpus` | image under test, and host of the run | Numbers are only comparable for the same image, platform and CPU class |
| `size_bytes` | `du -sbx /` inside the image | Registry storage, independent of the host image store |
| `start_ms` | `docker run -d` until authenticated HTTP 200 | Time until the web client can be opened |
| `app_ms` | until the application maps a visible X window | Time until the first usable frame |
| `auth_status`, `anon_status` | `curl` with and without credentials | The desktop answers when authenticated and refuses anonymous access |
| `auth_guard` | run without `VNC_PASSWORD` | Misconfiguration must fail closed |
| `tls_status` | HTTPS on the default configuration | Credentials never cross the wire in clear text |
| `plain_on_tls_port` | plain HTTP against the TLS port | Must not be 200 |
| `x_display` | `xdpyinfo` inside the container | The X server behind KasmVNC is alive |
| `idle_rss_kb` | `docker stats` for the running container | Memory cost of an idle session |
| `selftest_ok`, `selftest_steps`, `selftest_ms` | in-image `--selftest` | Wine, .NET, WebView2, SunnyUI and Magick.NET actually work |

## Scoring

100 points, higher is better. The score is a release gate: below 90 fails.

| Dimension | Max | Full marks | Partial |
|---|---|---|---|
| Self-test | 40 | 4/4 steps pass | 0 if any step fails; 20 if fewer than 4 steps are recorded |
| Basic auth | 8 | anonymous request returns 401 | – |
| Auth guard | 6 | container refuses to start without a password | – |
| TLS default | 6 | HTTPS 200 and plaintext rejected | – |
| Cold start | 8 | ≤ 10 s to HTTP 200 | 4 at ≤ 20 s |
| First window | 10 | ≤ 25 s to a visible application window | 5 at ≤ 40 s |
| Idle memory | 7 | ≤ 350 MiB per container | 4 at ≤ 600 MiB |
| Image size | 10 | ≤ 4.5 GiB | 6 at ≤ 5.5 GiB, 3 at ≤ 6.5 GiB |
| Desktop | 5 | X display answers | – |

A: ≥ 90, B: ≥ 75, C: ≥ 60, D: below.

Any failure of the self-test is a hard failure regardless of the total.

## Baseline

Measured on the reference host (12 vCPU, no GPU), Ubuntu 26.04 / Wine 10.0 /
KasmVNC 1.5.2 / WebView2 135.0.3179.98, demo image:

| Metric | Baseline | Notes |
|---|---|---|
| Image size | 2.58 GiB | `du -sbx /`, `WINE64_ONLY=1`, `KASMVNC_VIDEO=1` |
| Cold start | ~1 s | until authenticated HTTP 200; warm page cache |
| First window | 2–7 s | Xvfb + Wine + first WinForms window; depends on page cache |
| Idle memory | 200–300 MiB | KasmVNC + Wine + idle self-test; the full-mark ceiling is 350 MiB |
| Self-test | 4/4, 10–15 s | `webview2` dominates |
| Score | 100/100 (A) | |

## Repository baseline

`make baseline` prints the tracked tree so changes are comparable:

| Metric | Value |
|---|---|
| Tracked files | 49 |
| Lines | ~4.0 k |
| Bytes | ~152 KB |
| Largest file | `README.md` (~11 KB) |

Numbers vary with host CPU, page cache and image storage; compare within one
host, not across machines.
