#!/usr/bin/env python3
"""Boundary tests for the rubric in scripts/quality.py."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import quality


class CheckTests(unittest.TestCase):
    def test_points_are_additive(self) -> None:
        dim = quality.Dimension("sample")
        dim.checks.append(quality.Check("a", "first", 4, True))
        dim.checks.append(quality.Check("b", "second", 6, False))
        self.assertEqual(dim.earned, 4)
        self.assertEqual(dim.budget, 10)

    def test_parity_mapping_is_unique(self) -> None:
        english = [pair[0] for pair in quality.README_SECTIONS]
        chinese = [pair[1] for pair in quality.README_SECTIONS]
        self.assertEqual(len(english), len(set(english)))
        self.assertEqual(len(chinese), len(set(chinese)))

    def test_dimension_score_is_normalised(self) -> None:
        dim = quality.Dimension("sample")
        dim.checks.append(quality.Check("a", "pass", 3, True))
        dim.checks.append(quality.Check("b", "fail", 1, False))
        self.assertEqual(dim.score, 75)


class ParsingTests(unittest.TestCase):
    def test_h2_ignores_deeper_headings(self) -> None:
        body = "# title\n## One\ntext\n### skip\n## Two\n"
        self.assertEqual(quality.h2(body), ["One", "Two"])

    def test_dockerfile_arg_reads_defaults(self) -> None:
        text = "ARG UBUNTU_VERSION=26.04\nARG BASE=ubuntu:${UBUNTU_VERSION}\n"
        self.assertEqual(quality.dockerfile_arg(text, "UBUNTU_VERSION"), "26.04")
        self.assertEqual(quality.dockerfile_arg(text, "MISSING"), "")

    def test_latest_release_is_calver(self) -> None:
        release = quality.latest_release()
        self.assertRegex(release, r"^\d{4}\.\d{2}\.\d{2}(\.\d+)?$")


class RubricTests(unittest.TestCase):
    def test_budget_is_one_hundred(self) -> None:
        data = quality.report()
        for dim in data["dimensions"]:
            self.assertGreater(dim["budget"], 0, dim["name"])
        self.assertEqual(sum(dim["budget"] for dim in data["dimensions"]), 100)

    def test_repository_scores_one_hundred(self) -> None:
        data = quality.report()
        failures = [
            f"{dim['name']}.{item['id']}: {item['detail']}"
            for dim in data["dimensions"]
            for item in dim["checks"]
            if not item["ok"]
        ]
        self.assertEqual(data["score"], 100, "\n".join(failures))
        for dim in data["dimensions"]:
            self.assertEqual(dim["score"], 100, dim["name"])


if __name__ == "__main__":
    unittest.main()
