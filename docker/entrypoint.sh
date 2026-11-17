#!/usr/bin/env bash
# Container entrypoint: Xvfb -> optional x11vnc/noVNC -> application.
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
SCREEN="${SCREEN:-1600x900x24}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_LISTEN="${VNC_LISTEN:-127.0.0.1}"
ENABLE_VNC="${ENABLE_VNC:-0}"
WINESERVER="${WINESERVER:-$(command -v wineserver || echo /usr/lib/x86_64-linux-gnu/wine/wineserver)}"

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] ERROR: %s\n' "$*" >&2; exit 1; }

PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# --- X server ---------------------------------------------------------------
if [ ! -e "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
  log "starting Xvfb on ${DISPLAY} (${SCREEN})"
  Xvfb "$DISPLAY" -screen 0 "$SCREEN" -nolisten tcp -ac >/tmp/xvfb.log 2>&1 &
  PIDS+=("$!")
  for _ in $(seq 1 50); do
    xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
    sleep 0.2
  done
fi
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || die "X server $DISPLAY did not start"

# --- Wine prefix ------------------------------------------------------------
mkdir -p "$WINEPREFIX" /data
if [ ! -f "$WINEPREFIX/system.reg" ]; then
  log "initialising Wine prefix at ${WINEPREFIX}"
  wineboot -u >/tmp/wineboot-runtime.log 2>&1 || true
  "$WINESERVER" -w
fi

# --- Remote desktop (opt-in) ------------------------------------------------
if [ "$ENABLE_VNC" = "1" ]; then
  if [ "$VNC_LISTEN" != "127.0.0.1" ] && [ "${VNC_PASSWORD:-}" = "" ]; then
    die "VNC_LISTEN=${VNC_LISTEN} requires VNC_PASSWORD to be set"
  fi
  VNC_ARGS=(-display "$DISPLAY" -rfbport "$VNC_PORT" -listen "$VNC_LISTEN" -forever -shared -noxdamage)
  if [ "${VNC_PASSWORD:-}" != "" ]; then
    umask 077
    x11vnc -storepasswd "$VNC_PASSWORD" /tmp/.vncpass >/dev/null 2>&1
    VNC_ARGS+=(-rfbauth /tmp/.vncpass)
  else
    VNC_ARGS+=(-nopw)
  fi
  log "starting x11vnc on ${VNC_LISTEN}:${VNC_PORT}"
  x11vnc "${VNC_ARGS[@]}" >/tmp/x11vnc.log 2>&1 &
  PIDS+=("$!")

  log "starting noVNC on :${NOVNC_PORT}"
  websockify --web /usr/share/novnc "$NOVNC_PORT" "127.0.0.1:${VNC_PORT}" \
    >/tmp/websockify.log 2>&1 &
  PIDS+=("$!")
else
  log "VNC disabled (ENABLE_VNC=0); set ENABLE_VNC=1 and publish port ${NOVNC_PORT} to attach a browser"
fi

# --- Application ------------------------------------------------------------
# .NET self-contained publishes ship helper executables (createdump.exe) that
# are not the application; ignore them when guessing.
APP="${APP:-$(find /app -maxdepth 1 -type f -iname '*.exe' \
      ! -iname 'createdump.exe' ! -iname '*.vshost.exe' -printf '%f\n' 2>/dev/null \
      | sort | head -n1)}"
[ -n "${APP:-}" ] || die "no .exe found in /app; set APP=<name.exe>"
case "$APP" in
  [A-Za-z]:\\*|/*) APP_PATH="$APP" ;;
  *)               APP_PATH="/app/$APP" ;;
esac
[ -f "$APP_PATH" ] || die "application not found: $APP_PATH"

read -r -a APP_ARGS <<< "${APP_ARGS:-}"
log "starting wine ${APP_PATH} ${APP_ARGS[*]:-}"
exec wine "$APP_PATH" "${APP_ARGS[@]}" "$@"
