#!/usr/bin/env bash
# Run the in-image self-test and fail unless every step passed.
#
#   IMAGE=ghcr.io/webees/winforms-wine-runtime:1-demo ./scripts/selftest.sh
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/webees/winforms-wine-runtime:dev-demo}"

# OUT_DIR lets CI collect the evidence; otherwise a temporary directory is used.
if [ -n "${OUT_DIR:-}" ]; then
  mkdir -p "$OUT_DIR"
else
  OUT_DIR="$(mktemp -d)"
  trap 'rm -rf "$OUT_DIR"' EXIT
fi

echo "==> running self-test in $IMAGE"
docker run --rm --platform linux/amd64 \
  -v "$OUT_DIR:/data" \
  -e ENABLE_VNC=0 \
  "$IMAGE" --selftest --strict --out 'Z:\data'

echo "==> report"
if command -v jq >/dev/null 2>&1; then
  jq '{ok, failed, steps: [.steps[] | {name, ok, ms, detail}]}' "$OUT_DIR/report.json"
else
  cat "$OUT_DIR/report.json"
fi

grep -Eq '"ok": *true' "$OUT_DIR/report.json" || {
  echo "self-test failed: report.json reports ok=false" >&2
  exit 1
}

for f in report.json sunnyui.png magick.png webview2.png; do
  test -s "$OUT_DIR/$f" || { echo "missing artifact: $f" >&2; exit 1; }
done

echo "==> all checks passed"
