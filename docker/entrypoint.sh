#!/usr/bin/env bash
# X server -> optional KasmVNC desktop -> Wine application.
#
# Xkasmvnc is both the X server and the web/WebSocket server, so the desktop
# path has exactly one process. Xvfb is only used when ENABLE_VNC=0 (headless
# self-test and CI). See docs/architecture.md.
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/root}"

SCREEN="${SCREEN:-1600x900x24}"
IFS=x read -r width height depth <<<"$SCREEN"
depth="${depth:-24}"
if [[ ! $width =~ ^[0-9]+$ || ! $height =~ ^[0-9]+$ || ! $depth =~ ^[0-9]+$ ]]; then
  echo "entrypoint: error: SCREEN must be WIDTHxHEIGHT[xDEPTH], got '$SCREEN'" >&2
  exit 1
fi
SCREEN="${width}x${height}x${depth}"

PORT="${KASMVNC_PORT:-6901}"
LISTEN="${KASMVNC_LISTEN:-0.0.0.0}"
# Runtime state lives under /tmp so --read-only only needs /tmp, /wine and
# /data writable. Both files are regenerated from VNC_PASSWORD on every start.
STATE_DIR="/tmp/.kasmvnc"
AUTH_FILE="${STATE_DIR}/kasm-auth"
CERT="${STATE_DIR}/self.pem"
LOG=/tmp/kasmvnc.log
WINESERVER="${WINESERVER:-/usr/local/bin/wineserver}"

CHILD=""
log() { printf '[entrypoint] %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }
cleanup() { [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null || true; }
trap cleanup EXIT

wait_for_display() {
  for _ in $(seq 1 100); do
    xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}

ensure_state_dir() {
  if ! mkdir -p "$STATE_DIR" || ! chmod 700 "$STATE_DIR"; then
    die "cannot create $STATE_DIR"
  fi
}

prepare_auth() {
  [ -n "${VNC_PASSWORD:-}" ] || return 1
  [ "${#VNC_PASSWORD}" -ge 6 ] || die "VNC_PASSWORD must be at least 6 characters"
  ensure_state_dir
  printf '%s\n%s\n' "$VNC_PASSWORD" "$VNC_PASSWORD" |
    kasmvncpasswd -u wine -w "$AUTH_FILE" >/dev/null || die "cannot write $AUTH_FILE"
  [ -s "$AUTH_FILE" ] || die "cannot write $AUTH_FILE"
  chmod 600 "$AUTH_FILE"
  log "HTTP basic auth enabled for user 'wine'"
}

prepare_cert() {
  [ -n "${KASMVNC_CERT:-}" ] && { [ -r "$KASMVNC_CERT" ] || die "KASMVNC_CERT unreadable: $KASMVNC_CERT"; return 0; }
  [ -s "$CERT" ] && { KASMVNC_CERT="$CERT"; return 0; }
  ensure_state_dir
  log "generating a self-signed certificate at $CERT"
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=winforms-wine-runtime" \
    -keyout "$CERT.key" -out "$CERT.crt" >/dev/null 2>&1 || die "openssl failed"
  cat "$CERT.crt" "$CERT.key" >"$CERT"
  rm -f "$CERT.crt" "$CERT.key"
  chmod 600 "$CERT"
  KASMVNC_CERT="$CERT"
}

start_desktop() {
  local args=("$DISPLAY" -geometry "${width}x${height}" -depth "$depth"
    -interface "$LISTEN" -websocketPort "$PORT" -httpd /usr/share/kasmvnc/www
    -SecurityTypes None
    -FrameRate "${KASMVNC_FRAME_RATE:-30}"
    -DynamicQualityMin "${KASMVNC_QUALITY_MIN:-7}"
    -DynamicQualityMax "${KASMVNC_QUALITY_MAX:-8}"
    -RectThreads "${KASMVNC_RECT_THREADS:-0}"
    -videoCodec "${KASMVNC_VIDEO_CODEC:-auto}")

  if prepare_auth; then
    args+=(-KasmPasswordFile "$AUTH_FILE")
  elif [ "${KASMVNC_ALLOW_NO_AUTH:-0}" = "1" ]; then
    log "warning: VNC_PASSWORD is unset, the desktop is reachable without authentication"
    args+=(-disableBasicAuth)
  else
    die "set VNC_PASSWORD, or KASMVNC_ALLOW_NO_AUTH=1 for an unauthenticated desktop"
  fi

  if [ "${KASMVNC_SSL:-1}" = "1" ]; then
    prepare_cert
    args+=(-cert "$KASMVNC_CERT" -sslOnly)
    log "KasmVNC listening on https://${LISTEN}:${PORT}"
  else
    log "warning: TLS disabled, terminate TLS in front of port ${PORT}"
    log "KasmVNC listening on http://${LISTEN}:${PORT}"
  fi

  Xkasmvnc "${args[@]}" >"$LOG" 2>&1 &
  CHILD=$!
  if ! wait_for_display; then
    tail -n 40 "$LOG" >&2 || true
    die "KasmVNC failed to start"
  fi
}

start_xvfb() {
  log "starting Xvfb on ${DISPLAY} (${SCREEN})"
  Xvfb "$DISPLAY" -screen 0 "$SCREEN" -nolisten tcp -ac >/tmp/xvfb.log 2>&1 &
  CHILD=$!
  wait_for_display || { tail -n 20 /tmp/xvfb.log >&2 || true; die "Xvfb failed to start"; }
}

if [ "${ENABLE_VNC:-0}" = "1" ]; then start_desktop; else start_xvfb; fi

if [ ! -f "${WINEPREFIX}/system.reg" ]; then
  log "initialising Wine prefix at ${WINEPREFIX}"
  wineboot -u >/tmp/wineboot-runtime.log 2>&1 || true
  "$WINESERVER" -w
fi

# Self-contained publishes also ship createdump.exe; it is not the app.
APP="${APP:-$(find /app -maxdepth 1 -type f -iname '*.exe' \
  ! -iname createdump.exe ! -iname '*.vshost.exe' -printf '%f\n' 2>/dev/null | sort | head -n1)}"
[ -n "$APP" ] || die "no .exe in /app; set APP=<name.exe>"
case "$APP" in
  [A-Za-z]:\\*|/*) APP_PATH="$APP" ;;
  *) APP_PATH="/app/$APP" ;;
esac
[ -f "$APP_PATH" ] || die "application not found: $APP_PATH"

read -r -a APP_ARGS <<<"${APP_ARGS:-}"
log "starting wine ${APP_PATH} ${APP_ARGS[*]:-}"
exec wine "$APP_PATH" "${APP_ARGS[@]}" "$@"
