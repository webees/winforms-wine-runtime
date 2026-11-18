#!/usr/bin/env python3
"""Grade repository quality against the rubric published in docs/quality.md.

    ./scripts/quality.py [--min 100] [--json quality.json]

The audit is offline and deterministic: it reads the checkout only, never the
network, Docker or a built image. Runtime performance is graded separately by
``scripts/score.py``; this rubric covers everything that can be verified from
source. Exit status is non-zero when the score is below ``--min``.
"""

from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from functools import cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".ruff_cache", "__pycache__", "bin", "obj", "publish",
             "node_modules"}
TEXT_SUFFIXES = {
    "",
    ".cfg",
    ".json",
    ".md",
    ".py",
    ".sh",
    ".toml",
    ".txt",
    ".yaml",
    ".yml",
}


@dataclass(frozen=True)
class Check:
    """One scored assertion."""

    check_id: str
    title: str
    points: int
    ok: bool
    detail: str = ""


@dataclass
class Dimension:
    """A weighted group of checks."""

    name: str
    checks: list[Check] = field(default_factory=list)

    @property
    def earned(self) -> int:
        return sum(c.points for c in self.checks if c.ok)

    @property
    def budget(self) -> int:
        return sum(c.points for c in self.checks)


@cache
def read(rel: str) -> str:
    """Return a repository file as text; cached because checks overlap."""
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def sources(*patterns: str) -> list[Path]:
    found: set[Path] = set()
    for pattern in patterns:
        found.update(p for p in ROOT.glob(pattern) if p.is_file())
    return sorted(found)


def tracked_text() -> list[Path]:
    out = []
    for path in ROOT.rglob("*"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.name in {".DS_Store", "Thumbs.db"}:
            continue
        if path.is_file() and path.suffix in TEXT_SUFFIXES and path.stat().st_size < 1 << 20:
            out.append(path)
    return sorted(out)


def latest_release() -> str:
    match = re.search(r"^## \[(\d{4}\.\d{2}\.\d{2}(?:\.\d+)?)\]",
                      read("CHANGELOG.md"), re.M)
    return match.group(1) if match else ""


README_SECTIONS = [
    ("Why", "为什么"),
    ("Quick start", "快速开始"),
    ("Use it for your own application", "用自己的程序"),
    ("Ports", "端口"),
    ("Persistence", "持久化"),
    ("Environment", "环境变量"),
    ("WebView2: one required line of code", "WebView2：必须写的一行代码"),
    ("WebView2 version policy", "WebView2 版本策略"),
    ("What is verified", "已验证"),
    ("Limits", "限制"),
    ("Security", "安全"),
    ("Build arguments", "构建参数"),
    ("Build locally", "本地构建"),
    ("Documentation", "文档"),
    ("License", "许可"),
]


def h2(text: str) -> list[str]:
    return [m.group(1).strip() for m in re.finditer(r"^## +(.+)$", text, re.M)]


def long_lines(paths: list[Path], limit: int) -> list[str]:
    """Return ``file:line`` for every line longer than ``limit``."""
    return [f"{p.name}:{i}" for p in paths for i, line in
            enumerate(p.read_text().splitlines(), 1) if len(line) > limit]


def hygiene() -> Dimension:
    dim = Dimension("hygiene")
    required = [
        "README.md",
        "README.zh-CN.md",
        "LICENSE",
        "SECURITY.md",
        "CONTRIBUTING.md",
        "CODE_OF_CONDUCT.md",
        "CHANGELOG.md",
        "THIRD-PARTY-NOTICES.md",
        ".gitignore",
        ".dockerignore",
        ".editorconfig",
        "Makefile",
    ]
    missing = [name for name in required if not (ROOT / name).is_file()]
    dim.checks.append(Check("files", "required files", 4, not missing,
                            ", ".join(missing) or "all present"))

    junk = [p.name for p in ROOT.iterdir() if p.is_file() and
            (p.suffix in {".png", ".sarif"} or p.name in
             {"report.json", "bench.json", "bench.txt"})]
    dim.checks.append(Check("artifacts", "no generated artifacts", 2,
                            not junk, ", ".join(junk) or "clean"))

    markers = []
    self_referential = {"docs/quality.md", "scripts/quality.py"}
    for path in tracked_text():
        rel = str(path.relative_to(ROOT))
        if rel in self_referential:
            continue
        if path.suffix in {".md", ".sh", ".py", ".yml", ".yaml"} and re.search(
                r"\b(TODO|FIXME|XXX|HACK)\b", path.read_text(errors="replace")):
            markers.append(rel)
    dim.checks.append(Check("markers", "no TODO/FIXME markers", 2,
                            not markers, ", ".join(markers) or "none"))

    dirty = []
    for path in tracked_text():
        if path.name == "quality.json":
            continue
        body = path.read_text(encoding="utf-8", errors="replace")
        if body and (not body.endswith("\n") or "\r\n" in body or any(
                line != line.rstrip() for line in body.splitlines())):
            dirty.append(str(path.relative_to(ROOT)))
    dim.checks.append(Check("whitespace", "clean whitespace", 2,
                            not dirty, ", ".join(dirty[:5]) or "clean"))
    return dim


def shell() -> Dimension:
    dim = Dimension("shell")
    scripts = sources("docker/*.sh", "scripts/*.sh")
    bodies = {p.name: p.read_text() for p in scripts}

    lax = [name for name, body in bodies.items() if "set -euo pipefail" not in body]
    dim.checks.append(Check("strict", "strict mode everywhere", 4,
                            not lax, ", ".join(lax) or f"{len(scripts)} scripts"))
    dim.checks.append(Check("exec", "scripts executable", 2,
                            all(p.stat().st_mode & 0o111 for p in scripts),
                            "all executable"))
    long = long_lines(scripts, 120)
    dim.checks.append(Check("length", "lines <= 120 columns", 2,
                            not long, ", ".join(long[:5]) or "within limit"))
    banned = [name for name, body in bodies.items() if re.search(
        r"\beval\b|curl[^\n]*\|\s*(?:ba)?sh|set \+e", body)]
    dim.checks.append(Check("banned", "no eval or pipe-to-shell", 2,
                            not banned, ", ".join(banned) or "none"))
    noheader = [name for name, body in bodies.items() if
                not re.search(r"^#", "\n".join(body.splitlines()[:3]), re.M)]
    dim.checks.append(Check("header", "documented header", 2,
                            not noheader, ", ".join(noheader) or "all documented"))
    return dim


def python() -> Dimension:
    dim = Dimension("python")
    scripts = sources("scripts/*.py")

    bad = [p.name for p in scripts if not p.read_text().startswith(
        "#!/usr/bin/env python3") or not p.stat().st_mode & 0o111]
    dim.checks.append(Check("entry", "shebang and exec bit", 2,
                            not bad, ", ".join(bad) or f"{len(scripts)} scripts"))
    long = long_lines(scripts, 100)
    dim.checks.append(Check("length", "lines <= 100 columns", 2,
                            not long, ", ".join(long[:5]) or "within limit"))
    bare = [p.name for p in scripts if not ast.get_docstring(ast.parse(p.read_text()))]
    dim.checks.append(Check("docstring", "module docstrings", 2,
                            not bare, ", ".join(bare) or "documented"))
    dim.checks.append(Check("main", "run as a script", 2,
                            all("__main__" in p.read_text() for p in scripts),
                            "all runnable"))
    return dim


def dockerfile_arg(text: str, name: str) -> str:
    match = re.search(rf"^ARG {name}=(\S+)", text, re.M)
    return match.group(1) if match else ""


def supply_chain() -> Dimension:
    dim = Dimension("supply-chain")
    text = read("Dockerfile")
    stages = {m.group(1) for m in re.finditer(r"^FROM \S+ AS (\S+)", text, re.M)}
    unpinned = []
    for ref in re.findall(r"^FROM (\S+)", text, re.M):
        if ref in stages:
            continue
        expanded = re.sub(r"\$\{(\w+)\}",
                          lambda m: dockerfile_arg(text, m.group(1)), ref)
        if not re.search(r"@sha256:[0-9a-f]{64}$", expanded):
            unpinned.append(ref)
    dim.checks.append(Check("digest", "images pinned by digest", 6,
                            not unpinned, ", ".join(unpinned) or "pinned"))

    downloads = len(re.findall(r"curl[^\n]*-[a-zA-Z]*o\s+\S+", text))
    verified = len(re.findall(r"sha256sum -c", text))
    ok = downloads >= 2 and verified >= downloads and "WEBVIEW2_SHA256" in text
    dim.checks.append(Check("checksums", "downloads checksum-verified", 6, ok,
                            f"{verified} verifications / {downloads} downloads"))

    workflows = "\n".join(p.read_text() for p in sources(".github/workflows/*.yml"))
    refs = re.findall(r"uses:\s*(\S+?)@(\S+)", workflows)
    loose = [f"{name}@{ref}" for name, ref in refs
             if not re.fullmatch(r"[0-9a-f]{40}", ref)]
    commented = re.findall(r"uses:\s*\S+@[0-9a-f]{40}\s+# v", workflows)
    dim.checks.append(Check("actions", "actions pinned to commit SHAs", 4,
                            bool(refs) and not loose and len(commented) == len(refs),
                            ", ".join(loose[:3]) or f"{len(refs)} pinned"))

    cleaned = "rm -rf /var/lib/apt/lists/*" in text
    dim.checks.append(Check("apt", "apt lists removed, no :latest", 2,
                            cleaned and ":latest" not in text,
                            "ok" if cleaned else "apt lists kept"))
    stages_count = len(re.findall(r"^FROM ", text, re.M))
    dim.checks.append(Check("stages", "multi-stage build", 2, stages_count >= 3,
                            f"{stages_count} stages"))
    return dim


def runtime() -> Dimension:
    dim = Dimension("runtime")
    text = read("Dockerfile")
    entry = read("docker/entrypoint.sh")

    dim.checks.append(Check("tini", "tini as PID 1", 3,
                            bool(re.search(r'ENTRYPOINT \["[^"]*tini", "--"', text)),
                            "tini entrypoint"))
    dim.checks.append(Check("healthcheck", "health check wired", 3,
                            "HEALTHCHECK" in text and "healthcheck.sh" in text,
                            "healthcheck.sh"))
    exposed = re.findall(r"^EXPOSE (\d+)", text, re.M)
    dim.checks.append(Check("port", "single exposed port", 2,
                            exposed == ["6901"], ", ".join(exposed) or "none"))
    tls = re.search(r"KASMVNC_SSL=(\d)", text)
    dim.checks.append(Check("tls", "TLS enabled by default", 2,
                            bool(tls) and tls.group(1) == "1", "KASMVNC_SSL=1"))
    fail_closed = ("VNC_PASSWORD" in entry and "KASMVNC_ALLOW_NO_AUTH" in entry
                   and "exit 1" in entry)
    dim.checks.append(Check("auth", "authentication fails closed", 3, fail_closed,
                            "password required unless disabled"))
    secrets = re.findall(
        r"^\s*(?:ENV|ARG)\s+\S*(?:PASSWORD|TOKEN|SECRET)\S*=\S+", text, re.M)
    dim.checks.append(Check("secrets", "no secrets baked in", 2,
                            not secrets and not re.search(
                                r"^COPY .*\.(?:pem|key|crt)\b", text, re.M),
                            "none"))
    return dim


def governance() -> Dimension:
    dim = Dimension("governance")
    ci = read(".github/workflows/ci.yml")
    dim.checks.append(Check("permissions", "least-privilege token", 2,
                            "permissions:\n  contents: read" in ci, "contents: read"))
    dim.checks.append(Check("concurrency", "cancel superseded runs", 1,
                            "cancel-in-progress: true" in ci, "enabled"))
    ecosystems = set(re.findall(r"package-ecosystem:\s*(\S+)",
                                read(".github/dependabot.yml")))
    need = {"github-actions", "docker", "nuget"}
    dim.checks.append(Check("dependabot", "dependabot coverage", 2,
                            need <= ecosystems, ", ".join(sorted(ecosystems))))
    dim.checks.append(Check("codeowners", "CODEOWNERS", 1,
                            (ROOT / ".github/CODEOWNERS").is_file(), "@webees"))
    templates = (ROOT / ".github/PULL_REQUEST_TEMPLATE.md").is_file() and len(
        list((ROOT / ".github/ISSUE_TEMPLATE").glob("*.yml"))) >= 2
    dim.checks.append(Check("templates", "PR and issue templates", 1,
                            templates, "present"))
    cleanup = len(list((ROOT / ".github/workflows").glob("cleanup-*.yml")))
    dim.checks.append(Check("cleanup", "automated cleanup", 2, cleanup >= 2,
                            f"{cleanup} workflows"))
    release = latest_release()
    dim.checks.append(Check("security", "supported versions current", 1,
                            release in read("SECURITY.md"), release or "no release"))
    return dim


def docs() -> Dimension:
    dim = Dimension("docs")
    en = read("README.md")
    zh = read("README.zh-CN.md")

    def switch(text: str, target: str) -> bool:
        return target in "\n".join(text.splitlines()[:8])

    dim.checks.append(Check("switch", "language switch on top", 3,
                            switch(en, "README.zh-CN.md") and switch(zh, "README.md"),
                            "both READMEs"))
    want_en = [pair[0] for pair in README_SECTIONS]
    want_zh = [pair[1] for pair in README_SECTIONS]
    en_h, zh_h = h2(en), h2(zh)
    missing = (set(want_en) - set(en_h)) | (set(want_zh) - set(zh_h))
    extra = (set(en_h) - set(want_en)) | (set(zh_h) - set(want_zh))
    duplicated = len(en_h) != len(set(en_h)) or len(zh_h) != len(set(zh_h))
    detail = ", ".join(sorted(missing | extra)) or (
        "duplicate headings" if duplicated else f"{len(en_h)}/{len(zh_h)} sections")
    dim.checks.append(Check("parity", "bilingual section parity", 4,
                            not missing and not extra and not duplicated, detail))

    result = subprocess.run(["bash", "scripts/check-docs.sh"], cwd=ROOT,
                            capture_output=True, text=True)
    tail = (result.stderr or result.stdout).strip().splitlines()
    dim.checks.append(Check("sync", "code and docs agree", 3,
                            result.returncode == 0, tail[-1] if tail else "docs-chk"))
    rubric = read("docs/quality.md")
    names = ["hygiene", "shell", "python", "supply-chain", "runtime",
             "governance", "docs", "verification"]
    dim.checks.append(Check("rubric", "rubric documented", 2,
                            all(name in rubric for name in names) and "100" in rubric,
                            "docs/quality.md"))
    release = latest_release()
    stale = re.findall(r"winforms-wine-runtime:(\d{4}\.\d{2}\.\d{2}(?:\.\d+)?)",
                       "\n".join(p.read_text(errors="replace") for p in tracked_text()))
    dim.checks.append(Check("version", "release references current", 3,
                            bool(release) and all(v == release for v in stale),
                            f"{len(stale)} refs at {release}"))
    return dim


def verification() -> Dimension:
    dim = Dimension("verification")
    tests = sources("scripts/test_*.py")
    counts = {p.name: len(re.findall(r"^\s*def test_", p.read_text(), re.M))
              for p in tests}
    dim.checks.append(Check("tests", "scoring tests", 4,
                            {"test_score.py", "test_quality.py"} <= set(counts)
                            and min(counts.values()) >= 5, str(counts)))
    harness = {"scripts/selftest.sh", "scripts/bench.sh", "scripts/score.py"}
    present = {str(p.relative_to(ROOT)) for p in sources("scripts/*")}
    dim.checks.append(Check("harness", "verification harness", 2,
                            harness <= present, "selftest, bench, score"))
    makefile = read("Makefile")
    dim.checks.append(Check("make", "make targets", 2,
                            all(t in makefile for t in
                                ("lint:", "quality:", "test:", "bench:", "score:")),
                            "lint, quality, test"))
    dim.checks.append(Check("ci", "quality gate in CI", 2,
                            "scripts/quality.py" in read(".github/workflows/ci.yml"),
                            "ci.yml"))
    return dim


BUILDERS = (hygiene, shell, python, supply_chain, runtime, governance, docs,
            verification)


def report() -> dict:
    dims = [build() for build in BUILDERS]
    earned = sum(d.earned for d in dims)
    budget = sum(d.budget for d in dims)
    return {
        "score": round(earned / budget * 100) if budget else 0,
        "earned": earned,
        "budget": budget,
        "dimensions": [
            {
                "name": d.name,
                "earned": d.earned,
                "budget": d.budget,
                "checks": [
                    {"id": c.check_id, "ok": c.ok, "points": c.points,
                     "detail": c.detail}
                    for c in d.checks
                ],
            }
            for d in dims
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Grade repository quality.")
    parser.add_argument("--min", type=int, default=100,
                        help="fail below this score (default: 100)")
    parser.add_argument("--json", metavar="PATH", help="write the report as JSON")
    args = parser.parse_args()

    data = report()
    if args.json:
        Path(args.json).write_text(json.dumps(data, indent=2) + "\n",
                                   encoding="utf-8")
    print(f"{'dimension':<16}{'score':>6}{'max':>6}")
    for dim in data["dimensions"]:
        print(f"{dim['name']:<16}{dim['earned']:>6}{dim['budget']:>6}")
        for item in dim["checks"]:
            if not item["ok"]:
                print(f"  FAIL {item['id']}: {item['detail']}")
    print(f"{'TOTAL':<16}{data['earned']:>6}{data['budget']:>6}  "
          f"-> {data['score']}/100")
    if data["score"] < args.min:
        print(f"quality: FAILED ({data['score']} < {args.min})", file=sys.stderr)
        return 1
    print("quality: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
