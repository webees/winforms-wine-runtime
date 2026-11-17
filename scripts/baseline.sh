#!/usr/bin/env bash
# Size baseline for the tracked tree: total lines, bytes and the largest files.
#
#   ./scripts/baseline.sh [--top N]
#
# Text-only, so it never reads image or binary content into the report.
set -euo pipefail
cd "$(dirname "$0")/.."

top=10
[ "${1:-}" = "--top" ] && top=${2:-10}

sizes=$(git ls-files -z | xargs -0 wc -lc)
printf '%s\n\n  lines   bytes file\n' "$(printf '%s\n' "$sizes" |
  awk '$3 != "total" { l += $1; b += $2; f++ }
       END { printf "files %d\nlines %d\nbytes %d", f, l, b }')"
printf '%s\n' "$sizes" | awk '$3 != "total"' | sort -k2,2nr | head -n "$top"
