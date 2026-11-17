#!/usr/bin/env bash
# Check whether a WebView2 Fixed Version runtime works under Wine.
#
#   ./scripts/bisect-webview2.sh 135.0.3179.98
#
# Builds the self-test image with WEBVIEW2_VERSION=<version> and runs it.
# Exit code 0 = pass, 1 = fail.
set -euo pipefail

VERSION="${1:?usage: bisect-webview2.sh <webview2-version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="bisect-${VERSION//[^0-9A-Za-z._-]/-}"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

echo "==> building self-test image with WebView2 $VERSION"
docker buildx build --platform linux/amd64 --target demo \
  --build-arg "WEBVIEW2_VERSION=$VERSION" \
  -t "winforms-wine-runtime:$TAG" "$ROOT"

echo "==> running self-test"
if docker run --rm -v "$OUT_DIR:/data" -e ENABLE_VNC=0 \
     "winforms-wine-runtime:$TAG" --selftest --strict --out 'Z:\data'; then
  echo "PASS  $VERSION"
  exit 0
fi

echo "FAIL  $VERSION" >&2
if [ -f "$OUT_DIR/report.json" ]; then
  cat "$OUT_DIR/report.json" >&2
fi
exit 1
