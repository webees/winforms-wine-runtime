using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json;
using ImageMagick;
using ImageMagick.Drawing;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Sunny.UI;

namespace WinFormsWineRuntime.SelfTest;

internal sealed class MainForm : UIForm
{
    private readonly string _outDir;
    private readonly bool _selfTest;
    private readonly bool _strict;
    private WebView2? _web;
    private UIDataGridView? _grid;

    public int ExitCode { get; private set; }

    public MainForm(string[] args)
    {
        _selfTest = args.Contains("--selftest");
        _strict = args.Contains("--strict");
        _outDir = ReadArg(args, "--out")
                  ?? Environment.GetEnvironmentVariable("SELFTEST_OUT")
                  ?? @"C:\out";
        Directory.CreateDirectory(_outDir);

        BuildUi();
        Shown += async (_, _) =>
        {
            if (_selfTest) await RunSelfTestAsync();
        };
    }

    private static string? ReadArg(string[] args, string name)
    {
        var i = Array.IndexOf(args, name);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    private void BuildUi()
    {
        Text = "winforms-wine-runtime self-test";
        Size = new Size(1440, 900);
        StartPosition = FormStartPosition.CenterScreen;
        Style = UIStyle.Blue;

        var header = new UIPanel
        {
            Dock = DockStyle.Top,
            Height = 104,
            RectColor = Color.FromArgb(30, 41, 59)
        };
        header.Controls.Add(new UILabel
        {
            Text = "WinForms 容器运行时自检",
            Font = new Font("Microsoft YaHei", 16F, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = true,
            Location = new Point(24, 20)
        });
        header.Controls.Add(new UILabel
        {
            Text = "Wine 10 · .NET 8 · SunnyUI · WebView2 · Magick.NET",
            Font = new Font("Microsoft YaHei", 10F),
            ForeColor = Color.FromArgb(148, 163, 184),
            AutoSize = true,
            Location = new Point(26, 58)
        });
        var runButton = new UIButton
        {
            Text = "重新自检",
            Size = new Size(120, 36),
            Location = new Point(1280, 32),
            Anchor = AnchorStyles.Top | AnchorStyles.Right
        };
        runButton.Click += async (_, _) => await RunSelfTestAsync();
        header.Controls.Add(runButton);

        _grid = new UIDataGridView
        {
            Dock = DockStyle.Left,
            Width = 420,
            ReadOnly = true,
            AllowUserToAddRows = false,
            RowHeadersVisible = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill
        };
        _grid.Columns.Add("step", "步骤");
        _grid.Columns.Add("status", "结果");
        _grid.Columns.Add("detail", "用时/说明");

        _web = new WebView2 { Dock = DockStyle.Fill };

        Controls.Add(_web);
        Controls.Add(_grid);
        Controls.Add(header);
    }

    private void SetRow(string step, string status, string detail)
    {
        if (_grid is null) return;
        _grid.Rows.Add(step, status, detail);
        _grid.FirstDisplayedScrollingRowIndex = _grid.Rows.Count - 1;
    }

    private async Task RunSelfTestAsync()
    {
        _grid?.Rows.Clear();
        var report = new Dictionary<string, object?>
        {
            ["startedAt"] = DateTimeOffset.Now.ToString("O"),
            ["os"] = RuntimeInformation.OSDescription,
            ["runtime"] = RuntimeInformation.FrameworkDescription,
            ["arch"] = RuntimeInformation.ProcessArchitecture.ToString(),
            ["winePrefix"] = Environment.GetEnvironmentVariable("WINEPREFIX"),
            ["steps"] = new List<Dictionary<string, object?>>()
        };
        var steps = (List<Dictionary<string, object?>>)report["steps"]!;

        await RunStepAsync(steps, "sunnyui", TestSunnyUiAsync);
        await RunStepAsync(steps, "magick", TestMagickAsync);
        await RunStepAsync(steps, "webview2", TestWebView2Async);
        await RunStepAsync(steps, "webview2-shot", CaptureWebViewAsync);

        var failed = steps.Count(s => (bool)s["ok"]! == false);
        report["failed"] = failed;
        report["ok"] = failed == 0;
        report["finishedAt"] = DateTimeOffset.Now.ToString("O");

        var path = Path.Combine(_outDir, "report.json");
        await File.WriteAllTextAsync(
            path,
            JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));

        ExitCode = _strict && failed > 0 ? 1 : 0;
        Console.WriteLine($"[selftest] failed={failed} report={path}");
        if (_selfTest) Application.Exit();
    }

    private async Task RunStepAsync(
        List<Dictionary<string, object?>> steps,
        string name,
        Func<Task<Dictionary<string, object?>>> run)
    {
        var sw = Stopwatch.StartNew();
        Dictionary<string, object?> extra = new();
        string detail;
        bool ok;
        try
        {
            extra = await run();
            ok = true;
            detail = "ok";
        }
        catch (Exception ex)
        {
            ok = false;
            detail = ex.GetType().Name + ": " + ex.Message;
        }
        sw.Stop();

        steps.Add(new Dictionary<string, object?>
        {
            ["name"] = name,
            ["ok"] = ok,
            ["ms"] = sw.ElapsedMilliseconds,
            ["detail"] = detail,
            ["extra"] = extra
        });
        SetRow(name, ok ? "PASS" : "FAIL", $"{sw.ElapsedMilliseconds} ms · {detail}");
    }

    private Task<Dictionary<string, object?>> TestSunnyUiAsync()
    {
        if (_grid is null) throw new InvalidOperationException("grid not created");
        var file = Path.Combine(_outDir, "sunnyui.png");
        using var bmp = new Bitmap(480, 240);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.White);
            using var font = new Font("Microsoft YaHei", 20F);
            g.DrawString("中文渲染 SunnyUI", font, Brushes.DarkSlateBlue, 12, 12);
            g.DrawString("ABC 123 !@#", font, Brushes.Black, 12, 60);
        }
        bmp.Save(file, ImageFormat.Png);

        var rows = _grid.Rows.Count;
        return Task.FromResult(new Dictionary<string, object?>
        {
            ["rows"] = rows,
            ["file"] = file,
            ["bytes"] = new FileInfo(file).Length
        });
    }

    private Task<Dictionary<string, object?>> TestMagickAsync()
    {
        var file = Path.Combine(_outDir, "magick.png");
        using var image = new MagickImage(MagickColors.White, 640, 360);
        new Drawables()
            .FillColor(new MagickColor("#2563eb"))
            .Rectangle(40, 40, 600, 320)
            .FillColor(MagickColors.White)
            .Font("DejaVu-Sans")
            .FontPointSize(36)
            .Text(72, 200, "Magick.NET in Wine")
            .Draw(image);
        image.Write(file);
        return Task.FromResult(new Dictionary<string, object?>
        {
            ["version"] = MagickNET.Version,
            ["file"] = file,
            ["bytes"] = new FileInfo(file).Length
        });
    }

    private async Task<Dictionary<string, object?>> TestWebView2Async()
    {
        if (_web is null) throw new InvalidOperationException("webview not created");
        var userData = Path.Combine(_outDir, "wv2-profile");
        Directory.CreateDirectory(userData);

        // Under Wine the loader does not discover a Fixed Version runtime on its
        // own, so every application must pass the folder explicitly. Empty means
        // "let the loader try", which is what fails.
        var browserFolder = Environment.GetEnvironmentVariable("WEBVIEW2_BROWSER_EXECUTABLE_FOLDER");
        if (string.IsNullOrWhiteSpace(browserFolder)) browserFolder = null;
        var env = await CoreWebView2Environment.CreateAsync(
            browserFolder, userData, new CoreWebView2EnvironmentOptions());
        await _web.EnsureCoreWebView2Async(env);

        var tcs = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            var text = e.TryGetWebMessageAsString();
            if (text.StartsWith("ready|", StringComparison.Ordinal)) tcs.TrySetResult(text);
        }
        _web.CoreWebView2.WebMessageReceived += OnMessage;
        try
        {
            _web.CoreWebView2.NavigateToString(Html);
            var done = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(60)));
            if (done != tcs.Task) throw new TimeoutException("WebView2 did not post 'ready' within 60 s");

            var title = await _web.CoreWebView2.ExecuteScriptAsync("document.title");
            var message = await tcs.Task;
            return new Dictionary<string, object?>
            {
                ["runtime"] = env.BrowserVersionString,
                ["title"] = title.Trim('"'),
                ["message"] = message
            };
        }
        finally
        {
            _web.CoreWebView2.WebMessageReceived -= OnMessage;
        }
    }

    private async Task<Dictionary<string, object?>> CaptureWebViewAsync()
    {
        if (_web?.CoreWebView2 is null) throw new InvalidOperationException("webview not ready");
        var file = Path.Combine(_outDir, "webview2.png");
        using var stream = new MemoryStream();
        var capture = _web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
        if (await Task.WhenAny(capture, Task.Delay(TimeSpan.FromSeconds(30))) != capture)
            throw new TimeoutException("CapturePreviewAsync timed out");
        await capture;
        await File.WriteAllBytesAsync(file, stream.ToArray());
        return new Dictionary<string, object?>
        {
            ["file"] = file,
            ["bytes"] = new FileInfo(file).Length
        };
    }

    private const string Html = """
        <!doctype html><html><head><meta charset="utf-8"><title>wv2-ok-42</title>
        <style>
        /* Chromium under Wine sees .ttf fonts but not .ttc collections. */
        html,body{margin:0;height:100%;font-family:'Droid Sans Fallback','DejaVu Sans',sans-serif}
        body{display:flex;align-items:center;justify-content:center;background:#0f172a;color:#e2e8f0}
        canvas{max-width:90vw;border-radius:12px}</style></head>
        <body><div style="position:absolute;top:24px;left:24px;font-size:22px">
        HTML 中文测试 ABC 123</div><canvas id="c" width="800" height="420"></canvas>
        <script>
          const g = document.getElementById('c').getContext('2d');
          const grad = g.createLinearGradient(0, 0, 800, 420);
          grad.addColorStop(0, '#2563eb'); grad.addColorStop(1, '#9333ea');
          g.fillStyle = grad; g.fillRect(0, 0, 800, 420);
          g.fillStyle = '#fff'; g.font = 'bold 40px "Droid Sans Fallback","DejaVu Sans"';
          g.fillText('WebView2 OK', 60, 220);
          g.font = '24px "Droid Sans Fallback","DejaVu Sans"';
          g.fillText('Chromium in Wine · canvas 2d + JS interop', 60, 280);
          chrome.webview.postMessage('ready|' + navigator.userAgent);
        </script></body></html>
        """;
}
