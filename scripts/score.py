#!/usr/bin/env python3
"""Score a bench.json report with the rubric published in docs/benchmark.md.

    ./scripts/score.py bench.json [--min 90]

Exits non-zero on a hard failure (self-test) or a score below --min.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

GIB = 1024**3
KIB_PER_MIB = 1024


def band(value: float, limits: list[tuple[float, int]]) -> int:
    """Return the points of the first limit the value satisfies."""
    for limit, points in limits:
        if value <= limit:
            return points
    return 0


def num(value: object, default: float) -> float:
    """Coerce a JSON value to a number, ignoring null and junk."""
    try:
        return float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default


def score(report: dict) -> tuple[int, list[tuple[str, int, int, str]]]:
    rows: list[tuple[str, int, int, str]] = []

    def add(name: str, points: int, maximum: int, detail: str) -> None:
        rows.append((name, points, maximum, detail))

    ok = bool(report.get("selftest_ok"))
    steps = int(num(report.get("selftest_steps"), 0))
    selftest = 40 if steps >= 4 else 20
    add("self-test", selftest if ok else 0, 40, f"{steps} steps, ok={ok}")

    anon = int(num(report.get("anon_status"), 0))
    add("basic auth", 8 if anon == 401 else 0, 8, f"anonymous HTTP {anon}")
    guard = report.get("auth_guard") == "ok"
    add("auth guard", 6 if guard else 0, 6, "refuses to start without a password" if guard else "started without a password")
    tls_ok = int(num(report.get("tls_status"), 0)) == 200 and int(num(report.get("plain_on_tls_port"), 0)) != 200
    add("TLS default", 6 if tls_ok else 0, 6, "HTTPS 200, plaintext rejected" if tls_ok else "TLS listener misconfigured")

    start_ms = int(num(report.get("start_ms"), 10**9))
    add("cold start", band(start_ms, [(10_000, 8), (20_000, 4)]), 8, f"{start_ms / 1000:.1f} s to desktop")
    app_ms = int(num(report.get("app_ms"), 10**9))
    add("first window", band(app_ms, [(25_000, 10), (40_000, 5)]), 10, f"{app_ms / 1000:.1f} s to app window")
    rss_kb = int(num(report.get("idle_rss_kb"), 10**9))
    add("idle memory", band(rss_kb, [(350 * KIB_PER_MIB, 7), (600 * KIB_PER_MIB, 4)]), 7,
        f"{rss_kb / KIB_PER_MIB:.0f} MiB container")

    size = int(num(report.get("size_bytes"), 10**13))
    add("image size", band(size, [(4.5 * GIB, 10), (5.5 * GIB, 6), (6.5 * GIB, 3)]), 10, f"{size / GIB:.2f} GiB")

    x_ok = report.get("x_display") == "yes"
    add("desktop", 5 if x_ok else 0, 5, "X display responds" if x_ok else "X display unreachable")

    return sum(points for _, points, _, _ in rows), rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--min", type=int, default=90)
    parser.add_argument("--json", action="store_true", help="print a machine-readable result")
    args = parser.parse_args()

    report = json.loads(args.report.read_text())
    total, rows = score(report)
    grade = "A" if total >= 90 else "B" if total >= 75 else "C" if total >= 60 else "D"

    if args.json:
        print(json.dumps({"score": total, "grade": grade,
                          "breakdown": [{"name": n, "points": p, "max": m, "detail": d} for n, p, m, d in rows]}))
    else:
        print(f"{'dimension':<16}{'points':>8}  detail")
        for name, points, maximum, detail in rows:
            print(f"{name:<16}{points:>4}/{maximum:<3}  {detail}")
        print(f"{'total':<16}{total:>4}/100  grade {grade}")

    if not report.get("selftest_ok"):
        print("score: FAILED (self-test)", file=sys.stderr)
        return 1
    if total < args.min:
        print(f"score: FAILED ({total} < {args.min})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
