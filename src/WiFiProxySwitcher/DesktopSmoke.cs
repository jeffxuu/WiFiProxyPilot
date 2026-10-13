using System.Diagnostics;
using System.Reflection;
using System.Text.Json;

namespace WiFiProxySwitcher;
internal static class DesktopSmoke
{
    internal static void CreateFixture(string root)
    {
        Directory.CreateDirectory(root); Directory.CreateDirectory(Path.Combine(root, "state")); Directory.CreateDirectory(Path.Combine(root, "logs"));
        string config = Path.Combine(root, "config.json");
        if (!File.Exists(config)) { using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("default-config.json")!; using var dest = File.Create(config); s.CopyTo(dest); }
        File.WriteAllText(Path.Combine(root, "state", "status.json"), JsonSerializer.Serialize(new { Time = DateTimeOffset.Now, SSID = "XiaoMi", Gateway = "10.0.0.1", InterfaceGuid = "11111111-1111-1111-1111-111111111111", Outcome = "Enable", Stable = true, Health = "TcpOpen", HealthCheckedAt = 1, ClockSeconds = 1, DiagnosticIntervalSeconds = 60, PollSeconds = 5, Reason = "非白名单 Wi-Fi 的当前 IPv4 网关" }));
        string log = Path.Combine(root, "logs", "watcher.jsonl");
        if (!File.Exists(log)) File.WriteAllText(log, JsonSerializer.Serialize(new { Time = DateTimeOffset.Now, Level = "INFO", Message = "网络与代理状态（隔离模拟）", Data = new { SSID = "XiaoMi", Target = "Enable", Reason = "非白名单 Wi-Fi 的当前 IPv4 网关" } }) + Environment.NewLine);
    }
    internal static void AttachBenchmark(TrayContext context)
    {
        // Start-Process hides the helper's startup window; explicitly show the tested UI for real paint timing.
        context.Window.BeginInvoke(() => { ShowWindow(context.Window.Handle, 5); context.Window.Update(); });
        var elapsed = Stopwatch.StartNew(); bool hidden = false;
        var timer = new System.Windows.Forms.Timer { Interval = 250 };
        timer.Tick += (_, _) =>
        {
            if (!hidden && elapsed.Elapsed.TotalSeconds > 8) { hidden = true; context.Window.Close(); StartupMetrics.Mark("ReadyReopen"); }
            if (elapsed.Elapsed.TotalSeconds > 35) { timer.Stop(); timer.Dispose(); context.ExitUi(); }
        };
        timer.Start();
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);
    internal static int Run(WiFiProxySwitcher.Core.Options options)
    {
        string path = Path.GetFullPath(options.Output ?? Path.Combine(Path.GetTempPath(), "WiFiProxySwitcher-smoke-" + Guid.NewGuid().ToString("N"), "smoke.json"));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!); AppController.TestRoot = Path.Combine(Path.GetDirectoryName(path)!, "smoke-fixture"); CreateFixture(AppController.TestRoot);
        var results = new List<object>(); int failed = 0;
        void Test(string name, Action body) { try { body(); results.Add(new { Name = name, Passed = true, Error = "" }); } catch (Exception e) { failed++; results.Add(new { Name = name, Passed = false, Error = e.Message }); } }
        void Check(bool condition) { if (!condition) throw new InvalidOperationException("Assertion failed"); }
        void Wait(Task task) { var t = Stopwatch.StartNew(); while (!task.IsCompleted && t.Elapsed.TotalSeconds < 15) { Application.DoEvents(); Thread.Sleep(10); } if (!task.IsCompleted) throw new TimeoutException(); task.GetAwaiter().GetResult(); }
        using var controller = new AppController();
        Test("EmbeddedPayload", () => Wait(controller.WarmCache()));
        using var context = new TrayContext(controller, false);
        Wait(context.Window.InitializeAsync()); Wait(context.Window.RefreshAsync()); Application.DoEvents();
        Test("Window render", () => { using var bitmap = new Bitmap(context.Window.Width, context.Window.Height); context.Window.DrawToBitmap(bitmap, new Rectangle(Point.Empty, context.Window.Size)); bitmap.Save(Path.ChangeExtension(path, ".png")); });
        Test("X hides and retains tray / simulated independent watcher", () => { string before = File.ReadAllText(Path.Combine(AppController.TestRoot, "state", "status.json")); context.Window.Close(); Check(!context.Window.Visible && !context.Window.IsDisposed && context.Tray.Visible); Check(before == File.ReadAllText(Path.Combine(AppController.TestRoot, "state", "status.json"))); });
        Test("Tray reopen", () => { context.Open(); Application.DoEvents(); Check(context.Window.Visible && context.Window.WindowState == FormWindowState.Normal); });
        Test("TaskbarCreated message recreates icon (Explorer not restarted)", () => { context.SimulateTaskbarCreated(); Check(context.Tray.Visible); });
        Test("Second instance signals primary", () => { using var primary = new SingleInstance(); Task.Run(() => { using var secondary = new SingleInstance(); Check(!secondary.Primary); }).GetAwaiter().GetResult(); Check(primary.Activation.WaitOne(1000)); });
        Test("System mutations disabled in smoke", () => { bool blocked = false; try { controller.Execute(new("install")).GetAwaiter().GetResult(); } catch (InvalidOperationException) { blocked = true; } Check(blocked); });
        Test("Readable logs and simulated status", () => { var s = StatusReader.Read(); Check(s.Logs.Contains("信息") && s.Healthy && s.Health.Contains("未验证代理服务")); });
        IEnumerable<Control> Descendants(Control parent) { foreach (Control child in parent.Controls) { yield return child; foreach (var grandchild in Descendants(child)) yield return grandchild; } }
        string Ancestors(Control control) { var parts=new List<string>(); for(Control? c=control;c!=null;c=c.Parent)parts.Add(c.GetType().Name+"="+c.Enabled);return string.Join("/",parts); } void Click(string text) { var button = Descendants(context.Window).OfType<Button>().First(b => b.Text == text); button.PerformClick(); Application.DoEvents(); var clock = Stopwatch.StartNew(); while (context.Window.IsBusy && clock.Elapsed.TotalSeconds < 10) { Application.DoEvents(); Thread.Sleep(10); } Check(!context.Window.IsBusy); }
        Test("UI add / deduplicate / save real isolated JSON", () => { context.Open(1); var input = Descendants(context.Window).OfType<TextBox>().First(t => t.PlaceholderText.Contains("完整")); foreach (string name in new[] { "XiaoMi", "xiaomi", "中文网络", " Office " }) { input.Text = name; Click("添加"); } Click("保存并应用"); var config = WiFiProxySwitcher.Core.ConfigurationStore.Read(AppController.TestRoot); Check(config.Whitelist.Contains("XiaoMi") && config.Whitelist.Contains("中文网络") && config.Whitelist.Contains(" Office ") && config.Whitelist.Count(n => n.Equals("xiaomi", StringComparison.OrdinalIgnoreCase)) == 1); });
        Test("UI protects built-ins / deletes custom / persists", () => { var list = Descendants(context.Window).OfType<ListBox>().Single(); list.SelectedIndex = 0; Click("删除所选"); Check(list.Items[0]!.ToString()!.Contains("MC-Office")); list.SelectedIndex = list.Items.Cast<object>().ToList().FindIndex(n => n.ToString()!.StartsWith("XiaoMi")); Click("删除所选"); if(list.Items.Cast<object>().Any(n=>n.ToString()!.StartsWith("XiaoMi"))) throw new InvalidOperationException("Delete did not update list; selected="+list.SelectedIndex+"; page visible="+list.Visible+"; enabled="+list.Enabled+"; ancestors="+Ancestors(list)); Click("保存并应用"); if(WiFiProxySwitcher.Core.ConfigurationStore.Read(AppController.TestRoot).Whitelist.Contains("XiaoMi")) throw new InvalidOperationException("XiaoMi remained; UI items=" + string.Join("|",list.Items.Cast<object>()) + "; busy=" + context.Window.IsBusy); });
        Test("UI cancel discards unsaved names", () => { var input = Descendants(context.Window).OfType<TextBox>().First(t => t.PlaceholderText.Contains("完整")); input.Text = "unsaved"; Click("添加"); Click("取消修改 / 重新载入"); var list = Descendants(context.Window).OfType<ListBox>().Single(); Check(!list.Items.Cast<object>().Any(n => n.ToString()!.StartsWith("unsaved"))); });
        Test("Large logs bounded", () => { string log = Path.Combine(AppController.TestRoot, "logs", "watcher.jsonl"); string line = File.ReadAllText(log); using (var f = File.AppendText(log)) for (int i = 0; i < 20000; i++) f.Write(line); var s = StatusReader.Read(); Check(s.Logs.Length < 100000); });
        foreach (float scale in new[] { 1F, 1.25F, 1.5F, 2F })
            Test($"Synthetic DPI {scale * 100}% pages", () =>
            {
                using var form = new MainForm(null); form.Scale(new SizeF(scale, scale)); form.Show(); Application.DoEvents();
                for (int page = 0; page < 4; page++) { form.SelectPage(page); Application.DoEvents(); using var bitmap = new Bitmap(form.Width, form.Height); form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size)); bitmap.Save(Path.Combine(Path.GetDirectoryName(path)!, $"ui-{scale * 100:0}-{page}.png")); }
                form.Close();
            });
        Test("UI exit leaves simulated watcher and proxy state", () => { var before = File.ReadAllText(Path.Combine(AppController.TestRoot, "state", "status.json")); context.ExitUi(); Check(!context.Tray.Visible && before == File.ReadAllText(Path.Combine(AppController.TestRoot, "state", "status.json"))); });
        File.WriteAllText(path, JsonSerializer.Serialize(new { Version = "3.1.0", Total = results.Count, Failed = failed, Results = results, Windows = true, Startup = failed == 0 ? "Passed" : "Failed", EmbeddedPayload = "Passed", WinFormsRender = "Passed", ProxyWritten = false, TaskWritten = false, Dpi = "Synthetic scaling, real per-monitor DPI remains manual", RealNetworkIntegration = "NOT RUN" }, new JsonSerializerOptions { WriteIndented = true }));
        return failed == 0 ? 0 : 1;
    }
}
