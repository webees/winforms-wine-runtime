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
    """Return the overall score and one 100-point row per dimension."""
    rows: list[tuple[str, int, int, str]] = []

    def add(name: str, points: int, maximum: int, detail: str) -> None:
        rows.append((name, points, maximum, detail))

    ok = bool(report.get("selftest_ok"))
    steps = int(num(report.get("selftest_steps"), 0))
    selftest = 100 if steps >= 4 else 50
    add("self-test", selftest if ok else 0, 100, f"{steps} steps, ok={ok}")

    anon = int(num(report.get("anon_status"), 0))
    add("basic auth", 100 if anon == 401 else 0, 100, f"anonymous HTTP {anon}")
    guard = report.get("auth_guard") == "ok"
    guard_text = ("refuses to start without a password" if guard
                  else "started without a password")
    add("auth guard", 100 if guard else 0, 100, guard_text)
    tls_ok = (int(num(report.get("tls_status"), 0)) == 200
              and int(num(report.get("plain_on_tls_port"), 0)) != 200)
    tls_text = ("HTTPS 200, plaintext rejected" if tls_ok
                else "TLS listener misconfigured")
    add("TLS default", 100 if tls_ok else 0, 100, tls_text)

    start_ms = int(num(report.get("start_ms"), 10**9))
    add("cold start", band(start_ms, [(10_000, 100), (20_000, 50)]), 100,
        f"{start_ms / 1000:.1f} s to desktop")
    app_ms = int(num(report.get("app_ms"), 10**9))
    add("first window", band(app_ms, [(25_000, 100), (40_000, 50)]), 100,
        f"{app_ms / 1000:.1f} s to app window")
    rss_kb = int(num(report.get("idle_rss_kb"), 10**9))
    add("idle memory",
        band(rss_kb, [(350 * KIB_PER_MIB, 100), (600 * KIB_PER_MIB, 50)]), 100,
        f"{rss_kb / KIB_PER_MIB:.0f} MiB container")

    size = int(num(report.get("size_bytes"), 10**13))
    add("image size",
        band(size, [(4.5 * GIB, 100), (5.5 * GIB, 60), (6.5 * GIB, 30)]),
        100, f"{size / GIB:.2f} GiB")

    x_ok = report.get("x_display") == "yes"
    add("desktop", 100 if x_ok else 0, 100,
        "X display responds" if x_ok else "X display unreachable")

    return sum(points for _, points, _, _ in rows) // len(rows), rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--min", type=int, default=90)
    parser.add_argument("--json", action="store_true", help="print a machine-readable result")
    args = parser.parse_args()

    report = json.loads(args.report.read_text())
    total, rows = score(report)
    grades = ((90, "A"), (75, "B"), (60, "C"))
    grade = next((letter for floor, letter in grades if total >= floor), "D")

    if args.json:
        breakdown = [
            {"name": n, "points": p, "max": m, "detail": d}
            for n, p, m, d in rows
        ]
        print(json.dumps({"score": total, "grade": grade, "breakdown": breakdown}))
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
