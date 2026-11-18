# syntax=docker/dockerfile:1.7
#
# winforms-wine-runtime
#
# Base image for running .NET 8 WinForms applications on Linux containers:
# Wine 10 + KasmVNC, with the WebView2 Fixed Version runtime, CJK font
# substitution and the MSVC runtime that Wine does not ship.
#
# Applications must be published self-contained for win-x64:
#   dotnet publish -c Release -r win-x64 --self-contained true
#
# Target base (default): runtime only, no application.
# Target demo:           runtime + self-test app used by CI.

ARG UBUNTU_VERSION=26.04
ARG UBUNTU_DIGEST=sha256:d66b366dac61b575bee2aef07e9c26e8070096fbe84a3d4d3eb0da069b5d76db
ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:8.0
ARG DOTNET_SDK_DIGEST=sha256:1b955f179b02df4f0eb5fadedaa898cbe44d620a64aab52eec72c8e91d1355b5
ARG WEBVIEW2_VERSION=135.0.3179.98
ARG WEBVIEW2_SHA256=a6647e22379156781d07894a59382e62bfb1b1413edbdb335ecbd811a8c72245
ARG KASMVNC_VERSION=1.5.2

FROM ${DOTNET_SDK_IMAGE}@${DOTNET_SDK_DIGEST} AS selftest-build
WORKDIR /src
COPY src/SelfTest/ ./
RUN dotnet publish SelfTest.csproj -c Release -r win-x64 --self-contained true \
      -p:PublishSingleFile=false -o /out/app

# Wine 9 (Ubuntu 24.04) cannot load .NET 8 managed assemblies
# (System.Runtime.dll -> ERROR_MOD_NOT_FOUND). Wine 10 (Ubuntu 26.04) works.
FROM ubuntu:${UBUNTU_VERSION}@${UBUNTU_DIGEST} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_VERSION
ARG WEBVIEW2_VERSION
ARG WEBVIEW2_SHA256
ARG KASMVNC_VERSION
# Set by BuildKit; the default keeps the classic builder working.
ARG TARGETARCH=amd64
# 1 = install FFmpeg so KasmVNC can stream WebCodecs H.264/H.265/AV1 video.
# The server dlopen()s libavcodec at runtime and silently falls back to
# WebP/JPEG when it is missing.
ARG KASMVNC_VIDEO=1
# 1 = 64-bit Wine only: drops i386-windows and syswow64 (~1.2 GB of image).
# Build with --build-arg WINE64_ONLY=0 if the application ships 32-bit native
# dependencies or a 32-bit installer.
ARG WINE64_ONLY=1
ARG IMAGE_VERSION=dev
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
    SCREEN=1280x720x24 \
    WINEPREFIX=/wine \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES=mshtml= \
    ENABLE_VNC=0 \
    KASMVNC_PORT=6901 \
    KASMVNC_LISTEN=0.0.0.0 \
    KASMVNC_SSL=1 \
    KASMVNC_FRAME_RATE=15 \
    KASMVNC_QUALITY_MIN=5 \
    KASMVNC_QUALITY_MAX=8 \
    KASMVNC_RECT_THREADS=1 \
    KASMVNC_PREFER_BANDWIDTH=1 \
    WEBVIEW2_BROWSER_EXECUTABLE_FOLDER='C:\webview2' \
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--no-sandbox --disable-gpu --disable-dev-shm-usage --disable-features=RendererCodeIntegrity,NetworkServiceSandbox --disable-background-networking --disable-component-update --disable-domain-reliability --disable-sync --disable-breakpad --metrics-recording-only --no-first-run --no-default-browser-check --disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows'

# Distro packages, the SHA-256 pinned KasmVNC .deb, and the wineserver shim.
RUN set -eu; \
    # WebView2 ships an x64 runtime only, so any other arch yields a broken image.
    [ "$TARGETARCH" = "amd64" ] || { \
      echo "winforms-wine-runtime supports linux/amd64 only (got $TARGETARCH)" >&2; exit 1; }; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl unzip openssl tini \
      wine wine64 xvfb xauth x11-utils iproute2 \
      fontconfig fonts-wqy-microhei fonts-droid-fallback \
      libgl1 libglx-mesa0 libegl1 libgles2 libvulkan1; \
    if [ "$KASMVNC_VIDEO" = "1" ]; then \
      apt-get install -y --no-install-recommends ffmpeg; \
    fi; \
    sha=caaae8b563570cabed436914187b961f7b563f9e4473e3bb3b09d99e0fd3348d; \
    curl -fsSLo /tmp/kasmvnc.deb \
      "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_ubuntu_resolute_${KASMVNC_VERSION}_${TARGETARCH}.deb"; \
    printf '%s  %s\n' "$sha" /tmp/kasmvnc.deb | sha256sum -c -; \
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb; \
    rm -f /tmp/kasmvnc.deb; \
    rm -rf /var/lib/apt/lists/*; \
    if [ "$WINE64_ONLY" = "1" ]; then rm -rf /usr/lib/*/wine/i386-windows; fi; \
    srv=$(find /usr/lib -name wineserver -type f -print -quit); \
    [ -n "$srv" ] || { echo "wineserver not found" >&2; exit 1; }; \
    ln -sf "$srv" /usr/local/bin/wineserver; \
    wineserver --version

# Wine resolves family names through fontconfig; without these aliases controls
# that ask for 微软雅黑 / SimSun render CJK text as tofu.
RUN set -eu; \
    { echo '<?xml version="1.0"?>'; \
      echo '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">'; \
      echo '<fontconfig>'; \
      for fam in '微软雅黑' '微软雅黑 UI' SimSun SimHei 宋体; do \
        echo "  <alias binding=\"same\"><family>$fam</family><prefer><family>WenQuanYi Micro Hei</family></prefer></alias>"; \
      done; \
      echo '</fontconfig>'; \
    } > /etc/fonts/conf.d/69-win-cjk-alias.conf; \
    fc-cache -f >/dev/null; \
    fc-match '微软雅黑'

# WebView2 Fixed Version runtime (NuGet distribution, no Evergreen installer).
# msedge.dll is Chromium itself: without it msedgewebview2.exe exits 13 with no
# output and applications only see a 60 s timeout. WEBVIEW2_SHA256 is bound to
# WEBVIEW2_VERSION; bump both together.
RUN set -eu; \
    mkdir -p /tmp/wv /opt/webview2; \
    curl -fsSL -o /tmp/wv/wv.nupkg \
      "https://api.nuget.org/v3-flatcontainer/webview2.runtime.x64/${WEBVIEW2_VERSION}/webview2.runtime.x64.${WEBVIEW2_VERSION}.nupkg"; \
    echo "${WEBVIEW2_SHA256}  /tmp/wv/wv.nupkg" | sha256sum -c -; \
    unzip -q /tmp/wv/wv.nupkg -d /tmp/wv; \
    cp -a /tmp/wv/contentFiles/any/any/WebView2/. /opt/webview2/; \
    find /opt/webview2 -type f \( -iname '*.exe' -o -iname '*.dll' \) -exec chmod 0755 {} +; \
    test -f /opt/webview2/msedge.dll || { \
      echo "ERROR: ${WEBVIEW2_VERSION} does not bundle msedge.dll (Chromium core)" >&2; \
      exit 1; \
    }; \
    test -x /opt/webview2/msedgewebview2.exe; \
    rm -rf /tmp/wv

COPY docker/wine-setup.sh /usr/local/bin/wine-setup.sh

# The prefix, the CJK fonts and the Windows version are one layer: Wine only
# flushes the registry when wineserver exits, so the font adds must follow
# wineboot in the same build step.
RUN set -eu; \
    chmod 0755 /usr/local/bin/wine-setup.sh; \
    setup_id="$( { sha256sum /usr/local/bin/wine-setup.sh \
        /usr/share/fonts/truetype/wqy/wqy-microhei.ttc \
        /usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf; \
      printf '%s\n' "${WEBVIEW2_VERSION}"; } | sha256sum | cut -d' ' -f1)"; \
    xvfb-run -a --server-args="-screen 0 1280x720x24 -nolisten tcp -ac" \
      wineboot -u >/tmp/wineboot.log 2>&1 || true; \
    wineserver -w; \
    if [ "$WINE64_ONLY" = "1" ]; then rm -rf /wine/drive_c/windows/syswow64; fi; \
    xvfb-run -a --server-args="-screen 0 1280x720x24 -nolisten tcp -ac" \
      /usr/local/bin/wine-setup.sh; \
    printf '%s\n' "$setup_id" > /wine/.wfr-setup-id; \
    printf '%s\n' "$setup_id" > /etc/wfr-setup-id; \
    wineserver -w; \
    ln -sfn /opt/webview2 /wine/drive_c/webview2; \
    test -f /wine/drive_c/windows/system32/gdiplus.dll; \
    test -f /wine/drive_c/windows/Fonts/wqy-microhei.ttc; \
    test -x /wine/drive_c/webview2/msedgewebview2.exe; \
    grep -qi 'wine: created the configuration' /tmp/wineboot.log
COPY docker/entrypoint.sh /usr/local/bin/
RUN set -eu; \
    chmod 0755 /usr/local/bin/entrypoint.sh; \
    test "$(cat /etc/wfr-setup-id)" = "$(cat /wine/.wfr-setup-id)" || { \
      echo "wfr-setup-id stamps diverged: prefix layer and image fingerprint disagree" >&2; exit 1; }; \
    mkdir -p /app /data

WORKDIR /app

# KasmVNC serves the web client, the WebSocket and the desktop on this single
# port; see docs/ports-and-volumes.md.
EXPOSE 6901

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD ["bash", "-c", "xdpyinfo >/dev/null 2>&1 && { [ \"${ENABLE_VNC:-0}\" != 1 ] || [ -n \"$(ss -ltnH \"sport = :${KASMVNC_PORT:-6901}\")\" ]; }"]

# tini reaps zombies; the entrypoint replaces itself with the application.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD []

# Test target: the runtime plus the self-test application. Only `make
# build-demo`, CI and the benchmarks build this stage; it is never published.
FROM base AS demo
COPY --from=selftest-build /out/app /app

# Default stage: the runtime with an empty /app, so a plain `docker build .`
# (or `buildx build --push .` without --target) cannot ship an application.
FROM base
