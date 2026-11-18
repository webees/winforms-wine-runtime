#!/usr/bin/env bash
# Run the in-image self-test and fail unless every step passed.
#
#   IMAGE=winforms-wine-runtime:dev-demo ./scripts/selftest.sh
#
# PLATFORM defaults to linux/amd64; set it to empty to use the image's platform.
# SUMMARY_FILE is an internal hook for bench.sh: it receives "ok passed total".
# Needs docker and python3.
set -euo pipefail

case "${1:-}" in
-h | --help)
  sed -n '2,8p' "$0"
  exit 0
  ;;
esac

IMAGE="${IMAGE:-winforms-wine-runtime:dev-demo}"
PLATFORM="${PLATFORM-linux/amd64}"
plat=()
[ -n "$PLATFORM" ] && plat=(--platform "$PLATFORM")

# OUT_DIR lets CI collect the evidence; otherwise a temporary directory is used.
if [ -n "${OUT_DIR:-}" ]; then
  mkdir -p "$OUT_DIR"
  OUT_DIR="$(cd "$OUT_DIR" && pwd)"
else
  OUT_DIR="$(mktemp -d)"
  cleanup() {
    rm -rf "$OUT_DIR" 2>/dev/null ||
      docker run --rm -u 0:0 --entrypoint sh -v "$OUT_DIR:/w" "$IMAGE" \
        -c 'find /w -mindepth 1 -delete' >/dev/null 2>&1 || true
  }
  trap cleanup EXIT
fi

echo "==> running self-test in $IMAGE"
rc=0
docker run --rm ${plat[@]+"${plat[@]}"} \
  -v "$OUT_DIR:/data" \
  -e ENABLE_VNC=0 \
  "$IMAGE" --selftest --strict --out 'Z:\data' || rc=$?

echo "==> report"
if [ ! -s "$OUT_DIR/report.json" ]; then
  echo "self-test wrote no report.json (container exit $rc)" >&2
  echo "check the image entrypoint and the Wine prefix" >&2
  exit 1
fi
cat "$OUT_DIR/report.json"
echo

read -r passed total ok < <(python3 -c '
import json, sys
report = json.load(open(sys.argv[1]))
steps = report.get("steps", [])
print(sum(1 for step in steps if step.get("ok")), len(steps), int(report.get("ok") is True))
' "$OUT_DIR/report.json")

if [ -n "${SUMMARY_FILE:-}" ]; then
  result=false
  if [ "$ok" = "1" ]; then result=true; fi
  printf '%s %s %s\n' "$result" "$passed" "$total" >"$SUMMARY_FILE"
fi

echo "==> ${passed}/${total} steps passed"
if [ "$rc" -ne 0 ]; then
  echo "self-test exited $rc" >&2
  exit 1
fi
if [ "$ok" != "1" ] || [ "$passed" != "$total" ] || [ "$total" = "0" ]; then
  echo "self-test failed: report.json does not report every step as ok" >&2
  exit 1
fi

for f in report.json sunnyui.png magick.png webview2.png; do
  test -s "$OUT_DIR/$f" || {
    echo "missing artifact: $f" >&2
    exit 1
  }
done

echo "==> all checks passed"
