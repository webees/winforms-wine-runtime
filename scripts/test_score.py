#!/usr/bin/env python3
"""Boundary tests for the rubric in scripts/score.py.

    python3 scripts/test_score.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from score import GIB, KIB_PER_MIB, score  # noqa: E402

PERFECT = {
    "image": "test:1",
    "platform": "linux/amd64",
    "cpus": 8,
    "size_bytes": int(2.6 * GIB),
    "start_ms": 900,
    "app_ms": 2_300,
    "auth_status": 200,
    "anon_status": 401,
    "tls_status": 200,
    "plain_on_tls_port": 0,
    "x_display": "yes",
    "idle_rss_kb": 230 * KIB_PER_MIB,
    "auth_guard": "ok",
    "selftest_ok": True,
    "selftest_steps": 4,
    "selftest_ms": 14_000,
}


def points(**overrides: object) -> dict[str, int]:
    report = dict(PERFECT, **overrides)
    _, rows = score(report)
    return {name: got for name, got, _, _ in rows}


class RubricTest(unittest.TestCase):
    def test_perfect_report_scores_100(self) -> None:
        self.assertEqual(score(dict(PERFECT))[0], 100)

    def test_missing_keys_never_crash(self) -> None:
        total, rows = score({})
        self.assertEqual(total, 0)
        self.assertEqual(len(rows), 9)

    def test_null_values_never_crash(self) -> None:
        _, rows = score({key: None for key in PERFECT})
        self.assertEqual(len(rows), 9)

    def test_self_test_is_a_hard_dimension(self) -> None:
        self.assertEqual(points()["self-test"], 40)
        self.assertEqual(points(selftest_steps=3)["self-test"], 20)
        self.assertEqual(points(selftest_ok=False)["self-test"], 0)

    def test_basic_auth(self) -> None:
        self.assertEqual(points()["basic auth"], 8)
        self.assertEqual(points(anon_status=200)["basic auth"], 0)

    def test_auth_guard(self) -> None:
        self.assertEqual(points()["auth guard"], 6)
        self.assertEqual(points(auth_guard="")["auth guard"], 0)

    def test_tls_default(self) -> None:
        self.assertEqual(points()["TLS default"], 6)
        self.assertEqual(points(plain_on_tls_port=200)["TLS default"], 0)
        self.assertEqual(points(tls_status=0)["TLS default"], 0)

    def test_cold_start_bands(self) -> None:
        self.assertEqual(points(start_ms=10_000)["cold start"], 8)
        self.assertEqual(points(start_ms=10_001)["cold start"], 4)
        self.assertEqual(points(start_ms=20_001)["cold start"], 0)

    def test_first_window_bands(self) -> None:
        self.assertEqual(points(app_ms=25_000)["first window"], 10)
        self.assertEqual(points(app_ms=25_001)["first window"], 5)
        self.assertEqual(points(app_ms=40_001)["first window"], 0)

    def test_idle_memory_bands(self) -> None:
        self.assertEqual(points(idle_rss_kb=350 * KIB_PER_MIB)["idle memory"], 7)
        self.assertEqual(points(idle_rss_kb=350 * KIB_PER_MIB + 1)["idle memory"], 4)
        self.assertEqual(points(idle_rss_kb=600 * KIB_PER_MIB + 1)["idle memory"], 0)

    def test_image_size_bands(self) -> None:
        self.assertEqual(points(size_bytes=int(4.5 * GIB))["image size"], 10)
        self.assertEqual(points(size_bytes=int(4.5 * GIB) + 1)["image size"], 6)
        self.assertEqual(points(size_bytes=int(5.5 * GIB) + 1)["image size"], 3)
        self.assertEqual(points(size_bytes=int(6.5 * GIB) + 1)["image size"], 0)

    def test_desktop(self) -> None:
        self.assertEqual(points()["desktop"], 5)
        self.assertEqual(points(x_display="no")["desktop"], 0)


class CliTest(unittest.TestCase):
    script = Path(__file__).resolve().parent / "score.py"

    def run_score(self, report: dict) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile("w", suffix=".json") as handle:
            json.dump(report, handle)
            handle.flush()
            return subprocess.run(
                [sys.executable, str(self.script), handle.name],
                capture_output=True,
                text=True,
                check=False,
            )

    def test_good_report_passes(self) -> None:
        self.assertEqual(self.run_score(PERFECT).returncode, 0)

    def test_failed_self_test_blocks_release(self) -> None:
        result = self.run_score(dict(PERFECT, selftest_ok=False))
        self.assertEqual(result.returncode, 1)
        self.assertIn("self-test", result.stderr)

    def test_score_below_min_fails(self) -> None:
        result = self.run_score(dict(PERFECT, anon_status=200, auth_guard=""))
        self.assertEqual(result.returncode, 1)
        self.assertIn("score: FAILED", result.stderr)


if __name__ == "__main__":
    unittest.main()
