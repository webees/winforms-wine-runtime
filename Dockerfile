# syntax=docker/dockerfile:1.7
#
# winforms-wine-runtime
#
# Base image for running .NET 8 WinForms applications on Linux containers:
# Wine 10 + Xvfb + optional noVNC, with the WebView2 Fixed Version runtime,
# CJK font substitution and the MSVC runtime that Wine does not ship.
#
# Applications must be published self-contained for win-x64:
#   dotnet publish -c Release -r win-x64 --self-contained true
#
# Target base (default): runtime only, no application.
# Target demo:           runtime + self-test app used by CI.

ARG UBUNTU_VERSION=26.04
ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:8.0
ARG WEBVIEW2_VERSION=135.0.3179.98

FROM ${DOTNET_SDK_IMAGE} AS selftest-build
WORKDIR /src
COPY src/self-test/ ./
RUN dotnet publish SelfTest.csproj -c Release -r win-x64 --self-contained true \
      -p:PublishSingleFile=false -o /out/app

# Wine 9 (Ubuntu 24.04) cannot load .NET 8 managed assemblies
# (System.Runtime.dll -> ERROR_MOD_NOT_FOUND). Wine 10 (Ubuntu 26.04) works.
FROM ubuntu:${UBUNTU_VERSION} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG WEBVIEW2_VERSION
# 1 = 64-bit Wine only: drops i386-windows and syswow64 (~1.6 GB of image).
# Build with --build-arg WINE64_ONLY=0 if the application ships 32-bit native
# dependencies or a 32-bit installer.
ARG WINE64_ONLY=1
ARG IMAGE_VERSION=0.0.0
ARG SOURCE_REVISION=unknown

LABEL org.opencontainers.image.title="winforms-wine-runtime" \
      org.opencontainers.image.description="Run .NET 8 WinForms + WebView2 + SunnyUI + Magick.NET applications in Linux containers (Wine 10)" \
      org.opencontainers.image.url="https://github.com/webees/winforms-wine-runtime" \
      org.opencontainers.image.source="https://github.com/webees/winforms-wine-runtime" \
      org.opencontainers.image.documentation="https://github.com/webees/winforms-wine-runtime#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:${UBUNTU_VERSION}"

ENV LANG=C.UTF-8 \
    DISPLAY=:99 \
    SCREEN=1600x900x24 \
    WINEPREFIX=/wine \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES=mshtml= \
    ENABLE_VNC=0 \
    VNC_PORT=5900 \
    NOVNC_PORT=6080 \
    VNC_LISTEN=127.0.0.1 \
    WEBVIEW2_BROWSER_EXECUTABLE_FOLDER='C:\webview2' \
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--no-sandbox --disable-gpu --disable-dev-shm-usage --disable-features=RendererCodeIntegrity,NetworkServiceSandbox'

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip xz-utils \
      wine wine64 \
      xvfb x11-utils x11vnc novnc websockify scrot \
      fontconfig fonts-wqy-microhei fonts-droid-fallback fonts-liberation fonts-dejavu-core \
      libgl1 libglx-mesa0 libegl1 libgles2 libvulkan1 \
      procps tini \
    && rm -rf /var/lib/apt/lists/* \
    && if [ "$WINE64_ONLY" = "1" ]; then rm -rf /usr/lib/x86_64-linux-gnu/wine/i386-windows; fi \
    && ln -sf "$(find /usr/lib -name wineserver -type f | head -n1)" /usr/local/bin/wineserver \
    && wineserver --version

# Wine resolves font family names through fontconfig. Without these aliases,
# controls that ask for Microsoft YaHei / SimSun render CJK text as tofu.
RUN printf '%s\n' \
      '<?xml version="1.0"?>' \
      '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">' \
      '<fontconfig>' \
      '  <alias binding="same"><family>Microsoft YaHei</family><prefer><family>WenQuanYi Micro Hei</family></prefer></alias>' \
      '  <alias binding="same"><family>Microsoft YaHei UI</family><prefer><family>WenQuanYi Micro Hei</family></prefer></alias>' \
      '  <alias binding="same"><family>SimSun</family><prefer><family>WenQuanYi Micro Hei</family></prefer></alias>' \
      '  <alias binding="same"><family>SimHei</family><prefer><family>WenQuanYi Micro Hei</family></prefer></alias>' \
      '  <alias binding="same"><family>宋体</family><prefer><family>WenQuanYi Micro Hei</family></prefer></alias>' \
      '  <alias binding="same"><family>微软雅黑</family><prefer><family>WenQuanYi Micro Hei</family></prefer></alias>' \
      '</fontconfig>' \
      > /etc/fonts/conf.d/69-win-cjk-alias.conf \
    && fc-cache -f >/dev/null \
    && fc-match "Microsoft YaHei"

# WebView2 Fixed Version runtime (NuGet distribution, no Evergreen installer).
# msedge.dll (Chromium itself) must exist: without it msedgewebview2.exe exits
# with code 13 and no output, and applications only see a 60 s timeout.
WORKDIR /tmp/wv
RUN mkdir -p /opt/webview2 \
    && curl -fsSL -o wv.nupkg \
       "https://api.nuget.org/v3-flatcontainer/webview2.runtime.x64/${WEBVIEW2_VERSION}/webview2.runtime.x64.${WEBVIEW2_VERSION}.nupkg" \
    && unzip -q wv.nupkg \
    && cp -a contentFiles/any/any/WebView2/. /opt/webview2/ \
    && find /opt/webview2 -type f \( -iname '*.exe' -o -iname '*.dll' \) -exec chmod 0755 {} + \
    && test -x /opt/webview2/msedgewebview2.exe \
    && test -f /opt/webview2/msedge.dll \
    && rm -rf /tmp/wv \
    || { echo "ERROR: ${WEBVIEW2_VERSION} does not bundle msedge.dll (Chromium core); it cannot run in this container" >&2; exit 1; }

WORKDIR /

# Pre-initialise the Wine prefix. wineserver must be allowed to exit on its own,
# otherwise GDI+ Bitmap.Save() fails with a generic error at runtime.
RUN Xvfb :98 -screen 0 1600x900x24 -nolisten tcp -ac >/tmp/xvfb98.log 2>&1 & \
    XPID=$!; \
    sleep 2; \
    DISPLAY=:98 timeout 240 wineboot -u >/tmp/wineboot.log 2>&1; \
    DISPLAY=:98 timeout 180 wineserver -w; \
    kill "$XPID" 2>/dev/null || true; \
    if [ "$WINE64_ONLY" = "1" ]; then rm -rf /wine/drive_c/windows/syswow64; fi; \
    test -f /wine/drive_c/windows/system32/gdiplus.dll; \
    test -f /wine/drive_c/windows/system32/kernel32.dll; \
    grep -qi 'wine: created the configuration' /tmp/wineboot.log

# Fonts must be installed *after* the prefix exists: Wine flushes its registry
# when the server exits, so entries written during wineboot are lost.
#
# Two renderers matter. GDI+ (WinForms) finds a font in C:\windows\Fonts and
# honours FontSubstitutes. DirectWrite (Chromium in WebView2) only sees fonts
# registered in the Fonts key, and it does not load .ttc collections, so a
# plain .ttf is installed as well.
RUN Xvfb :96 -screen 0 1600x900x24 -nolisten tcp -ac >/tmp/xvfb96.log 2>&1 & \
    XPID=$!; \
    sleep 2; \
    cp /usr/share/fonts/truetype/wqy/wqy-microhei.ttc /wine/drive_c/windows/Fonts/; \
    cp /usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf /wine/drive_c/windows/Fonts/; \
    DISPLAY=:96 timeout 120 wine reg add \
      "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts" \
      /v "Droid Sans Fallback (TrueType)" /d "DroidSansFallbackFull.ttf" /f; \
    DISPLAY=:96 timeout 120 wine reg add \
      "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts" \
      /v "WenQuanYi Micro Hei (TrueType)" /d "wqy-microhei.ttc" /f; \
    for f in "Microsoft YaHei" "Microsoft YaHei UI" SimSun SimHei 宋体 微软雅黑 "MS Shell Dlg" "MS Shell Dlg 2" Tahoma; do \
      DISPLAY=:96 timeout 120 wine reg add \
        "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes" \
        /v "$f" /d "WenQuanYi Micro Hei" /f; \
    done; \
    DISPLAY=:96 timeout 180 wineserver -w; \
    kill "$XPID" 2>/dev/null || true; \
    test -f /wine/drive_c/windows/Fonts/wqy-microhei.ttc; \
    test -f /wine/drive_c/windows/Fonts/DroidSansFallbackFull.ttf; \
    DISPLAY=:96 timeout 60 wine reg query \
      "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts" \
      | grep -q "Droid Sans Fallback"; \
    DISPLAY=:96 timeout 60 wineserver -k || true

# msedgewebview2.exe needs the MSVC runtime; the Wine built-ins are incomplete.
RUN for dll in /opt/webview2/*140*.dll; do \
      [ -f "$dll" ] && cp -n "$dll" /wine/drive_c/windows/system32/ || true; \
    done

# Expose the Fixed Version runtime as C:\webview2 for
# WEBVIEW2_BROWSER_EXECUTABLE_FOLDER.
RUN mkdir -p /wine/drive_c && ln -sfn /opt/webview2 /wine/drive_c/webview2 \
    && test -x /wine/drive_c/webview2/msedgewebview2.exe

# Report Windows 10 so applications skip legacy code paths.
RUN Xvfb :97 -screen 0 1600x900x24 -nolisten tcp -ac >/tmp/xvfb97.log 2>&1 & \
    XPID=$!; \
    sleep 2; \
    DISPLAY=:97 timeout 60 wine reg add 'HKCU\Software\Wine' /v Version /d win10 /f >/tmp/winever.log 2>&1 || true; \
    DISPLAY=:97 timeout 120 wineserver -w; \
    kill "$XPID" 2>/dev/null || true

COPY docker/entrypoint.sh docker/healthcheck.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
    && mkdir -p /app /data

WORKDIR /app

# noVNC is the only port that should be published. The VNC server listens on
# loopback by default; see docs/ports-and-volumes.md before changing VNC_LISTEN.
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD []

FROM base AS demo
COPY --from=selftest-build /out/app /app
