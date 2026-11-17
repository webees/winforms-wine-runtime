#!/usr/bin/env bash
# Build-time Wine prefix setup, run once under xvfb-run after wineboot.
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
cp /usr/share/fonts/truetype/wqy/wqy-microhei.ttc \
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
cp -n /opt/webview2/*140*.dll "${WINEPREFIX}/drive_c/windows/system32/" 2>/dev/null || true

wine reg query "$FONTS" | grep -q "Droid Sans Fallback"
