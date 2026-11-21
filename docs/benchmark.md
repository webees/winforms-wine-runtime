# Benchmark and score

The runtime is measured by `scripts/bench.sh` and graded by `scripts/score.py`.
Both run against a built image; the demo target is required because the
self-test is part of the score. Engineering quality is a separate 100-point
gate in [docs/quality.md](quality.md); releases require both — quality at 100 and
performance at least 90, with 100 as the target.

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

Every dimension is scored out of **100**; the overall score is the mean of the
nine dimensions, so 100 requires all nine at 100. The score is a release gate:
below 90 fails.

| Dimension | Full marks | Partial |
|---|---|---|
| Self-test | 4/4 steps pass | 0 if any step fails; 50 if fewer than 4 steps are recorded |
| Basic auth | anonymous request returns 401 | – |
| Auth guard | container refuses to start without a password | – |
| TLS default | HTTPS 200 and plaintext rejected | – |
| Cold start | ≤ 10 s to HTTP 200 | 50 at ≤ 20 s |
| First window | ≤ 25 s to a visible application window | 50 at ≤ 40 s |
| Idle memory | ≤ 350 MiB per container | 50 at ≤ 600 MiB |
| Image size | ≤ 2.0 GiB | 60 at ≤ 3.0 GiB, 30 at ≤ 4.0 GiB |
| Desktop | X display answers | – |

A: ≥ 90, B: ≥ 75, C: ≥ 60, D: below.

Any failure of the self-test is a hard failure regardless of the total.

## Baseline

Measured on the reference host (12 vCPU, no GPU), Ubuntu 26.04 / Wine 10.0 /
KasmVNC 1.5.2 / WebView2 135.0.3179.98, demo image:

| Metric | Baseline | Notes |
|---|---|---|
| Image size | 1.13 GiB | `du -sbx /`, default trim flags |
| Cold start | ~0.4 s | until authenticated HTTP 200; warm page cache |
| First window | 2–7 s | Xvfb + Wine + first WinForms window; depends on page cache |
| Idle memory | ~150 MiB | KasmVNC + Wine + idle self-test; the full-mark ceiling is 350 MiB |
| Self-test | 4/4, 10–15 s | `webview2` dominates |
| Score | 100/100 (A) | |

Last verified 2026-11-22: 366 ms cold start, 2.3 s to the app window, 143 MiB
idle RSS, 1.13 GiB image.

## Repository baseline

`make baseline` prints the tracked tree so changes are comparable:

| Metric | Value |
|---|---|
| Tracked files | 48 |
| Lines | 4.95 k |
| Bytes | 192 KB |
| Largest file | `scripts/quality.py` (31 KB) |

Numbers vary with host CPU, page cache and image storage; compare within one
host, not across machines.
