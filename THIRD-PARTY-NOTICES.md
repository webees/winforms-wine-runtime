# Third-party notices

The published image aggregates software from several projects. The MIT licence
in `LICENSE` covers this repository's own files only.

| Component | Licence | Notes |
|---|---|---|
| [Wine](https://www.winehq.org/) 10 | LGPL-2.1-or-later | Distributed as Ubuntu package `wine64`. LGPL requires that recipients can relink; the package and its sources are available from Ubuntu and WineHQ. |
| [Ubuntu](https://ubuntu.com/) 26.04 base | Various free licences | See `/usr/share/doc/*/copyright` inside the image. |
| [.NET 8](https://dotnet.microsoft.com/) runtime in the self-test | MIT | Self-contained publish output. |
| [Microsoft Edge WebView2 runtime](https://learn.microsoft.com/microsoft-edge/webview2/) (Fixed Version) | Microsoft licence | Redistributed as the NuGet package `webview2.runtime.x64`. Distribution with an application is permitted under the Microsoft Edge WebView2 Runtime terms; the runtime may not be modified. |
| [SunnyUI](https://github.com/yhuse/SunnyUI) | MIT | Self-test only. |
| [Magick.NET](https://github.com/dlemstra/Magick.NET) / ImageMagick | Apache-2.0 / ImageMagick licence | Self-test only. |
| [KasmVNC](https://github.com/kasmtech/KasmVNC) 1.5.2 | GPL-2.0 | Installed from the upstream release package. See the GPL section below. |
| [FFmpeg](https://ffmpeg.org/) libraries (`KASMVNC_VIDEO=1`) | LGPL-2.1-or-later / GPL-2.0 for some builds | Ubuntu package, loaded through `dlopen()` for WebCodecs video encoding. |
| [WenQuanYi Micro Hei](http://wenq.org/) | Apache-2.0 / GPL-3.0 with font exception | Ubuntu package `fonts-wqy-microhei`. |

## KasmVNC and the GPL

KasmVNC is **GPL-2.0**. The published image is an aggregate: KasmVNC runs as its
own process and this repository's code is not linked against it, so the MIT
licence here is unaffected. Distribution of an image that *contains* KasmVNC
still carries GPL-2.0 obligations for that component:

- ship or offer the corresponding source for KasmVNC 1.5.2 (upstream tag
  `v1.5.2`), and
- keep its licence text available to recipients (it is installed under
  `/usr/share/doc/kasmvncserver/` in the image).

If you cannot accept those obligations, build the image with a KasmVNC-free
streaming layer of your own; removing the package is not enough, because the
entrypoint depends on `Xkasmvnc` for the desktop path.

## Trademarks

Windows, WinForms, .NET, Microsoft Edge and WebView2 are trademarks of Microsoft
Corporation. Wine is a trademark of the Wine project. This project is not
affiliated with or endorsed by Microsoft or the Wine project; the names are used
descriptively.

## Reporting a licensing problem

Open an issue titled `licensing: <component>` and include the file or layer you
believe is misattributed.
