#!/usr/bin/env bash
# Healthy = X server responds and, when the desktop is enabled, KasmVNC is
# listening on the configured port.
#
# The listening socket is checked with ss rather than bash's /dev/tcp: /dev/tcp
# does not handle IPv6 literals reliably, and ss also works when KasmVNC binds a
# specific address instead of 0.0.0.0.
set -euo pipefail

DISPLAY="${DISPLAY:-:99}"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1

if [ "${ENABLE_VNC:-0}" = "1" ]; then
  # No pipe into grep -q: grep would exit early and SIGPIPE ss, which pipefail
  # would report as unhealthy.
  [ -n "$(ss -ltnH "sport = :${KASMVNC_PORT:-6901}")" ]
fi
