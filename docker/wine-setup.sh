#!/usr/bin/env bash
# Wine prefix setup: runs at build time (after wineboot) and on every container
# start, so an existing prefix picks up new fonts, registry mappings and DLLs.
#
# Copies CJK fonts into C:\windows\Fonts and maps the Windows family names that
# WinForms applications ask for. Without this, SunnyUI and anything using
# 微软雅黑 / SimSun render every glyph as tofu under Wine.
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-/wine}"
export WINEDEBUG=-all

FONTDIR="${WINEPREFIX}/drive_c/windows/Fonts"
FONTS='HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
SUBS='HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
FALLBACK=DroidSansFallbackFull.ttf
SYSTEM='WenQuanYi Micro Hei'

mkdir -p "$FONTDIR"
cp -f /usr/share/fonts/truetype/wqy/wqy-microhei.ttc \
   /usr/share/fonts/truetype/droid/"$FALLBACK" \
   "$FONTDIR/"

reg() { wine reg add "$@" >/dev/null; }

reg "$FONTS" /v "Droid Sans Fallback (TrueType)" /d "$FALLBACK" /f
reg "$FONTS" /v "${SYSTEM} (TrueType)" /d wqy-microhei.ttc /f

for family in "微软雅黑" "微软雅黑 UI" SimSun SimHei 宋体 "MS Shell Dlg" "MS Shell Dlg 2" Tahoma; do
  reg "$SUBS" /v "$family" /d "$SYSTEM" /f
done

reg 'HKCU\Software\Wine' /v Version /d win10 /f

# WebView2 links against the VC++ 2015-2022 runtime; Wine ships no redistributable.
# Fail the build instead of shipping an image whose WebView2 exits with code 13.
shopt -s nullglob
msvc=(/opt/webview2/*140*.dll)
if [ "${#msvc[@]}" -eq 0 ]; then
  echo "error: no MSVC runtime DLLs (*140*.dll) in /opt/webview2" >&2
  exit 1
fi
# -f so a WebView2 upgrade refreshes the runtime DLLs instead of keeping stale ones.
cp -f "${msvc[@]}" "${WINEPREFIX}/drive_c/windows/system32/"

# grep without -q: reading to EOF keeps `wine` from dying on SIGPIPE, which
# pipefail would turn into a false failure.
wine reg query "$FONTS" | grep -F "Droid Sans Fallback" >/dev/null
