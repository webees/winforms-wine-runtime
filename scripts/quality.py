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
import importlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from functools import cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAX_TEXT_BYTES = 32 * 1024
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
NAME = re.compile(r"^\.?[a-z0-9][a-z0-9.-]*$")
PY_NAME = re.compile(r"^[a-z][a-z0-9_]*\.py$")
TEMPLATE_NAME = re.compile(r"^[a-z][a-z0-9_]*\.yml$")
FIXED_NAMES = {
    "README.md", "README.zh-CN.md", "CHANGELOG.md", "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md", "SECURITY.md", "LICENSE", "CODEOWNERS",
    "THIRD-PARTY-NOTICES.md", "PULL_REQUEST_TEMPLATE.md", "Dockerfile",
    "Makefile",
}
DOTNET_NAME = re.compile(r"^[A-Z][A-Za-z0-9]*\.(?:cs|csproj)$")
FIXED_DIRS = {"ISSUE_TEMPLATE"}


def well_named(path: Path) -> bool:
    """Lowercase paths, PascalCase .NET projects, fixed uppercase documents."""
    parts = path.relative_to(ROOT).parts
    for depth, part in enumerate(parts[:-1], 1):
        project = ROOT.joinpath(*parts[:depth]) / f"{part}.csproj"
        if part not in FIXED_DIRS and not NAME.match(part) and not project.is_file():
            return False
    name = parts[-1]
    if name in FIXED_NAMES or DOTNET_NAME.match(name):
        return True
    if name.endswith(".py"):
        return bool(PY_NAME.match(name))
    if path.parent.name == "ISSUE_TEMPLATE":
        return bool(TEMPLATE_NAME.match(name))
    return bool(NAME.match(name))


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

    @property
    def score(self) -> int:
        """Dimension score out of 100, floored so a miss never rounds up."""
        return self.earned * 100 // self.budget if self.budget else 0


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


@cache
def repo_files() -> list[Path]:
    """Files that git would commit; ignored build output must not count."""
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT, capture_output=True, text=True)
    if listed.returncode:
        return tracked_text()
    return [ROOT / rel for rel in listed.stdout.split("\0")
            if rel and (ROOT / rel).is_file()]


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

    empty = [str(p.relative_to(ROOT)) for p in tracked_text() if p.stat().st_size == 0]
    dim.checks.append(Check("empty", "no empty text files", 1,
                            not empty, ", ".join(empty) or "none"))

    bloated = [str(p.relative_to(ROOT)) for p in tracked_text()
               if p.stat().st_size > MAX_TEXT_BYTES]
    dim.checks.append(Check("size", f"text files <= {MAX_TEXT_BYTES // 1024} KiB", 1,
                            not bloated, ", ".join(bloated) or "within budget"))

    odd = [p.relative_to(ROOT).as_posix() for p in repo_files() if not well_named(p)]
    dim.checks.append(Check("naming", "consistent file names", 3,
                            not odd, ", ".join(odd[:3]) or "kebab-case + .NET PascalCase"))
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

    bots = read(".github/dependabot.yml")
    ecosystems = re.findall(r"package-ecosystem:\s*(\S+)", bots)
    limited = len(re.findall(r"open-pull-requests-limit:\s*\d+", bots)) >= len(ecosystems)
    grouped = len(re.findall(r"^\s{4}groups:$", bots, re.M)) >= len(ecosystems)
    dim.checks.append(Check("dependabot-hygiene", "updates grouped and bounded", 4,
                            {"github-actions", "docker", "nuget"} <= set(ecosystems)
                            and limited and grouped,
                            f"{len(ecosystems)} ecosystems"))
    return dim


def runtime() -> Dimension:
    dim = Dimension("runtime")
    text = read("Dockerfile")
    entry = read("docker/entrypoint.sh")

    dim.checks.append(Check("tini", "tini as PID 1", 3,
                            bool(re.search(r'ENTRYPOINT \["[^"]*tini", "--"', text)),
                            "tini entrypoint"))
    dim.checks.append(Check("healthcheck", "health check wired", 3,
                            "HEALTHCHECK" in text and "xdpyinfo" in text
                            and "ss -ltnH" in text, "inline HEALTHCHECK"))
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

    window = re.search(r"--start-period=(\d+)s", text)
    retries = re.search(r"--retries=(\d+)", text)
    dim.checks.append(Check("healthcheck-window", "health check tolerates boot", 4,
                            bool(window) and int(window.group(1)) >= 60
                            and bool(retries) and int(retries.group(1)) >= 3,
                            "start-period >= 60s, retries >= 3"))
    warned = re.search(r"KASMVNC_ALLOW_NO_AUTH[^\n]*\n(?:[^\n]*\n)?[^\n]*warning",
                       entry)
    dim.checks.append(Check("no-auth-warning", "empty password logs warning", 2,
                            bool(warned), "warning emitted"))
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


def release() -> Dimension:
    dim = Dimension("release")
    release_yml = read(".github/workflows/release.yml")
    workflows = "\n".join(p.read_text() for p in sources(".github/workflows/*.yml"))

    aliases = re.findall(r"type=raw,value=([^\s$][^\s]*)", release_yml)
    moving = [alias for alias in aliases if alias.lower() != "latest"]
    dim.checks.append(Check("immutable-tags", "no numeric moving aliases", 30,
                            not moving, ", ".join(moving) or "CalVer + latest"))

    runners = re.findall(r"runs-on:\s*(\S+)", workflows)
    floating = [runner for runner in runners if runner.endswith("-latest")]
    dim.checks.append(Check("runner-pinned", "runners pinned by version", 20,
                            not floating, ", ".join(floating) or "ubuntu-24.04"))

    lines = workflows.splitlines()
    checkouts = [i for i, line in enumerate(lines) if "actions/checkout@" in line]
    hardened = all(
        any("persist-credentials: false" in follow
            for follow in lines[i + 1:i + 6])
        for i in checkouts
    )
    dim.checks.append(Check("checkout", "checkout drops credentials", 20,
                            hardened, f"{len(checkouts)} checkout steps"))

    cleanup = read(".github/workflows/cleanup-ghcr.yml")
    retired = "delete_tags" in cleanup and "'latest,2'" not in cleanup
    dim.checks.append(Check("cleanup", "retired tags are removable", 15,
                            retired, "delete_tags input, latest kept"))

    changelog = read("CHANGELOG.md")
    calver = re.findall(r"^## \[(\d{4}\.\d{2}\.\d{2}(?:\.\d+)?)\] - \d{4}-\d{2}-\d{2}$",
                        changelog, re.M)
    dim.checks.append(Check("changelog", "Keep a Changelog + CalVer", 15,
                            "## [Unreleased]" in changelog and bool(calver),
                            f"{len(calver)} dated releases"))
    unguarded = [p.name for p in sources(".github/workflows/*.yml")
                 if not re.search(r"^permissions:", p.read_text(), re.M)]
    write_all = [p.name for p in sources(".github/workflows/*.yml")
                 if "permissions: write-all" in p.read_text()]
    dim.checks.append(Check("permissions", "workflow tokens scoped", 10,
                            not unguarded and not write_all,
                            ", ".join(unguarded + write_all) or "all scoped"))
    guarded = re.search(r"if: github\.event_name == 'workflow_dispatch'"
                        r"[^\n]*delete_tags", cleanup)
    dim.checks.append(Check("guarded-delete", "tag deletion is manual only", 15,
                            bool(guarded) and "dry_run" in cleanup,
                            "workflow_dispatch + dry run"))
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

    rubric = read("docs/quality.md")
    names = ["hygiene", "shell", "python", "supply-chain", "runtime",
             "governance", "release", "docs", "verification", "leanness"]
    dim.checks.append(Check("rubric", "rubric documented", 2,
                            all(name in rubric for name in names) and "100" in rubric,
                            "docs/quality.md"))
    release = latest_release()
    stale = re.findall(r"winforms-wine-runtime:(\d{4}\.\d{2}\.\d{2}(?:\.\d+)?)",
                       "\n".join(p.read_text(errors="replace") for p in tracked_text()))
    dim.checks.append(Check("version", "release references current", 3,
                            bool(release) and all(v == release for v in stale),
                            f"{len(stale)} refs at {release}"))

    markdown = [p for p in tracked_text() if p.suffix == ".md"]
    broken = []
    for path in markdown:
        for target in re.findall(r"\]\(([^)#\s]+)", path.read_text(errors="replace")):
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if not (path.parent / target).resolve().exists():
                broken.append(f"{path.relative_to(ROOT)} -> {target}")
    dim.checks.append(Check("links", "relative links resolve", 4,
                            not broken, ", ".join(broken[:3]) or "all resolve"))

    def env_keys(text: str, heading: str) -> list[str]:
        section = text.split(heading, 1)[1].split("\n## ", 1)[0]
        pairs = re.findall(r"^\| `([A-Z0-9_]+)`(?: / `([A-Z0-9_]+)`)?",
                           section, re.M)
        return [name for pair in pairs for name in pair if name]

    en_keys = env_keys(en, "## Environment")
    zh_keys = env_keys(zh, "## 环境变量")
    dim.checks.append(Check("env-parity", "environment tables match", 4,
                            bool(en_keys) and en_keys == zh_keys,
                            f"{len(en_keys)} variables"))

    alias = [p.relative_to(ROOT).as_posix() for p in markdown
             if p.name != "CHANGELOG.md"
             if re.search(r"`2` and `latest`|winforms-wine-runtime:2\b",
                          p.read_text(errors="replace"))]
    dim.checks.append(Check("alias", "retired aliases are gone", 4,
                            not alias, ", ".join(alias) or "no stale alias"))

    dockerfile = read("Dockerfile")
    entry = read("docker/entrypoint.sh")
    code_vars = set(re.findall(r"\$\{([A-Z][A-Z0-9_]*):-", entry)) - {
        "BASH_SOURCE", "HOME", "PATH", "PWD", "DISPLAY", "WINEPREFIX",
        "WINESERVER", "LANG"}
    unused = sorted(v for v in en_keys if not v.startswith("WEBVIEW2_")
                    and v not in entry + dockerfile)
    undocumented = sorted(code_vars - set(en_keys)) + sorted(code_vars - set(zh_keys))
    dim.checks.append(Check("env-docs", "runtime variables documented", 4,
                            not undocumented and not unused,
                            ", ".join(undocumented + unused) or f"{len(code_vars)} variables"))

    build = en.split("## Build arguments", 1)[1].split("\n## ", 1)[0]
    doc_args = set(re.findall(r"^\| `([A-Z][A-Z0-9_]*)`", build, re.M))
    code_args = set(re.findall(r"^ARG ([A-Z][A-Z0-9_]*)", dockerfile, re.M)) - {
        "DEBIAN_FRONTEND"}
    dim.checks.append(Check("args-docs", "build arguments documented", 3,
                            doc_args == code_args,
                            ", ".join(sorted(doc_args ^ code_args))
                            or f"{len(code_args)} arguments"))

    port = re.search(r"^EXPOSE (\d+)", dockerfile, re.M)
    port_files = ["README.md", "README.zh-CN.md", "docs/ports-and-volumes.md",
                  "examples/docker-compose.yml", "examples/kubernetes.yaml"]
    absent = [name for name in port_files
              if not port or port.group(1) not in read(name)]
    dim.checks.append(Check("port-docs", "exposed port documented", 3,
                            bool(port) and not absent,
                            ", ".join(absent) or (port.group(1) if port else "no EXPOSE")))

    scorer = importlib.import_module("score").score
    bench_doc = read("docs/benchmark.md")
    marker = re.search(r"^# bench-report-keys:(.*(?:\n#   .*)*)",
                       read("scripts/bench.sh"), re.M)
    emitted = set(re.findall(r"[a-z0-9_]+", marker.group(1))) if marker else set()
    measured = re.search(r"^## What is measured$(.*?)^## ", bench_doc, re.S | re.M)
    documented = {key for line in (measured.group(1).splitlines() if measured else [])
                  if line.startswith("|")
                  for key in re.findall(r"`([a-z0-9_]+)`", (line.split("|") + [""])[1])}
    scoring = re.search(r"^## Scoring$(.*?)^## ", bench_doc, re.S | re.M)
    scored = scoring.group(1).lower() if scoring else ""
    total, rows = scorer({
        "selftest_ok": True, "selftest_steps": 4, "anon_status": 401,
        "auth_guard": "ok", "tls_status": 200, "plain_on_tls_port": 400,
        "start_ms": 1_000, "app_ms": 2_000, "idle_rss_kb": 200 * 1024,
        "size_bytes": 2 * 1024 ** 3, "x_display": "yes"})
    wrong = [name for name, _, maximum, _ in rows
             if name.lower() not in scored or maximum != 100]
    dim.checks.append(Check("bench-docs", "benchmark docs match score.py", 4,
                            bool(marker) and emitted == documented and total == 100
                            and not wrong,
                            ", ".join(sorted((emitted ^ documented) | set(wrong)))
                            or f"{total}/100, {len(emitted)} keys"))

    image = re.search(r"^IMAGE \?= (\S+)", read("Makefile"), re.M)
    image = image.group(1) if image else ""
    refs = sources("README.md", "README.zh-CN.md", "docs/*.md",
                   "examples/*.yml", "examples/*.yaml")
    missing_image = [p.relative_to(ROOT).as_posix() for p in refs
                     if p.name in {"README.md", "README.zh-CN.md",
                                   "ports-and-volumes.md", "kubernetes.yaml"}
                     and image not in p.read_text(errors="replace")]
    bad_tags = [p.relative_to(ROOT).as_posix() for p in refs
                if re.search(rf"{re.escape(image)}:dev(?![0-9A-Za-z-])",
                             p.read_text(errors="replace"))
                or re.search(rf"{re.escape(image)}:(?:1|1\.0|1\.0\.0|2\.0|2\.0\.0)"
                             r"(?![0-9.])", p.read_text(errors="replace"))]
    dim.checks.append(Check("image-docs", "documented image and tags", 4,
                            bool(image) and not missing_image and not bad_tags,
                            ", ".join(missing_image + bad_tags) or image))

    versioning = read("docs/versioning.md")
    dim.checks.append(Check("calver", "CalVer documented", 2,
                            "CalVer" in versioning and "scripts/version.sh" in versioning,
                            "docs/versioning.md"))

    windows = [p.relative_to(ROOT).as_posix() for p in refs
               if re.search(r"APP=([A-Za-z]:\\|[A-Za-z]:/)",
                            p.read_text(errors="replace"))]
    dim.checks.append(Check("app-path", "no Windows APP paths", 2,
                            not windows, ", ".join(windows) or "Linux paths only"))
    return dim


def verification() -> Dimension:
    dim = Dimension("verification")
    tests = sources("scripts/test_*.py")
    counts = {p.name: len(re.findall(r"^\s*def test_", p.read_text(), re.M))
              for p in tests}
    dim.checks.append(Check("tests", "scoring tests", 4,
                            "test_rubrics.py" in counts
                            and counts["test_rubrics.py"] >= 15, str(counts)))
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
    selftest = read("scripts/selftest.sh")
    dim.checks.append(Check("strict", "self-test runs in strict mode", 4,
                            "--strict" in selftest and "rc=$?" in selftest,
                            "strict exit code"))
    dim.checks.append(Check("gate", "lint runs the quality gate", 4,
                            "quality" in makefile.split("lint:", 1)[1].split("\n\n", 1)[0],
                            "make lint -> quality"))
    return dim


def leanness() -> Dimension:
    dim = Dimension("leanness")
    files = repo_files()
    lines = {p: len(read(p.relative_to(ROOT).as_posix()).splitlines())
             for p in files}
    total = sum(lines.values())
    biggest = max(lines.items(), key=lambda item: item[1])
    dim.checks.append(Check("files", "small tree", 3, len(files) <= 50,
                            f"{len(files)} files"))
    dim.checks.append(Check("lines", "small codebase", 3, total <= 5000,
                            f"{total} lines"))
    dim.checks.append(Check("largest", "no monolith file", 3, biggest[1] <= 760,
                            f"{biggest[0].name} {biggest[1]} lines"))
    scripts = sources("scripts/*", "docker/*")
    cited = "\n".join(read(p.relative_to(ROOT).as_posix()) for p in files
                      if p not in scripts)
    orphans = [p.name for p in scripts if p.name not in cited]
    dim.checks.append(Check("orphans", "every script is used", 4,
                            not orphans, ", ".join(orphans) or f"{len(scripts)} scripts"))
    audits = [p.name for p in sources("scripts/check-*.sh")]
    dim.checks.append(Check("audits", "one audit entry point", 3,
                            not audits, ", ".join(audits) or "quality.py"))
    return dim


BUILDERS = (hygiene, shell, python, supply_chain, runtime, governance, release,
            docs, verification, leanness)


def report() -> dict:
    dims = [build() for build in BUILDERS]
    scores = [d.score for d in dims]
    total = sum(scores) // len(scores) if scores else 0
    return {
        "score": total,
        "dimensions": [
            {
                "name": d.name,
                "score": d.score,
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


def render(data: dict) -> None:
    print(f"{'dimension':<16}{'score':>6}/100")
    for dim in data["dimensions"]:
        print(f"{dim['name']:<16}{dim['score']:>6}")
        for item in dim["checks"]:
            if not item["ok"]:
                print(f"  FAIL {item['id']}: {item['detail']}")
    print(f"{'TOTAL':<16}{data['score']:>6}/100")


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
    render(data)
    if data["score"] < args.min:
        print(f"quality: FAILED ({data['score']} < {args.min})", file=sys.stderr)
        return 1
    print("quality: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
