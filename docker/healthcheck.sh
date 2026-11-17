#!/usr/bin/env bash
# Healthy = X server responds and, when the desktop is enabled, KasmVNC accepts TCP.
set -euo pipefail

DISPLAY="${DISPLAY:-:99}"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || exit 1

if [ "${ENABLE_VNC:-0}" = "1" ]; then
  port="${KASMVNC_PORT:-6901}"
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null || exit 1
fi

exit 0
