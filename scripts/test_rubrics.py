#!/usr/bin/env python3
"""Boundary tests for both rubrics: scripts/score.py and scripts/quality.py.

    python3 scripts/test_rubrics.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import quality
from score import GIB, KIB_PER_MIB, score

PERFECT = {
    "image": "test:1",
    "platform": "linux/amd64",
    "cpus": 8,
    "size_bytes": int(1.2 * GIB),
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
    _, rows = score(dict(PERFECT, **overrides))
    return {name: got for name, got, _, _ in rows}


class PerformanceRubricTest(unittest.TestCase):
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
        self.assertEqual(points()["self-test"], 100)
        self.assertEqual(points(selftest_steps=3)["self-test"], 50)
        self.assertEqual(points(selftest_ok=False)["self-test"], 0)

    def test_basic_auth(self) -> None:
        self.assertEqual(points()["basic auth"], 100)
        self.assertEqual(points(anon_status=200)["basic auth"], 0)

    def test_auth_guard(self) -> None:
        self.assertEqual(points()["auth guard"], 100)
        self.assertEqual(points(auth_guard="")["auth guard"], 0)

    def test_tls_default(self) -> None:
        self.assertEqual(points()["TLS default"], 100)
        self.assertEqual(points(plain_on_tls_port=200)["TLS default"], 0)
        self.assertEqual(points(tls_status=0)["TLS default"], 0)

    def test_cold_start_bands(self) -> None:
        self.assertEqual(points(start_ms=10_000)["cold start"], 100)
        self.assertEqual(points(start_ms=10_001)["cold start"], 50)
        self.assertEqual(points(start_ms=20_001)["cold start"], 0)

    def test_first_window_bands(self) -> None:
        self.assertEqual(points(app_ms=25_000)["first window"], 100)
        self.assertEqual(points(app_ms=25_001)["first window"], 50)
        self.assertEqual(points(app_ms=40_001)["first window"], 0)

    def test_idle_memory_bands(self) -> None:
        self.assertEqual(points(idle_rss_kb=350 * KIB_PER_MIB)["idle memory"], 100)
        self.assertEqual(points(idle_rss_kb=350 * KIB_PER_MIB + 1)["idle memory"], 50)
        self.assertEqual(points(idle_rss_kb=600 * KIB_PER_MIB + 1)["idle memory"], 0)

    def test_image_size_bands(self) -> None:
        self.assertEqual(points(size_bytes=2 * GIB)["image size"], 100)
        self.assertEqual(points(size_bytes=2 * GIB + 1)["image size"], 60)
        self.assertEqual(points(size_bytes=3 * GIB + 1)["image size"], 30)
        self.assertEqual(points(size_bytes=4 * GIB + 1)["image size"], 0)

    def test_desktop(self) -> None:
        self.assertEqual(points()["desktop"], 100)
        self.assertEqual(points(x_display="no")["desktop"], 0)

    def test_cli_good_report_passes(self) -> None:
        self.assertEqual(self.run_score(PERFECT).returncode, 0)

    def test_cli_failed_self_test_blocks_release(self) -> None:
        result = self.run_score(dict(PERFECT, selftest_ok=False))
        self.assertEqual(result.returncode, 1)
        self.assertIn("self-test", result.stderr)

    def test_cli_score_below_min_fails(self) -> None:
        result = self.run_score(dict(PERFECT, anon_status=200, auth_guard=""))
        self.assertEqual(result.returncode, 1)
        self.assertIn("score: FAILED", result.stderr)

    def run_score(self, report: dict) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile("w", suffix=".json") as handle:
            json.dump(report, handle)
            handle.flush()
            return subprocess.run(
                [sys.executable, str(Path(__file__).resolve().parent / "score.py"),
                 handle.name],
                capture_output=True,
                text=True,
                check=False,
            )


class QualityCheckTest(unittest.TestCase):
    def test_points_are_additive(self) -> None:
        dim = quality.Dimension("sample")
        dim.checks.append(quality.Check("a", "first", 4, True))
        dim.checks.append(quality.Check("b", "second", 6, False))
        self.assertEqual(dim.earned, 4)
        self.assertEqual(dim.budget, 10)

    def test_dimension_score_is_normalised(self) -> None:
        dim = quality.Dimension("sample")
        dim.checks.append(quality.Check("a", "pass", 3, True))
        dim.checks.append(quality.Check("b", "fail", 1, False))
        self.assertEqual(dim.score, 75)

    def test_parity_mapping_is_unique(self) -> None:
        english = [pair[0] for pair in quality.README_SECTIONS]
        chinese = [pair[1] for pair in quality.README_SECTIONS]
        self.assertEqual(len(english), len(set(english)))
        self.assertEqual(len(chinese), len(set(chinese)))

    def test_h2_ignores_deeper_headings(self) -> None:
        body = "# title\n## One\ntext\n### skip\n## Two\n"
        self.assertEqual(quality.h2(body), ["One", "Two"])

    def test_dockerfile_arg_reads_defaults(self) -> None:
        text = "ARG UBUNTU_VERSION=26.04\nARG BASE=ubuntu:${UBUNTU_VERSION}\n"
        self.assertEqual(quality.dockerfile_arg(text, "UBUNTU_VERSION"), "26.04")
        self.assertEqual(quality.dockerfile_arg(text, "MISSING"), "")

    def test_latest_release_is_calver(self) -> None:
        self.assertRegex(quality.latest_release(),
                         r"^\d{4}\.\d{2}\.\d{2}(\.\d+)?$")

    def test_every_dimension_is_weighted(self) -> None:
        data = quality.report()
        self.assertEqual(len(data["dimensions"]), len(quality.BUILDERS))
        for dim in data["dimensions"]:
            self.assertGreater(len(dim["checks"]), 0, dim["name"])
            self.assertEqual(dim["score"], 100, dim["name"])


if __name__ == "__main__":
    unittest.main()
