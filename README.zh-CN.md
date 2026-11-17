# winforms-wine-runtime

在 Linux 容器里运行 **.NET 8 WinForms** 桌面程序（含 **WebView2**、**SunnyUI**、
**Magick.NET**），通过浏览器访问。

镜像只提供运行时：Wine 10、KasmVNC、WebView2 Fixed Version、中文字体映射、
Chromium 需要的 MSVC 运行库。业务程序以自包含 `win-x64` 发布产物拷入 `/app`。

## 为什么

- 每个会话 300–500 MB，而不是 Windows 虚拟机的 4–8 GB。
- 不需要 Windows 授权；Windows 客户端版也不允许多会话托管。
- 用现有的容器与 K8s 体系发布。

## 快速开始

```bash
make build-demo
docker run --rm -p 6901:6901 \
  -e ENABLE_VNC=1 -e VNC_PASSWORD=change-me \
  -v wine-prefix:/wine -v app-data:/data \
  ghcr.io/webees/winforms-wine-runtime:dev-demo
```

打开 <https://localhost:6901>，接受自签证书，输入密码，即可看到自检程序。
若前置了负责 TLS 的反向代理，设置 `-e KASMVNC_SSL=0`。

> GHCR 上发布的是运行时镜像（`ghcr.io/webees/winforms-wine-runtime`），
> 不含自检程序。`-demo` 标签只在本地构建，用于验证。

## 用自己的程序

```dockerfile
FROM ghcr.io/webees/winforms-wine-runtime:2
COPY publish/ /app/
ENV APP=YourApp.exe
```

```bash
dotnet publish -c Release -r win-x64 --self-contained true -o publish
docker build -t your-app .
docker run --rm -p 6901:6901 -e ENABLE_VNC=1 -e VNC_PASSWORD=change-me your-app
```

## 端口

| 端口 | 默认 | 用途 |
|---|---|---|
| `6901/tcp` | 发布 | KasmVNC 网页、WebSocket 与桌面 |

只有这一个端口。`KASMVNC_LISTEN` 默认 `0.0.0.0`；没有 `VNC_PASSWORD`
时容器拒绝启动，除非显式设置 `KASMVNC_ALLOW_NO_AUTH=1`。

## 持久化

| 路径 | 内容 | 建议 |
|---|---|---|
| `/wine` | Wine prefix（`C:\`）、字体、注册表、WebView2 配置 | 命名卷或 PVC |
| `/data` | 业务数据、自检输出 | 命名卷或绑定挂载 |
| `/app` | 程序本体 | 镜像层或只读挂载 |

`/wine` 为空时首次启动会自动 `wineboot`（约 20 秒）。跨重启保留 `/wine`
可避免重复初始化并保留用户设置；Wine 大版本升级后建议重建。

## 构建参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `UBUNTU_VERSION` | `26.04` | 基础发行版；22.04 与 24.04 自带 Wine 6.0 与 9.0，无法加载 .NET 8 |
| `DOTNET_SDK_IMAGE` | `mcr.microsoft.com/dotnet/sdk:8.0` | 编译自检程序 |
| `WEBVIEW2_VERSION` | `135.0.3179.98` | Fixed Version 运行时，版本上限见上文 |
| `KASMVNC_VERSION` | `1.5.2` | KasmVNC 版本，带 SHA-256 校验 |
| `KASMVNC_VIDEO` | `1` | 安装 FFmpeg，提供 H.264/H.265/AV1 编码 |
| `WINE64_ONLY` | `1` | 去掉 32 位 Wine（`i386-windows`、`syswow64`），约 1.2 GB |
| `IMAGE_VERSION` | `0.0.0` | `org.opencontainers.image.version` 标签 |
| `SOURCE_REVISION` | `unknown` | `org.opencontainers.image.revision` 标签 |
| `TARGETARCH` | `amd64` | 架构，多架构构建时由 BuildKit 设置 |

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `APP` | `/app` 下第一个 `*.exe` | 启动的可执行文件 |
| `APP_ARGS` | 空 | 额外参数 |
| `SCREEN` | `1600x900x24` | 桌面分辨率与色深 |
| `ENABLE_VNC` | `0` | `1` 启动 KasmVNC |
| `VNC_PASSWORD` | 空 | HTTP Basic 密码，至少 6 位 |
| `KASMVNC_PORT` | `6901` | 网页、WebSocket 与桌面端口 |
| `KASMVNC_LISTEN` | `0.0.0.0` | KasmVNC 绑定地址 |
| `KASMVNC_SSL` | `1` | `1` 用自签证书提供 HTTPS |
| `KASMVNC_CERT` | 空 | 包含证书与私钥的 PEM，覆盖自签证书 |
| `KASMVNC_ALLOW_NO_AUTH` | `0` | `1` 允许无认证桌面 |
| `KASMVNC_FRAME_RATE` | `30` | 编码帧率上限 |
| `KASMVNC_QUALITY_MIN` / `KASMVNC_QUALITY_MAX` | `7` / `8` | 动态 JPEG/WebP 质量下限与上限（0–9） |
| `KASMVNC_VIDEO_CODEC` | `auto` | `auto`、`h264`、`h265`、`av1` 或对应的 `*_vaapi` |
| `KASMVNC_RECT_THREADS` | `0` | 编码线程数，`0` 表示自动 |
| `WEBVIEW2_USER_DATA_FOLDER` | 空 | 覆盖 WebView2 配置目录位置 |

## 已验证

基线数值与评分口径见 [docs/benchmark.md](docs/benchmark.md)：`make bench` 生成
`bench.json`，`make score` 低于 90 分即失败，CI 与 release 都用同一套门槛。

`--selftest --strict` 会输出四步报告：`sunnyui`、`magick`、`webview2`、
`webview2-shot`。CI 每次提交都执行，`report.json` 出现失败即构建失败。

## 限制

- **一个容器一个会话**：Wine prefix 与 WebView2 配置目录不支持并发写。
- **仅 amd64**：arm64 上的 Wine 无法运行 `win-x64` 程序。
- **无 GPU**：默认软件渲染，除非传入 `/dev/dri` 并调整 Chromium 参数。
- **无 Windows 外壳**：没有资源管理器和任务栏。中文输入依赖 KasmVNC
  客户端的 IME 模式或粘贴，不经过 Windows 输入法。
- **仅 Web 客户端**：KasmVNC 不兼容通用 VNC 客户端，网页端是唯一入口。

## 安全

镜像执行任意 Windows 代码，**Wine 不是沙箱**。不要挂载宿主敏感目录或
Docker socket；只发布 `6901`，保持 TLS 开启（或在前置代理终止）。详见
[SECURITY.md](SECURITY.md)。

## 许可

本仓库 MIT；Wine、WebView2 运行时、KasmVNC、字体等各自遵循原许可。
**KasmVNC 为 GPL-2.0**，再分发镜像时需要注意，见
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
