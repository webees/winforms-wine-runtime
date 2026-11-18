#!/usr/bin/env bash
# Every `uses:` in .github/workflows must pin a 40-character commit SHA and
# record the human-readable release in a trailing comment:
#
#   uses: owner/action@<sha> # v1.2.3
#
# Tags are mutable upstream, so a tag pin alone is not reproducible.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
while IFS= read -r line; do
  if ! [[ $line =~ @[0-9a-f]{40}[[:space:]]+#\ v[0-9] ]]; then
    echo "::error::action must be a 40-char SHA with a '# vX' comment: $line" >&2
    status=1
  fi
done < <(grep -rhE '^[[:space:]]*(-[[:space:]]+)?uses:' .github/workflows)
exit "$status"
