using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;

// All product code is exercised with an owned fixture. No real proxy, task, WLAN or Explorer mutation.
internal static class DesktopVerification
{
    internal static void CreateFixture(string root)
    {
        SafeFiles.PlainPath(root);
        if (File.Exists(Path.Combine(root, "state", "installation.json")))
            throw new IOException("隔离验证不能使用真实安装目录。");
        Directory.CreateDirectory(root); Directory.CreateDirectory(Path.Combine(root, "state")); Directory.CreateDirectory(Path.Combine(root, "logs"));
        string path = Path.Combine(root, "config.json");
        if (!File.Exists(path))
        {
            var config = ConfigurationStore.CreateDefault();
            config["SetupComplete"] = true; config["ManagementIntent"] = "Monitoring";
            config["Whitelist"] = new JsonArray("Office", "Guest");
            File.WriteAllText(path, config.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        WriteHeartbeat(root);
        string log = Path.Combine(root, "logs", "watcher.jsonl");
        if (!File.Exists(log))
            File.WriteAllText(log, JsonSerializer.Serialize(new { Time = DateTimeOffset.Now, Level = "INFO", Message = "当前界面使用隔离演示数据；未更改系统代理或任务", Data = new { SSID = "Mobile Hotspot", Gateway = "192.0.2.1", Target = "Enable", Reason = "当前 Wi-Fi 网关规则" } }) + Environment.NewLine);
    }
    private static void WriteHeartbeat(string root, DateTimeOffset? time = null)
    {
        string revision = ConfigurationStore.Read(root).Revision;
        File.WriteAllText(Path.Combine(root, "state", "status.json"), JsonSerializer.Serialize(new
        {
            Time = time ?? DateTimeOffset.Now, EngineVersion = "3.2.0-beta.1", SchemaVersion = 2,
            ManagementIntent = "Monitoring", SetupComplete = true, SSID = "Mobile Hotspot", NetworkKind = "Connected",
            Gateway = "192.0.2.1", InterfaceGuid = "11111111-1111-1111-1111-111111111111", Outcome = "Enable", RuleAction = "Enable",
            Stable = true, ActualEnabled = true, ActualServer = "192.0.2.1:7890", ConfigRevision = revision, AppliedRevision = revision,
            Health = "TcpOpen", HealthCheckedAt = 50.0, ClockSeconds = 51.0, Diagnostics = "Tcp", DiagnosticIntervalSeconds = 60,
            PollSeconds = 5, Reason = "当前 Wi-Fi 未命中免代理规则，使用其 IPv4 网关", RuleReason = "当前 Wi-Fi 未命中免代理规则，使用其 IPv4 网关", CheckRequestId = ""
        }));
    }

    internal static void AttachBenchmark(PilotTrayHost host)
    {
        // The helper is started hidden, then explicitly shown to measure actual WPF rendering.
        host.Window.Show();
        host.Window.Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            ShowWindow(new WindowInteropHelper(host.Window).Handle, 5);
            host.Window.UpdateLayout();
        }));
        var elapsed = Stopwatch.StartNew(); bool hidden = false;
        var timer = new DispatcherTimer(DispatcherPriority.Background, host.Window.Dispatcher) { Interval = TimeSpan.FromMilliseconds(250) };
        EventHandler? tick = null;
        tick = (_, _) =>
        {
            if (!hidden && elapsed.Elapsed.TotalSeconds >= 8)
            {
                hidden = true; host.Window.Close(); StartupMetrics.Mark("ReadyReopen");
            }
            if (elapsed.Elapsed.TotalSeconds >= 35)
            {
                timer.Stop(); timer.Tick -= tick; host.ExitUi();
            }
        };
        timer.Tick += tick; timer.Start();
    }
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr window, int command);

    // Targeted review of the refined homepage only, not a repeat of the full desktop suite.
    internal static int RunHomeReview(Options options)
    {
        string output = Path.GetFullPath(options.Output ?? throw new ArgumentException("首页评审需要 /output"));
        string directory = Path.GetDirectoryName(output)!; Directory.CreateDirectory(directory);
        AppController.TestRoot = Path.Combine(directory, "home-fixture-" + Guid.NewGuid().ToString("N")); CreateFixture(AppController.TestRoot);
        var app = new System.Windows.Application { ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown };
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(app.Dispatcher));
        using var controller = new AppController(); using var host = new PilotTrayHost(controller, false);
        var results = new List<object>(); int failed = 0;
        async Task Check(string name, Func<Task> test)
        {
            try { await test(); results.Add(new { Name = name, Passed = true, Error = "" }); }
            catch (Exception e) { failed++; results.Add(new { Name = name, Passed = false, Error = e.ToString() }); }
        }
        void Assert(bool condition) { if (!condition) throw new InvalidOperationException("Assertion failed"); }
        app.Dispatcher.BeginInvoke(new Action(async () =>
        {
            try
            {
                await host.Window.ViewModel.InitializeAsync(); host.Window.ApplyTheme("Light");
                ShowWindow(new WindowInteropHelper(host.Window).Handle, 5);
                await Check("Homepage observes automatic intent, proxy and TCP separately", () =>
                {
                    var vm = host.Window.ViewModel;
                    Assert(vm.AutomaticEnabled && vm.DashboardNetworkTitle == "Mobile Hotspot" && vm.Status?.ProxyEnabled == true && vm.Status.Diagnostic?.State == ProxyDiagnosticState.TcpReachable);
                    Assert(vm.DashboardDiagnosticStatus == Localization.Text("DiagnosticTcp") && vm.DashboardDiagnosticStatus != Localization.Text("DiagnosticHttp")); return Task.CompletedTask;
                });
                await Check("Window maximize, restore and keyboard focus use native WPF semantics", async () =>
                {
                    System.Windows.SystemCommands.MaximizeWindow(host.Window); await host.Window.Dispatcher.InvokeAsync(() => {}, DispatcherPriority.Render);
                    Assert(host.Window.WindowState == System.Windows.WindowState.Maximized);
                    System.Windows.SystemCommands.RestoreWindow(host.Window); await host.Window.Dispatcher.InvokeAsync(() => {}, DispatcherPriority.Render);
                    Assert(host.Window.WindowState == System.Windows.WindowState.Normal);
                    Assert(host.Window.MoveFocus(new System.Windows.Input.TraversalRequest(System.Windows.Input.FocusNavigationDirection.First)));
                });
                await Check("Actual light homepage capture with new resource templates", async () =>
                {
                    System.Windows.Input.Keyboard.ClearFocus();
                    await host.Window.Dispatcher.InvokeAsync(() => host.Window.UpdateLayout(), DispatcherPriority.Render); await Task.Delay(120);
                    Assert(host.Window.Background is System.Windows.Media.SolidColorBrush brush && brush.Color == System.Windows.Media.Color.FromRgb(245,245,247));
                    var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(host.Window);
                    var bitmap = new RenderTargetBitmap((int)Math.Ceiling(host.Window.ActualWidth*dpi.DpiScaleX),(int)Math.Ceiling(host.Window.ActualHeight*dpi.DpiScaleY),96*dpi.DpiScaleX,96*dpi.DpiScaleY,System.Windows.Media.PixelFormats.Pbgra32);
                    bitmap.Render(host.Window); var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
                    using var file = File.Create(Path.Combine(directory,"overview-refined-light.png")); png.Save(file);
                });
                await Check("Automatic switch cannot manufacture success in an isolated preview", async () =>
                {
                    await host.Window.ViewModel.Perform("automatic");
                    Assert(host.Window.ViewModel.AutomaticEnabled && host.Window.ViewModel.Status?.Intent == ManagementIntent.Monitoring && !host.Window.ViewModel.AutomaticControlEnabled && host.Window.ViewModel.IsDemo && host.Window.ViewModel.Message == Localization.Format("OperationFailed", Localization.Error(new UiOperationException("DemoDisabled"))));
                });
                await Check("Actual tray menu capture uses the isolated application", async () =>
                {
                    var menu = host.Tray.ContextMenuStrip ?? throw new InvalidOperationException("Tray menu missing");
                    menu.Show(new System.Drawing.Point(20, 20));
                    await Task.Delay(120);
                    using var bitmap = new System.Drawing.Bitmap(menu.Width, menu.Height);
                    menu.DrawToBitmap(bitmap, new System.Drawing.Rectangle(0, 0, menu.Width, menu.Height));
                    bitmap.Save(Path.Combine(directory, "tray-preview.png"), System.Drawing.Imaging.ImageFormat.Png);
                    menu.Close();
                });
            }
            catch (Exception e) { failed++; results.Add(new { Name="Home review initialization", Passed=false, Error=e.ToString() }); }
            finally
            {
                File.WriteAllText(output, JsonSerializer.Serialize(new { Total=results.Count, Failed=failed, Results=results, ProxyWritten=false, TaskWritten=false, Network="Synthetic fixture; not real-network acceptance", UI="Actual WPF at current desktop DPI", ManualWindowDragSnapAndDpi="NOT RUN" }, new JsonSerializerOptions { WriteIndented=true }));
                host.ExitUi();
            }
        }));
        app.Run(); return failed == 0 ? 0 : 1;
    }

    internal static int Run(Options options)
    {
        string output = Path.GetFullPath(options.Output ?? Path.Combine(Path.GetTempPath(), "WiFiPilot-smoke-" + Guid.NewGuid().ToString("N"), "smoke.json"));
        SafeFiles.PlainPath(output); string directory = Path.GetDirectoryName(output)!; Directory.CreateDirectory(directory);
        string fixture = Path.Combine(directory, "wpf-smoke-fixture-" + Guid.NewGuid().ToString("N"));
        AppController.TestRoot = fixture; CreateFixture(fixture);
        var results = new List<object>(); var captures = new List<object>(); int failed = 0; double refreshMilliseconds = 0;
        void Check(bool value) { if (!value) throw new InvalidOperationException("Assertion failed"); }
        async Task Test(string name, Func<Task> body)
        {
            var clock = Stopwatch.StartNew();
            try { await body(); results.Add(new { Name = name, Passed = true, Error = "", DurationMilliseconds = clock.Elapsed.TotalMilliseconds }); }
            catch (Exception e) { failed++; results.Add(new { Name = name, Passed = false, Error = e.Message, DurationMilliseconds = clock.Elapsed.TotalMilliseconds }); }
        }
        var application = System.Windows.Application.Current ?? new System.Windows.Application { ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown };
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(application.Dispatcher));
        using var controller = new AppController();
        using var host = new PilotTrayHost(controller, false);
        var vm = host.Window.ViewModel;
        async Task WaitForStatus(Func<bool> ready)
        {
            var clock = Stopwatch.StartNew();
            while (!ready() && clock.Elapsed.TotalSeconds < 10)
            {
                await vm.RefreshAsync();
                if (!ready()) await Task.Delay(25);
            }
            Check(ready());
        }
        async Task Render(string page, string name)
        {
            host.Open(page);
            await host.Window.Dispatcher.InvokeAsync(() => host.Window.UpdateLayout(), DispatcherPriority.Render);
            await Task.Delay(100); // One frame and font rendering settle; no synthetic DPI loops.
            host.Window.UpdateLayout();
            var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(host.Window);
            int width = Math.Max(1, (int)Math.Ceiling(host.Window.ActualWidth * dpi.DpiScaleX));
            int height = Math.Max(1, (int)Math.Ceiling(host.Window.ActualHeight * dpi.DpiScaleY));
            var bitmap = new RenderTargetBitmap(width, height, 96 * dpi.DpiScaleX, 96 * dpi.DpiScaleY, System.Windows.Media.PixelFormats.Pbgra32);
            bitmap.Render(host.Window);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            string path = Path.Combine(directory, name); SafeFiles.PlainPath(path);
            using (var stream = File.Create(path)) encoder.Save(stream);
            captures.Add(new { Path = path, Width = width, Height = height, DpiScale = dpi.DpiScaleX, Source = "Actual WPF RenderTargetBitmap; isolated fixture data" });
        }
        application.Dispatcher.BeginInvoke(new Action(async () =>
        {
            try
            {
                await vm.InitializeAsync();
                await Test("Embedded payload uses verified cache", async () => await controller.WarmCache());
                await Test("Real WPF dashboard renders with independent TCP diagnostic", async () =>
                {
                    vm.Settings.Theme = "Light"; await vm.Perform("save-settings"); host.Window.ApplyTheme("Light"); WriteHeartbeat(fixture); await vm.RefreshAsync();
                    Check(vm.Status?.Network?.State == NetworkConnectionState.Connected && vm.Status.Diagnostic?.State == ProxyDiagnosticState.TcpReachable);
                    await Render("Dashboard", "wpf-dashboard-light.png");
                });
                await Test("Settings groups render in the same WPF application", async () =>
                {
                    await Render("Settings", "wpf-settings-light.png"); Check(vm.Page == "Settings");
                });
                await Test("X hides UI and preserves independent watcher fixture and tray", () =>
                {
                    string before = File.ReadAllText(Path.Combine(fixture, "state", "status.json")); host.Window.Close();
                    Check(!host.Window.IsVisible && host.Tray.Visible && before == File.ReadAllText(Path.Combine(fixture, "state", "status.json")));
                    return Task.CompletedTask;
                });
                await Test("Tray reopens the same WPF window", async () =>
                {
                    host.Open(); await host.Window.Dispatcher.InvokeAsync(() => host.Window.UpdateLayout(), DispatcherPriority.Render);
                    Check(host.Window.IsVisible && host.Window.WindowState == System.Windows.WindowState.Normal);
                });
                await Test("TaskbarCreated icon recovery message is simulated", () => { host.SimulateTaskbarCreated(); Check(host.Tray.Visible); return Task.CompletedTask; });
                await Test("Second instance signals primary in the same isolated namespace", async () =>
                {
                    using var primary = new SingleInstance(); Check(primary.Primary);
                    await Task.Run(() => { using var secondary = new SingleInstance(); Check(!secondary.Primary); });
                    Check(primary.Activation.WaitOne(1000));
                });
                await Test("Real system mutations are forbidden in isolated mode", async () =>
                {
                    bool blocked = false; try { await controller.Execute(new("install")); } catch (InvalidOperationException) { blocked = true; } Check(blocked);
                });
                await Test("Wi-Fi editor adds, deduplicates, edits and saves real isolated JSON", async () =>
                {
                    await vm.Perform("rules"); vm.Rules.Input = "Lab Hotspot"; await vm.Perform("add");
                    Check(vm.Rules.Dirty && vm.Rules.Names.Contains("Lab Hotspot"));
                    vm.Rules.Input = "lab hotspot"; await vm.Perform("add"); Check(vm.Rules.Names.Count(n => n.Equals("Lab Hotspot", StringComparison.OrdinalIgnoreCase)) == 1);
                    vm.Rules.Selected = "Lab Hotspot"; vm.Rules.Input = "Home Hotspot"; await vm.Perform("edit");
                    await vm.Perform("save-rules"); var saved = ConfigurationStore.Read(fixture);
                    Check(saved.Whitelist.Contains("Home Hotspot") && !saved.Whitelist.Contains("Lab Hotspot") && !vm.Rules.Dirty);
                    Check(vm.Message == Localization.Text("SavedPending") && vm.Message != Localization.Text("RulesApplied"));
                    await Render("Rules", "wpf-rules-light.png");
                });
                await Test("Cancel discards only unsaved changes", async () =>
                {
                    vm.Rules.Input = "Unsaved Network"; await vm.Perform("add"); await vm.Perform("cancel");
                    Check(!vm.Rules.Names.Contains("Unsaved Network") && !vm.Rules.Dirty && vm.Rules.Names.Contains("Home Hotspot"));
                });
                await Test("Every rule can be deleted and an empty list persists", async () =>
                {
                    foreach (string name in vm.Rules.Names.ToArray()) { vm.Rules.Selected = name; await vm.Perform("delete"); }
                    await vm.Perform("save-rules"); Check(ConfigurationStore.Read(fixture).Whitelist.Length == 0 && vm.Rules.Names.Count == 0);
                });
                await Test("Stale heartbeat cannot appear as a current connection", async () =>
                {
                    WriteHeartbeat(fixture, DateTimeOffset.Now.AddMinutes(-5)); await vm.RefreshAsync();
                    await WaitForStatus(() => vm.Status?.Fresh == false);
                    Check(vm.Status?.State == ApplicationState.Degraded && !vm.Status.Fresh && !vm.Status.Connected && vm.NetworkLabel == Localization.Text("Unreadable"));
                    WriteHeartbeat(fixture); await WaitForStatus(() => vm.Status?.Fresh == true);
                });
                await Test("Logs are loaded on demand and status refresh is measured", async () =>
                {
                    host.Open("Logs"); await WaitForStatus(() => vm.Logs.Contains("隔离演示数据"));
                    host.Open("Dashboard"); var clock = Stopwatch.StartNew(); var sample = await Task.Run(() => StatusReader.Read()); refreshMilliseconds = clock.Elapsed.TotalMilliseconds; Check(sample.Fresh);
                });
                await Test("Dark WPF dashboard renders", async () =>
                {
                    vm.Settings.Theme = "Dark"; await vm.Perform("save-settings"); host.Window.ApplyTheme("Dark"); WriteHeartbeat(fixture); await vm.RefreshAsync();
                    Check(host.Window.Background is System.Windows.Media.SolidColorBrush background && background.Color == System.Windows.Media.Color.FromRgb(37, 38, 41));
                    await Render("Dashboard", "wpf-dashboard-dark.png");
                });
                await Test("Exit UI preserves watcher fixture and proxy observation", () =>
                {
                    string before = File.ReadAllText(Path.Combine(fixture, "state", "status.json"));
                    host.ExitUi();
                    Check(!host.Tray.Visible && before == File.ReadAllText(Path.Combine(fixture, "state", "status.json"))); return Task.CompletedTask;
                });
            }
            catch (Exception e) { failed++; results.Add(new { Name = "WPF verification initialization", Passed = false, Error = e.ToString() }); }
            finally
            {
                File.WriteAllText(output, JsonSerializer.Serialize(new
                {
                    Version = "3.2.0-beta.1", Total = results.Count, Passed = results.Count - failed, Failed = failed, Results = results, Captures = captures,
                    StatusRefreshMilliseconds = refreshMilliseconds, Windows = true, UI = "Actual WPF application and render tree", ProxyWritten = false, TaskWritten = false,
                    Network = "Isolated synthetic SSID and documentation IPv4 address", Explorer = "TaskbarCreated message only; Explorer was not restarted", RealNetworkIntegration = "NOT RUN", Fixture = fixture
                }, new JsonSerializerOptions { WriteIndented = true }));
                host.ExitUi();
            }
        }));
        application.Run();
        AppController.TestRoot = null;
        return failed == 0 ? 0 : 1;
    }
}
