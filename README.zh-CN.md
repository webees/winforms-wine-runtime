# winforms-wine-runtime

在 Linux 容器里运行 **.NET 8 WinForms** 桌面程序（含 **WebView2**、**SunnyUI**、
**Magick.NET**），通过浏览器访问。

镜像只提供运行时：Wine 10、Xvfb、WebView2 Fixed Version、中文字体映射、
Chromium 需要的 MSVC 运行库。业务程序以自包含 `win-x64` 发布产物拷入 `/app`。

## 为什么

- 每个会话 300–500 MB，而不是 Windows 虚拟机的 4–8 GB。
- 不需要 Windows 授权；Windows 客户端版也不允许多会话托管。
- 用现有的容器与 K8s 体系发布。

## 快速开始

```bash
make build-demo
docker run --rm -p 6080:6080 \
  -e ENABLE_VNC=1 -e VNC_PASSWORD=change-me \
  -v wine-prefix:/wine -v app-data:/data \
  winforms-wine-runtime:dev-demo
```

打开 <http://localhost:6080/vnc.html> 输入密码，即可看到自检程序。

> GHCR 上发布的是运行时镜像（`ghcr.io/webees/winforms-wine-runtime`），
> 不含自检程序。`-demo` 标签只在本地构建，用于验证。

## 用自己的程序

```dockerfile
FROM ghcr.io/webees/winforms-wine-runtime:1
COPY publish/ /app/
ENV APP=YourApp.exe
```

```bash
dotnet publish -c Release -r win-x64 --self-contained true -o publish
docker build -t your-app .
docker run --rm -p 6080:6080 -e ENABLE_VNC=1 -e VNC_PASSWORD=change-me your-app
```

## 端口

| 端口 | 默认 | 用途 |
|---|---|---|
| `6080/tcp` | 发布 | noVNC 网页（`/vnc.html`） |
| `5900/tcp` | 仅回环 | 原生 VNC，仅调试 |

VNC 默认绑定 `127.0.0.1`；把 `VNC_LISTEN` 改成其他地址时必须同时设置
`VNC_PASSWORD`，否则容器拒绝启动。

## 持久化

| 路径 | 内容 | 建议 |
|---|---|---|
| `/wine` | Wine prefix（`C:\`）、字体、注册表、WebView2 配置 | 命名卷或 PVC |
| `/data` | 业务数据、自检输出 | 命名卷或绑定挂载 |
| `/app` | 程序本体 | 镜像层或只读挂载 |

`/wine` 为空时首次启动会自动 `wineboot`（约 20 秒）。跨重启保留 `/wine`
可避免重复初始化并保留用户设置；Wine 大版本升级后建议重建。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `APP` | `/app` 下第一个 `*.exe` | 启动的可执行文件 |
| `APP_ARGS` | 空 | 额外参数 |
| `SCREEN` | `1600x900x24` | Xvfb 分辨率 |
| `ENABLE_VNC` | `0` | `1` 启动 x11vnc + noVNC |
| `VNC_PASSWORD` | 空 | VNC 密码 |
| `VNC_PORT` / `NOVNC_PORT` | `5900` / `6080` | 端口 |
| `VNC_LISTEN` | `127.0.0.1` | x11vnc 绑定地址 |

## 已验证

`--selftest --strict` 会输出四步报告：`sunnyui`、`magick`、`webview2`、
`webview2-shot`。CI 每次提交都执行，`report.json` 出现失败即构建失败。

## 限制

- **一个容器一个会话**：Wine prefix 与 WebView2 配置目录不支持并发写。
- **仅 amd64**：arm64 上的 Wine 无法运行 `win-x64` 程序。
- **无 GPU**：默认软件渲染，除非传入 `/dev/dri` 并调整 Chromium 参数。
- **无 Windows 外壳**：没有资源管理器和输入法，文本输入走浏览器或剪贴板。

## 安全

镜像执行任意 Windows 代码，**Wine 不是沙箱**。不要挂载宿主敏感目录或
Docker socket；不要把 VNC 暴露到公网。详见 [SECURITY.md](SECURITY.md)。

## 许可

本仓库 MIT；Wine、WebView2 运行时、noVNC、字体等各自遵循原许可，见
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
