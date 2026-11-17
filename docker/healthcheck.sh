#!/usr/bin/env bash
# Healthy = X server responds and, when VNC is enabled, noVNC accepts TCP.
set -euo pipefail

DISPLAY="${DISPLAY:-:99}"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || exit 1

if [ "${ENABLE_VNC:-0}" = "1" ]; then
  port="${NOVNC_PORT:-6080}"
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null || exit 1
  exec 3>&- 3<&-
fi

exit 0
