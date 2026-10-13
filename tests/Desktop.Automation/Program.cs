using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Windows.Automation;

// External UIA client: invokes actual WPF/native controls, never ViewModel methods.
internal static class Program
{
    private static readonly List<object> Results = new();
    private static readonly List<object> InputEvents = new();
    private static int failures;
    private static AutomationElement window = null!;
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [STAThread]
    private static int Main(string[] args)
    {
        // UIA clickable points are physical pixels. Keep the client out of DPI
        // virtualization so a click lands on the control at 125/150/200% scaling.
        _ = SetProcessDpiAwarenessContext(new IntPtr(-4));
        _ = SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (args.Length < 2) throw new ArgumentException("EXE path and evidence directory required; optional --installed, --setup-only or --backend-failure.");
        string exe = Path.GetFullPath(args[0]), evidence = Path.GetFullPath(args[1]); Directory.CreateDirectory(evidence);
        bool setupOnly = args.Contains("--setup-only"), backendFailure = args.Contains("--backend-failure");
        bool installed = args.Contains("--installed") || backendFailure, real = installed || setupOnly;
        if (real && !(Environment.GetEnvironmentVariable("GITHUB_ACTIONS") == "true" && Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT") == "github-hosted"))
            throw new InvalidOperationException("Real installed tests are restricted to a disposable GitHub-hosted Windows runner.");
        var info = new ProcessStartInfo(exe) { UseShellExecute = false };
        if (!real) { info.ArgumentList.Add("/preview"); info.ArgumentList.Add("/output"); info.ArgumentList.Add(Path.Combine(evidence, "preview.json")); }
        using var process = Process.Start(info) ?? throw new IOException("Application did not start.");
        IntPtr hwnd = IntPtr.Zero;
        try
        {
            Wait(() => { process.Refresh(); hwnd = process.MainWindowHandle; return hwnd != IntPtr.Zero; }, 30000);
            window = AutomationElement.FromHandle(hwnd);
            CaptureText(evidence, "startup-controls");
            Test("Actual WPF window opens", () => Assert(window.Current.Name == "WiFi Proxy Pilot"));
            Wait(() => Find("NavRules", false) != null, 15000);
            if (setupOnly)
            {
                Test("Unconfigured application automatic click opens the real setup wizard", () =>
                {
                    Click("AutomaticToggle"); Wait(() => Find("ConfirmEnable", false) != null);
                    Assert(Find("ConfirmEnable")!.Current.IsEnabled);
                    CaptureText(evidence, "actual-setup-wizard");
                    using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\WiFiProxySwitcher");
                    Assert(key?.GetValue("InstallDir") == null);
                });
                return failures == 0 ? 0 : 1;
            }
            if (backendFailure)
            {
                Test("Backend failure does not report automatic resume success", () =>
                {
                    Assert(Configuration(true, evidence).GetProperty("ManagementIntent").GetString() == "Paused");
                    string tracePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WiFiProxySwitcher-Control", "commands.jsonl");
                    int previousLines = File.Exists(tracePath) ? File.ReadAllLines(tracePath).Length : 0;
                    Click("AutomaticToggle");
                    Wait(() => File.Exists(tracePath) && File.ReadAllLines(tracePath).Skip(previousLines).Any(line => { using var json = JsonDocument.Parse(line); return json.RootElement.GetProperty("Stage").GetString() == "WpfCommand.Failed"; }), 30000);
                    Wait(() => Find("AutomaticToggle")!.Current.IsEnabled);
                    Assert(Configuration(true, evidence).GetProperty("ManagementIntent").GetString() == "Paused");
                    Assert(((TogglePattern)Find("AutomaticToggle")!.GetCurrentPattern(TogglePattern.Pattern)).Current.ToggleState == ToggleState.Off);
                    string message = Find("StatusMessage")!.Current.Name;
                    Assert(message.StartsWith("Operation failed", StringComparison.Ordinal) || message.StartsWith("操作失败", StringComparison.Ordinal));
                    File.Copy(tracePath, Path.Combine(evidence, "actual-backend-failure-trace.jsonl"), true);
                    CaptureText(evidence, "actual-backend-failure");
                });
                return failures == 0 ? 0 : 1;
            }
            Test("Native right caption maximize and restore", () =>
            {
                Invoke(NativeCaption("Maximize", "MaximizeRestore")); Wait(() => Window().Current.WindowVisualState == WindowVisualState.Maximized);
                // Re-query after state changes: native caption controls can be recreated.
                Invoke(NativeCaption("Maximize", "MaximizeRestore", "Restore")); Wait(() => Window().Current.WindowVisualState == WindowVisualState.Normal);
            });
            Test("Native caption minimizes the actual window", () =>
            {
                Invoke(NativeCaption("Minimize")); Wait(() => !IsWindowVisible(hwnd) || Window().Current.WindowVisualState == WindowVisualState.Minimized);
                ShowWindow(hwnd, 9); Wait(() => Window().Current.WindowVisualState == WindowVisualState.Normal);
            });
            Test("Demo banner and automatic toggle disable are explicit", () =>
            {
                if (installed) { Results.Add(new { Name = "Demo-only assertion", Passed = true, Scope = "Covered in separate preview run" }); return; }
                var automatic = Find("AutomaticToggle")!; Assert(!automatic.Current.IsEnabled);
                Assert(Find("DemoBanner")!.Current.Name.Length > 10);
            });
            Test("Wi-Fi rules add through real WPF controls", () =>
            {
                Select("NavRules"); Value("SsidInput", "UIA Test Network"); Click("AddRule"); Wait(() => FindByName("UIA Test Network") != null);
            });
            Test("Rule editing and save persist the real JSON", () =>
            {
                var row = FindByName("UIA Test Network")!;
                var container = RuleRow(row);
                var edit = container.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.AutomationIdProperty, "EditRule"));
                Invoke(edit!); Value("SsidInput", "UIA Edited Network"); Click("UpdateRule"); Click("SaveRules");
                Wait(() => Configuration(installed, evidence).GetProperty("Whitelist").EnumerateArray().Any(x => x.GetString() == "UIA Edited Network"));
            });
            Test("Cancel discards an unsaved rule", () =>
            {
                Value("SsidInput", "UIA Unsaved Network"); Click("AddRule"); Click("CancelRules"); Wait(() => FindByName("UIA Unsaved Network") == null);
            });
            Test("Rule delete and save persist removal", () =>
            {
                var row = FindByName("UIA Edited Network")!; var container = RuleRow(row);
                var delete = container.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.AutomationIdProperty, "DeleteRule"));
                Invoke(delete!); Click("SaveRules");
                Wait(() => !Configuration(installed, evidence).GetProperty("Whitelist").EnumerateArray().Any(x => x.GetString() == "UIA Edited Network"));
            });
            Test("Settings save uses WPF textbox and command", () =>
            {
                Select("NavSettings"); Value("PortInput", "7891"); Click("SaveSettings"); Wait(() => Configuration(installed, evidence).GetProperty("Port").GetInt32() == 7891);
            });
            Test("English language switches all retained pages", () =>
            {
                SelectCombo("LanguageChoice", "English"); Click("SaveSettings"); Select("NavOverview"); Wait(() => FindByName("Overview") != null);
                CaptureText(evidence, "en-US-overview"); Select("NavRules"); CaptureText(evidence, "en-US-rules"); Select("NavSettings"); CaptureText(evidence, "en-US-settings"); Select("NavLogs"); CaptureText(evidence, "en-US-logs");
            });
            Test("Chinese language switches all retained pages", () =>
            {
                Select("NavSettings"); SelectCombo("LanguageChoice", "简体中文"); Click("SaveSettings"); Select("NavOverview"); Wait(() => FindByName("概览") != null);
                CaptureText(evidence, "zh-CN-overview"); Select("NavRules"); CaptureText(evidence, "zh-CN-rules"); Select("NavSettings"); CaptureText(evidence, "zh-CN-settings"); Select("NavLogs"); CaptureText(evidence, "zh-CN-logs");
            });
            Test("Theme switch through actual toolbar button", () => { Click("ThemeToggle"); Assert(!process.HasExited); });
            if (installed)
            {
                Test("Automatic pause click persists Paused and watcher acknowledgement", () =>
                {
                    Select("NavOverview"); Toggle("AutomaticToggle"); Wait(() => Configuration(true, evidence).GetProperty("ManagementIntent").GetString() == "Paused", 30000);
                    Wait(() => Heartbeat().GetProperty("ManagementIntent").GetString() == "Paused", 30000);
                    Wait(() => Find("AutomaticToggle")!.Current.IsEnabled, 30000);
                });
                Test("Automatic resume click confirms real watcher Monitoring", () =>
                {
                    Toggle("AutomaticToggle"); Wait(() => Heartbeat().GetProperty("ManagementIntent").GetString() == "Monitoring", 30000);
                    Assert(Heartbeat().GetProperty("Outcome").GetString() != "Stopped"); Wait(() => Find("AutomaticToggle")!.Current.IsEnabled, 30000);
                });
                Test("Check now click is acknowledged by real watcher", () =>
                {
                    string before = Heartbeat().GetProperty("RequestedCheckRequestId").GetString() ?? ""; Click("CheckNow");
                    Wait(() => Heartbeat().GetProperty("RequestedCheckRequestId").GetString() is string next && next.Length > 0 && next != before, 30000);
                });
            }
            Test("Native X hides to tray and preserves independent watcher", () =>
            {
                Invoke(NativeCaption("Close")); Wait(() => !IsWindowVisible(hwnd)); Assert(!process.HasExited);
                if (installed) Assert(Heartbeat().GetProperty("Outcome").GetString() != "Stopped");
            });
            Test("Second launch reopens the existing tray instance", () =>
            {
                using var second = Process.Start(info)!; Assert(second.WaitForExit(10000)); Assert(second.ExitCode == 0); Wait(() => IsWindowVisible(hwnd));
            });
        }
        catch (Exception error) { failures++; Results.Add(new { Name = "Desktop automation setup", Passed = false, Error = error.ToString() }); }
        finally
        {
            // Test-owned process only. Does not stop the independent installed watcher.
            if (!process.HasExited)
            {
                if (real)
                {
                    using var shutdown = Process.Start(new ProcessStartInfo(exe, "/shutdown-ui /quiet") { UseShellExecute = false });
                    shutdown?.WaitForExit(10000);
                    if (!process.WaitForExit(10000)) { process.Kill(); process.WaitForExit(); }
                }
                else { process.Kill(); process.WaitForExit(); }
            }
            File.WriteAllText(Path.Combine(evidence, "uia-results.json"), JsonSerializer.Serialize(new { Total = Results.Count, Failed = failures, Results, Boundary = real ? "Real WPF/PowerShell/Watcher in disposable GitHub-hosted Windows" : "Actual WPF controls, isolated fixture; no Windows proxy/task mutation" }, new JsonSerializerOptions { WriteIndented = true }));
            File.WriteAllText(Path.Combine(evidence, "uia-input.json"), JsonSerializer.Serialize(InputEvents, new JsonSerializerOptions { WriteIndented = true }));
        }
        return failures == 0 ? 0 : 1;
    }
    private static void Test(string name, Action action) { try { action(); Results.Add(new { Name = name, Passed = true }); Console.WriteLine("PASS " + name); } catch (Exception e) { failures++; Results.Add(new { Name = name, Passed = false, Error = e.ToString() }); Console.WriteLine("FAIL " + name + ": " + e.Message); } }
    private static void Assert(bool value) { if (!value) throw new InvalidOperationException("UIA assertion failed."); }
    private static void Wait(Func<bool> test, int timeout = 10000) { var clock = Stopwatch.StartNew(); while (clock.ElapsedMilliseconds < timeout) { try { if (test()) return; } catch (Exception e) when (e is ElementNotAvailableException or IOException or JsonException or InvalidOperationException) { } Thread.Sleep(100); } throw new TimeoutException("Expected UI/system state was not observed."); }
    private static AutomationElement? Find(string id, bool required = true) { var found = window.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.AutomationIdProperty, id)); if (required && found == null) throw new InvalidOperationException("Control missing: " + id); return found; }
    private static AutomationElement? FindByName(string name) => window.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.NameProperty, name));
    private static AutomationElement NativeCaption(params string[] ids)
    {
        var buttons = window.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button)).Cast<AutomationElement>();
        return buttons.FirstOrDefault(e => ids.Contains(e.Current.AutomationId)) ?? throw new InvalidOperationException("Native caption missing: " + string.Join("/", ids));
    }
    private static AutomationElement RuleRow(AutomationElement element)
    {
        for (AutomationElement? current = element; current != null; current = TreeWalker.ControlViewWalker.GetParent(current))
            if (current.Current.ControlType == ControlType.ListItem) return current;
        throw new InvalidOperationException("Rule row is not inside an actual ListBox item.");
    }
    private static void Invoke(AutomationElement e) => ((InvokePattern)e.GetCurrentPattern(InvokePattern.Pattern)).Invoke();
    private static void Click(string id) { Wait(() => Find(id)!.Current.IsEnabled); Invoke(Find(id)!); Thread.Sleep(200); }
    // Command controls expose Invoke through their accessibility peer. Invoke
    // calls the real control's OnClick; no ViewModel or state setter is called here.
    private static void Select(string id) { Click(id); InputEvents.Add(new { Target = id, Pattern = "Invoke" }); }
    private static void Toggle(string id) { Click(id); InputEvents.Add(new { Target = id, Pattern = "Invoke" }); }
    private static void Value(string id, string value) => ((ValuePattern)Find(id)!.GetCurrentPattern(ValuePattern.Pattern)).SetValue(value);
    private static WindowPattern Window() => (WindowPattern)window.GetCurrentPattern(WindowPattern.Pattern);
    private static void SelectCombo(string id, string name) { var e = Find(id)!; ((ExpandCollapsePattern)e.GetCurrentPattern(ExpandCollapsePattern.Pattern)).Expand(); Thread.Sleep(100); var item = e.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.NameProperty, name)); if (item == null) throw new InvalidOperationException("Combo item missing: " + name); ((SelectionItemPattern)item.GetCurrentPattern(SelectionItemPattern.Pattern)).Select(); }
    private static JsonElement Configuration(bool installed, string evidence) { string root = installed ? InstalledRoot() : Path.Combine(evidence, "fixture"); using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "config.json"))); return doc.RootElement.Clone(); }
    private static string InstalledRoot() { using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\WiFiProxySwitcher"); return key?.GetValue("InstallDir") as string ?? throw new IOException("No installed watcher root."); }
    private static JsonElement Heartbeat() { using var file = new FileStream(Path.Combine(InstalledRoot(), "state", "status.json"), FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete); using var doc = JsonDocument.Parse(file); return doc.RootElement.Clone(); }
    private static void CaptureText(string evidence, string name)
    {
        var all = window.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>().Select(e => new { Name = e.Current.Name, Id = e.Current.AutomationId, Type = e.Current.ControlType.ProgrammaticName });
        File.WriteAllText(Path.Combine(evidence, name + ".json"), JsonSerializer.Serialize(all, new JsonSerializerOptions { WriteIndented = true }));
        var bounds = window.Current.BoundingRectangle;
        if (bounds.Width > 0 && bounds.Height > 0)
        {
            using var bitmap = new System.Drawing.Bitmap((int)bounds.Width, (int)bounds.Height);
            using var graphics = System.Drawing.Graphics.FromImage(bitmap);
            // Capture the application's own HWND, including the native caption.
            // Screen-copy can capture a lock-screen or another app above this window.
            var hdc = graphics.GetHdc();
            bool captured;
            try { captured = PrintWindow(new IntPtr(window.Current.NativeWindowHandle), hdc, 2); }
            finally { graphics.ReleaseHdc(hdc); }
            if (!captured) throw new InvalidOperationException("Application HWND capture failed.");
            bitmap.Save(Path.Combine(evidence, name + ".png"), System.Drawing.Imaging.ImageFormat.Png);
        }
    }
}
