# winforms-wine-runtime

**简体中文** · [English](README.md)

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
# 仅本地标签；发布镜像是 CalVer 标签。
docker run --rm -p 6901:6901 \
  -e ENABLE_VNC=1 -e VNC_PASSWORD=change-me \
  -v wine-prefix:/wine -v app-data:/data \
  ghcr.io/webees/winforms-wine-runtime:dev-demo
```

打开 <https://localhost:6901>，接受自签证书，输入密码，即可看到 1280×720
桌面中的自检程序。
若前置了负责 TLS 的反向代理，设置 `-e KASMVNC_SSL=0`。

> GHCR 上发布的是运行时镜像（`ghcr.io/webees/winforms-wine-runtime`），
> 不含自检程序。`-demo` 标签只在本地构建，用于验证；只有
> `--target demo` 会把自检程序加进去，直接 `docker build .` 得到的是不含
> 任何应用的运行时。`dev` 与 `dev-demo` 仅限本地，不会推送。

> **版本采用 CalVer：** Git 标签为 `vYYYY.MM.DD`，GHCR 标签为
> `YYYY.MM.DD`。只有 `latest` 是移动别名；生产环境请固定具体日期标签或
> digest。详见 [docs/versioning.md](docs/versioning.md)。

## 用自己的程序

```dockerfile
FROM ghcr.io/webees/winforms-wine-runtime:2026.11.22.1
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
| `UBUNTU_DIGEST` | `sha256:d66b…` | 基础镜像 digest 固定；标签由 `UBUNTU_VERSION` 提供 |
| `DOTNET_SDK_IMAGE` | `mcr.microsoft.com/dotnet/sdk:8.0` | 编译自检程序 |
| `DOTNET_SDK_DIGEST` | `sha256:1b95…` | SDK 镜像 digest 固定 |
| `WEBVIEW2_VERSION` | `135.0.3179.98` | Fixed Version 运行时，版本上限见「WebView2 版本策略」 |
| `WEBVIEW2_SHA256` | `a6647e…` | NuGet 包校验值；升级 `WEBVIEW2_VERSION` 时同步更新 |
| `KASMVNC_VERSION` | `1.5.2` | KasmVNC 版本；SHA-256 只对 1.5.2 有效，覆盖版本需同步改校验值 |
| `KASMVNC_VIDEO` | `1` | 安装 FFmpeg，提供 H.264/H.265/AV1 编码 |
| `WINE64_ONLY` | `1` | 去掉 32 位 Wine（`i386-windows`、`syswow64`），约 1.2 GB |
| `IMAGE_VERSION` | `dev` | `org.opencontainers.image.version` 标签 |
| `SOURCE_REVISION` | `unknown` | `org.opencontainers.image.revision` 标签 |
| `TARGETARCH` | `amd64` | 由 BuildKit 注入；只接受 `amd64` |

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `LANG` | `C.UTF-8` | Wine 及其辅助进程使用的区域设置 |
| `APP` | `/app` 下第一个 `*.exe` | 启动的可执行文件：`/app` 下的裸文件名或 Linux 绝对路径；不接受 `C:\...` 这类 Windows 路径 |
| `APP_ARGS` | 空 | 额外参数，按空白切分，不支持引号 |
| `SCREEN` | `1280x720x24` | 桌面分辨率与色深 |
| `ENABLE_VNC` | `0` | `1` 启动 KasmVNC |
| `VNC_PASSWORD` | 空 | HTTP Basic 密码，至少 6 位 |
| `KASMVNC_PORT` | `6901` | 网页、WebSocket 与桌面端口 |
| `KASMVNC_LISTEN` | `0.0.0.0` | KasmVNC 绑定地址 |
| `KASMVNC_SSL` | `1` | `1` 用自签证书提供 HTTPS |
| `KASMVNC_CERT` | 空 | 包含证书与私钥的 PEM，覆盖自签证书 |
| `KASMVNC_ALLOW_NO_AUTH` | `0` | `1` 允许无认证桌面 |
| `KASMVNC_FRAME_RATE` | `15` | 编码帧率上限 |
| `KASMVNC_QUALITY_MIN` / `KASMVNC_QUALITY_MAX` | `5` / `8` | 动态 JPEG/WebP 质量下限与上限（0–9） |
| `KASMVNC_VIDEO_CODEC` | `auto` | `auto`、`h264`、`h265`、`av1` 或对应的 `*_vaapi` |
| `KASMVNC_RECT_THREADS` | `1` | 编码线程数，`0` 表示自动 |
| `KASMVNC_PREFER_BANDWIDTH` | `1` | `1` 时牺牲画质换带宽（更低质量档、更强压缩） |
| `DOTNET_GCHeapHardLimit` / `DOTNET_gcServer` / `DOTNET_TieredPGO` | `0x10000000` / `0` / `0` | .NET 堆上限 256 MiB，关闭服务器 GC 与分层 PGO |
| `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` | 见 `Dockerfile` | Chromium 参数：软件渲染、单渲染进程、JS 堆 256 MiB、禁止后台流量 |
| `WEBVIEW2_USER_DATA_FOLDER` | 空 | 镜像不设置；应用应自行向 `CreateAsync` 传 `userDataFolder`（自检程序用 `Z:\data\wv2`） |

自动探测只扫描 `/app` 顶层（不递归），并跳过 `createdump.exe`、`*.vshost.exe`
这类运行时辅助程序；`APP` 指定子目录时用相对路径，例如 `sub/YourApp.exe`。

## WebView2：必须写的一行代码

Wine 下 WebView2 加载器不会自己发现 Fixed Version 运行时，
`WEBVIEW2_BROWSER_EXECUTABLE_FOLDER` 也不会被读取；只有应用把目录显式传给
加载器时才会生效。

```csharp
var dir = Environment.GetEnvironmentVariable("WEBVIEW2_BROWSER_EXECUTABLE_FOLDER"); // C:\webview2
var env = await CoreWebView2Environment.CreateAsync(
    dir, userDataFolder, new CoreWebView2EnvironmentOptions());
await webView.EnsureCoreWebView2Async(env);
```

镜像内 `C:\webview2` 是固定路径，`dir` 也可以直接写死。用 Windows API 访问
`C:\webview2` 时，操作的是 Wine prefix，而不是宿主机目录。

## WebView2 版本策略

镜像使用 **Fixed Version** 运行时（NuGet `webview2.runtime.x64`），而不是
Evergreen 安装器，因为安装器在 Wine 下无法运行。

Wine 10 目前支持到 **135.0.3179.98**；136 及以后能启动 renderer，但导航和
`postMessage` 桥接永远不完成。升级 `WEBVIEW2_VERSION` 前必须运行
`scripts/bisect-webview2.sh` 和自检，不能只改版本号。

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

## 本地构建

```bash
make build          # 运行时 + 自检两个目标
make test           # 在容器里跑自检
make bench          # 测体积、启动、内存并写出 bench.json
make score          # 评分，低于 90 分失败
make baseline       # 统计跟踪的文件数、行数与字节数
make rubric-test    # 两套评分规则的单测
make lint           # 格式化、静态检查、评分单测与质量门禁
```

arm64 宿主机上所有目标都走 QEMU 模拟，可用但很慢；CI 与生产使用原生 x86-64。

## 文档

- [docs/architecture.md](docs/architecture.md) — 分层、启动流程、构建决策
- [docs/versioning.md](docs/versioning.md) — CalVer 版本规范与发布流程
- [docs/ports-and-volumes.md](docs/ports-and-volumes.md) — 端口与持久化
- [docs/network-tuning.md](docs/network-tuning.md) — 延迟、TCP、MTU 与 KasmVNC 调优
- [docs/troubleshooting.md](docs/troubleshooting.md) — 已知故障与处理
- [docs/benchmark.md](docs/benchmark.md) — 基线数据与评分口径
- [docs/quality.md](docs/quality.md) — 工程质量评分口径、检查项与 100 分门槛

## 许可

本仓库 MIT；Wine、WebView2 运行时、KasmVNC、字体等各自遵循原许可。
**KasmVNC 为 GPL-2.0**，再分发镜像时需要注意，见
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
