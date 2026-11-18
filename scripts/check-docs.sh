#!/usr/bin/env bash
# Fail when code and documentation drift apart.
#
#   ./scripts/check-docs.sh
#
# Checks: runtime variables, exposed ports, documented links, image references.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
bad() {
  printf 'docs-chk: %s\n' "$*" >&2
  fail=1
}

# Variables with a documented default (`${VAR:-...}`), minus shell plumbing.
code_vars=$(grep -oE '\$\{[A-Z][A-Z0-9_]*:-' docker/entrypoint.sh | sed -E 's/^\$\{//; s/:-$//' | sort -u |
  grep -vE '^(HOME|PATH|PWD|DISPLAY|WINEPREFIX|WINESERVER|LANG)$' || true)

# Variables documented in the "Environment" table of each README.
doc_vars() {
  awk -F'`' '/^\| `[A-Z][A-Z0-9_]*`( \/ `[A-Z][A-Z0-9_]*`)? \|/ {
    print $2
    if ($4 ~ /^[A-Z][A-Z0-9_]*$/) print $4
  }' "$1" | sort -u
}

for readme in README.md README.zh-CN.md; do
  [ -f "$readme" ] || {
    bad "missing $readme"
    continue
  }
  docs=$(doc_vars "$readme")
  for v in $code_vars; do
    grep -qx "$v" <<<"$docs" || bad "$readme does not document \`$v\`"
  done
  for v in $docs; do
    case "$v" in WEBVIEW2_*) continue ;; esac # consumed by the WebView2 loader
    grep -qw "$v" docker/entrypoint.sh Dockerfile || bad "$readme documents \`$v\` but no code reads it"
  done
done

# Every documented build argument exists, and every ARG is documented.
doc_args=$(sed -n '/^## Build arguments/,/^## /p' README.md |
  awk -F'`' '/^\| `[A-Z][A-Z0-9_]*` \|/ {print $2}' | sort -u)
code_args=$(awk '/^ARG [A-Z]/ {print $2}' Dockerfile | cut -d= -f1 | grep -v '^DEBIAN_FRONTEND$' | sort -u)
while read -r arg; do
  [ -n "$arg" ] || continue
  grep -qx "$arg" <<<"$code_args" || bad "README documents build arg \`$arg\` that Dockerfile does not declare"
done <<<"$doc_args"
while read -r arg; do
  [ -n "$arg" ] || continue
  grep -qx "$arg" <<<"$doc_args" || bad "Dockerfile ARG \`$arg\` is not documented under Build arguments"
done <<<"$code_args"

# Port: EXPOSE, README table, examples and workflows must agree.
port=$(awk '/^EXPOSE / {print $2}' Dockerfile | head -n1)
[ -n "$port" ] || bad "Dockerfile has no EXPOSE"
for f in README.md README.zh-CN.md docs/ports-and-volumes.md examples/docker-compose.yml examples/kubernetes.yaml; do
  grep -q "$port" "$f" || bad "$f does not mention port $port"
done

# Relative links in Markdown must resolve.
while IFS= read -r link; do
  [ -e "$link" ] || bad "broken link: $link"
done < <(grep -rhoE '\]\([^)#][^)]*\)' README.md README.zh-CN.md docs/*.md |
  sed -E 's/^\]\(//; s/\)$//' | grep -vE '^(https?|mailto|#)' | sort -u)

# The scoring table in docs/benchmark.md must match scripts/score.py.
PYTHONDONTWRITEBYTECODE=1 python3 -B - <<'PY' || fail=1
import re
import sys
from pathlib import Path

sys.path.insert(0, "scripts")
from score import score

text = Path("docs/benchmark.md").read_text()
failed = False
section = re.search(r"^## Scoring$(.*?)^## ", text, re.S | re.M)
documented = {
    name.strip().lower()
    for name in re.findall(r"^\| ([A-Za-z][A-Za-z -]*) \|",
                           section.group(1) if section else "", re.M)
    if name.strip().lower() != "dimension"
}

# Every metric bench.sh emits must be documented, and score.py must not read a
# key the report never contains. bench.sh declares its keys on one marker line
# so this stays exact without parsing the printf format.
bench = Path("scripts/bench.sh").read_text()
marker = re.search(r"^# bench-report-keys:(.*(?:\n#   .*)*)", bench, re.M)
emitted = set(re.findall(r"[a-z0-9_]+", marker.group(1))) if marker else set()
if not emitted:
    print("docs-chk: scripts/bench.sh has no '# bench-report-keys:' line", file=sys.stderr)
    failed = True
measured = re.search(r"^## What is measured$(.*?)^## ", text, re.S | re.M)
documented_metrics = {
    key for line in (measured.group(1).splitlines() if measured else [])
    if line.startswith("|")
    for key in re.findall(r"`([a-z0-9_]+)`", (line.split("|") + [""])[1])
}
if not documented_metrics:
    print("docs-chk: docs/benchmark.md has no 'What is measured' table", file=sys.stderr)
    failed = True

perfect = {
    "selftest_ok": True, "selftest_steps": 4, "anon_status": 401, "auth_guard": "ok",
    "tls_status": 200, "plain_on_tls_port": 400, "start_ms": 1_000, "app_ms": 2_000,
    "idle_rss_kb": 200 * 1024, "size_bytes": 2 * 1024**3, "x_display": "yes",
}
total, rows = score(perfect)
if total != 100:
    print(f"docs-chk: score.py gives {total}/100 to a perfect image", file=sys.stderr)
    failed = True
for name, _, maximum, _ in rows:
    if name.lower() not in documented:
        print(f"docs-chk: docs/benchmark.md is missing dimension '{name}'", file=sys.stderr)
        failed = True
    if maximum != 100:
        print(f"docs-chk: score.py dimension '{name}' is not out of 100", file=sys.stderr)
        failed = True
if documented != {name.lower() for name, _, _, _ in rows}:
    print("docs-chk: docs/benchmark.md and score.py disagree on the scored dimensions", file=sys.stderr)
    failed = True

for key in sorted(emitted ^ documented_metrics):
    print(f"docs-chk: bench.sh and docs/benchmark.md disagree on metric `{key}`", file=sys.stderr)
    failed = True
for key in sorted(set(perfect) - emitted):
    print(f"docs-chk: score.py reads `{key}` which bench.sh does not emit", file=sys.stderr)
    failed = True
sys.exit(1 if failed else 0)
PY

# The image referenced by the docs must be the one the Makefile builds.
image=$(awk -F' \\?= ' '/^IMAGE \?=/ {print $2}' Makefile)
[ -n "$image" ] || bad "Makefile does not define IMAGE"
for f in README.md README.zh-CN.md docs/ports-and-volumes.md examples/kubernetes.yaml; do
  grep -q "$image" "$f" || bad "$f does not reference the built image $image"
done

# Published images use CalVer plus the moving `2` and `latest` aliases. `dev`
# and `dev-demo` are local-only, and SemVer-style aliases are gone.
for f in README.md README.zh-CN.md docs/*.md examples/*.yml examples/*.yaml; do
  [ -f "$f" ] || continue
  if grep -nE "${image//./\\.}:dev([^0-9A-Za-z-]|$)" "$f" >/dev/null; then
    bad "$f presents the local-only :dev tag as a published image"
  fi
  if grep -nE "${image//./\\.}:(1|1\.0|1\.0\.0|2\.0|2\.0\.0)([^0-9.]|$)" "$f" >/dev/null; then
    bad "$f references a retired SemVer image tag"
  fi
done

[ -f docs/versioning.md ] || bad "docs/versioning.md is missing"
grep -q 'vYYYY.MM.DD' docs/versioning.md || bad "docs/versioning.md does not document CalVer"

# APP takes a bare filename under /app or an absolute Linux path. A Windows
# path cannot be resolved before Wine starts, so never advertise one.
for f in README.md README.zh-CN.md docs/*.md; do
  if grep -nE 'APP=([A-Za-z]:\\|[A-Za-z]:/)' "$f" >/dev/null; then
    bad "$f shows a Windows path for APP"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "docs-chk: FAILED" >&2
  exit 1
fi
echo "docs-chk: ok"
