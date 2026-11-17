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
| [noVNC](https://github.com/novnc/noVNC) | MPL-2.0 | Ubuntu package. |
| [x11vnc](https://github.com/LibVNC/x11vnc) | GPL-2.0-or-later | Ubuntu package, invoked as a separate process. |
| [WenQuanYi Micro Hei](http://wenq.org/) | Apache-2.0 / GPL-3.0 with font exception | Ubuntu package `fonts-wqy-microhei`. |

## Trademarks

Windows, WinForms, .NET, Microsoft Edge and WebView2 are trademarks of Microsoft
Corporation. Wine is a trademark of the Wine project. This project is not
affiliated with or endorsed by Microsoft or the Wine project; the names are used
descriptively.

## Reporting a licensing problem

Open an issue titled `licensing: <component>` and include the file or layer you
believe is misattributed.
