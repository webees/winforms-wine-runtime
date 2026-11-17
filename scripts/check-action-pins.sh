#!/usr/bin/env bash
# Every `uses:` in .github/workflows must pin a version tag, never a branch.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
while IFS= read -r ref; do
  case "$ref" in
    *@v[0-9]*) ;;
    *) echo "::error::unpinned action: $ref" >&2; status=1 ;;
  esac
done < <(grep -rhoE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+[^[:space:]]+' \
  .github/workflows | awk '{print $NF}')
exit "$status"
