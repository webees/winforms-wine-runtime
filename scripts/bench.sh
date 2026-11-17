#!/usr/bin/env bash
# Measure the image and write a JSON report; score it with scripts/score.py.
#
#   IMAGE=winforms-wine-runtime:dev-demo ./scripts/bench.sh \
#     [--out bench.json] [--evidence DIR] [--platform linux/amd64] [--image IMAGE]
#
# Needs docker, curl and python3. Runs five short-lived containers on an
# ephemeral loopback port, so host services and parallel runs do not collide.
# Without --platform the image's own platform is used; numbers are only
# comparable when the platform and the host CPU class match.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-winforms-wine-runtime:dev-demo}"
PLATFORM="${PLATFORM:-}"
OUT=""
EVIDENCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --evidence) EVIDENCE="$2"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

PW=bench-password
# Container-side desktop port, i.e. the image's KASMVNC_PORT default.
DESKTOP_PORT=6901
APP="wfr-bench-$$"
TLS="wfr-bench-tls-$$"
tmp=$(mktemp -d)
clean_tree() { # the app writes as its own uid; fall back to a root container
  rm -rf "$1" 2>/dev/null ||
    docker run --rm -u 0:0 --entrypoint sh -v "$1:/w" "$IMAGE" -c 'find /w -mindepth 1 -delete' >/dev/null 2>&1 || true
}
cleanup() { docker rm -f "$APP" "$TLS" >/dev/null 2>&1 || true; clean_tree "$tmp"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The self-test report and screenshots land in $tmp unless the caller keeps them.
evidence="$tmp"
if [ -n "$EVIDENCE" ]; then
  mkdir -p "$EVIDENCE"
  evidence=$(cd "$EVIDENCE" && pwd)
fi

plat=()
[ -n "$PLATFORM" ] && plat=(--platform "$PLATFORM")

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

http_code() { # url, credentials
  local args=(-s -o /dev/null -w '%{http_code}')
  case "$1" in https://*) args+=(-k) ;; esac
  [ -n "$2" ] && args+=(-u "$2")
  local code
  code=$(curl "${args[@]}" "$1" 2>/dev/null || true)
  case "$code" in '' | 000 | *[!0-9]*) echo 0 ;; *) echo "$code" ;; esac
}

wait_http() { # url, credentials, seconds
  local deadline=$((SECONDS + $3))
  while [ $SECONDS -lt $deadline ]; do
    [ "$(http_code "$1" "$2")" = 200 ] && return 0
    sleep 0.5
  done
  return 1
}

wait_app() { # seconds; Wine's desktop owns the root, the app maps its own window
  local deadline=$((SECONDS + $1))
  while [ $SECONDS -lt $deadline ]; do
    if docker exec "$APP" sh -c 'xwininfo -root -children' 2>/dev/null | awk '
        /\("/ && !/explorer\.exe/ && match($0, /[0-9]+x[0-9]+\+/) {
          split(substr($0, RSTART, RLENGTH - 1), size, "x")
          if (size[1] >= 200 && size[2] >= 100) ok = 1
        }
        END { exit !ok }'; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

host_port() { docker port "$1" "${DESKTOP_PORT}/tcp" | head -n1 | sed 's/.*://'; }

mem_kb() { # container
  local mem value
  mem=$(docker stats --no-stream --format '{{.MemUsage}}' "$1" | awk '{print $1}')
  case "$mem" in
    *GiB) value=$(awk -v v="${mem%GiB}" 'BEGIN {printf "%d", v * 1048576}') ;;
    *MiB) value=$(awk -v v="${mem%MiB}" 'BEGIN {printf "%d", v * 1024}') ;;
    *KiB) value=$(awk -v v="${mem%KiB}" 'BEGIN {printf "%d", v}') ;;
    *) echo "bench: cannot read container memory (got '$mem')" >&2; return 1 ;;
  esac
  printf '%s' "$value"
}

echo "==> image $IMAGE"
# Content size, independent of the host's image store (compressed vs. unpacked).
size=$(docker run --rm ${plat[@]+"${plat[@]}"} --entrypoint du "$IMAGE" -sbx / 2>/dev/null | awk '{print $1}')
[ -n "$size" ] || { echo "bench: cannot measure image size" >&2; exit 1; }

echo "==> cold start (HTTP)"
start=$(now_ms)
docker run -d ${plat[@]+"${plat[@]}"} --name "$APP" -e ENABLE_VNC=1 -e VNC_PASSWORD="$PW" -e KASMVNC_SSL=0 \
  -p "127.0.0.1::${DESKTOP_PORT}" "$IMAGE" >/dev/null
HTTP_PORT=$(host_port "$APP")
[ -n "$HTTP_PORT" ] || { echo "bench: no published desktop port" >&2; exit 1; }
if ! wait_http "http://127.0.0.1:$HTTP_PORT/" "wine:$PW" 120; then
  docker logs --tail 40 "$APP" >&2 || true
  echo "bench: desktop did not answer within 120 s" >&2
  exit 1
fi
start_ms=$(($(now_ms) - start))
auth=$(http_code "http://127.0.0.1:$HTTP_PORT/" "wine:$PW")
anon=$(http_code "http://127.0.0.1:$HTTP_PORT/" "")
if ! wait_app 120; then
  docker logs --tail 40 "$APP" >&2 || true
  echo "bench: no application window within 120 s" >&2
  exit 1
fi
app_ms=$(($(now_ms) - start))
x_ok=no
docker exec "$APP" xdpyinfo -display :99 >/dev/null 2>&1 && x_ok=yes
# docker stats includes page cache, which keeps growing after start while the
# working set has settled; the minimum of three samples is the honest number.
idle=""
for _ in 1 2 3; do
  sample=$(mem_kb "$APP")
  if [ "$sample" -gt 0 ] && { [ -z "$idle" ] || [ "$sample" -lt "$idle" ]; }; then
    idle=$sample
  fi
  sleep 1
done
rss_kb=${idle:-0}

echo "==> TLS default"
docker rm -f "$TLS" >/dev/null 2>&1 || true
docker run -d ${plat[@]+"${plat[@]}"} --name "$TLS" -e ENABLE_VNC=1 -e VNC_PASSWORD="$PW" \
  -p "127.0.0.1::${DESKTOP_PORT}" "$IMAGE" >/dev/null
TLS_PORT=$(host_port "$TLS")
[ -n "$TLS_PORT" ] || { echo "bench: no published TLS port" >&2; exit 1; }
wait_http "https://127.0.0.1:$TLS_PORT/" "wine:$PW" 120 || { echo "bench: TLS listener failed" >&2; exit 1; }
tls=$(http_code "https://127.0.0.1:$TLS_PORT/" "wine:$PW")
plain=$(http_code "http://127.0.0.1:$TLS_PORT/" "")

echo "==> auth guard"
if docker run --rm ${plat[@]+"${plat[@]}"} -e ENABLE_VNC=1 "$IMAGE" >"$tmp/guard.log" 2>&1; then
  guard=fail
else
  guard=ok
fi

echo "==> self-test"
selftest_dir="$tmp/selftest"
mkdir -p "$selftest_dir"
# The seeded default covers a failed docker run or a crash before the report is
# read; a completed run overwrites it.
printf 'false 0 0\n' >"$tmp/selftest.summary"
selftest_start=$(now_ms)
OUT_DIR="$selftest_dir" IMAGE="$IMAGE" PLATFORM="$PLATFORM" SUMMARY_FILE="$tmp/selftest.summary" \
  ./scripts/selftest.sh >"$tmp/selftest.log" 2>&1 || true
selftest_ms=$(($(now_ms) - selftest_start))
if [ -n "$EVIDENCE" ]; then
  cp "$selftest_dir/report.json" "$evidence"/ 2>/dev/null || true
  cp "$selftest_dir"/*.png "$evidence"/ 2>/dev/null || true
fi
read -r selftest_ok selftest_steps _ <"$tmp/selftest.summary"

# bench-report-keys: image platform cpus size_bytes start_ms app_ms auth_status anon_status tls_status plain_on_tls_port x_display idle_rss_kb auth_guard selftest_ok selftest_steps selftest_ms
json=$(printf '{\n  "image": "%s",\n  "platform": "%s",\n  "cpus": %s,\n  "size_bytes": %s,\n  "start_ms": %s,\n  "app_ms": %s,\n  "auth_status": %s,\n  "anon_status": %s,\n  "tls_status": %s,\n  "plain_on_tls_port": %s,\n  "x_display": "%s",\n  "idle_rss_kb": %s,\n  "auth_guard": "%s",\n  "selftest_ok": %s,\n  "selftest_steps": %s,\n  "selftest_ms": %s\n}' \
  "$IMAGE" "${PLATFORM:-native}" "$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)" \
  "$size" "$start_ms" "$app_ms" "${auth:-0}" "${anon:-0}" "${tls:-0}" "${plain:-0}" \
  "$x_ok" "$rss_kb" "$guard" "$selftest_ok" "$selftest_steps" "$selftest_ms")

if [ -n "$OUT" ]; then printf '%s\n' "$json" >"$OUT"; echo "==> wrote $OUT"; else printf '%s\n' "$json"; fi
