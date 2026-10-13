using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;

// Drives the final Inno EXE through native controls. No script-install shortcut,
// fake screenshots, ViewModel calls, or production-host installation is allowed.
internal static class SetupWizard
{
    private static readonly List<object> stages = new(), captures = new();
    private static string currentStage = "Launch", evidence = "";
    private static AutomationElement wizard = null!;
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern bool Process32First(IntPtr snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern bool Process32Next(IntPtr snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct ProcessEntry
    {
        public uint Size, Usage, ProcessId; public IntPtr Heap; public uint ModuleId, Threads, ParentId; public int Priority; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string File;
    }

    internal static int Run(string[] args)
    {
        if (Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true" || Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT") != "github-hosted")
            throw new InvalidOperationException("Interactive installer tests are restricted to a disposable GitHub-hosted Windows runner.");
        if (args.Length < 2) throw new ArgumentException("Final Setup EXE and evidence directory are required.");
        string setup = Path.GetFullPath(args[0]); evidence = Path.GetFullPath(args[1]); Directory.CreateDirectory(evidence);
        string appDir = Path.GetFullPath(Option(args, "--app-dir"));
        string language = Option(args, "--language");
        if (language is not ("en-US" or "zh-CN")) throw new ArgumentException("Wizard language must be en-US or zh-CN.");
        if (Path.GetFileName(setup) != "WiFiProxyPilot-Setup-x64.exe") throw new ArgumentException("Test the final Setup artifact.");
        if (!appDir.StartsWith(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Wizard tests require a dedicated directory inside the disposable user's LocalAppData.");
        bool zh = language == "zh-CN", succeeded = false;
        string next = zh ? "下一步 >" : "Next >", install = zh ? "安装" : "Install", finish = zh ? "完成" : "Finish";
        string welcome = zh ? "欢迎使用" : "Welcome to the", license = zh ? "许可协议" : "License Agreement";
        string directory = zh ? "选择目标位置" : "Select Destination Location", tasks = zh ? "选择附加任务" : "Select Additional Tasks";
        string ready = zh ? "准备安装" : "Ready to Install", installing = zh ? "正在安装" : "Installing", finished = zh ? "完成 WiFi Proxy Pilot 安装向导" : "Completing the WiFi Proxy Pilot Setup Wizard";
        string accept = zh ? "我同意此协议" : "I accept the agreement", desktop = zh ? "创建桌面快捷方式" : "Create a desktop shortcut";
        var info = new ProcessStartInfo(setup) { UseShellExecute = false };
        foreach (string arg in new[] { "/LANG=" + language.Replace('-', '_'), "/DIR=" + appDir, "/NORESTART", "/TASKS=desktopicon", "/LOG=" + Path.Combine(evidence, "setup-wizard.log") }) info.ArgumentList.Add(arg);
        using var process = Process.Start(info) ?? throw new IOException("Final Setup did not start.");
        try
        {
            Wait(() => { var related = Descendants(process.Id); wizard = AutomationElement.RootElement.FindAll(TreeScope.Children, Condition.TrueCondition).Cast<AutomationElement>()
                .FirstOrDefault(e => related.Contains(e.Current.ProcessId) && e.Current.ClassName == "TWizardForm" && e.Current.Name.Contains("WiFi Proxy Pilot", StringComparison.Ordinal))!; return wizard != null; }, 30000);
            Step("Welcome page is displayed in " + language, () => { Wait(() => PageContains(welcome)); Assert(wizard.Current.Name.StartsWith(zh ? "安装" : "Setup", StringComparison.Ordinal)); Capture("01-welcome"); Invoke(Button(next)); });
            Step("Native license acceptance enables Next", () => { Wait(() => PageContains(license)); Capture("02-license"); Assert(!Button(next).Current.IsEnabled); SelectNative(FindName(accept)); Wait(() => Button(next).Current.IsEnabled); Invoke(Button(next)); });
            Step("Directory edit uses the Chinese and space path", () =>
            {
                Wait(() => PageContains(directory));
                var edit = Elements().FirstOrDefault(e => e.Current.ControlType == ControlType.Edit && e.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern) && !((ValuePattern)pattern).Current.IsReadOnly)
                    ?? throw new InvalidOperationException("Native directory edit is missing.");
                ((ValuePattern)edit.GetCurrentPattern(ValuePattern.Pattern)).SetValue(appDir);
                Assert(string.Equals(((ValuePattern)edit.GetCurrentPattern(ValuePattern.Pattern)).Current.Value, appDir, StringComparison.OrdinalIgnoreCase));
                Capture("03-directory"); Invoke(Button(next));
            });
            Step("Desktop shortcut task is present in the selected language", () => { Wait(() => PageContains(tasks)); Assert(PageContains(desktop)); Capture("04-tasks"); Invoke(Button(next)); });
            Step("Ready page exposes the real Install button", () => { Wait(() => PageContains(ready)); Assert(Button(install).Current.IsEnabled); Capture("05-ready"); });
            Step("Actual native Install control displays installation progress", () =>
            {
                var installButton = Button(install); var invoke = Task.Run(() => Invoke(installButton));
                Wait(() => PageContains(installing) || PageContains(finished), 180000, 25);
                Assert(PageContains(installing)); Capture("06-progress");
                Wait(() => PageContains(finished), 180000, 50);
                if (!invoke.Wait(10000)) throw new TimeoutException("Install control invocation did not finish."); invoke.GetAwaiter().GetResult();
            });
            Step("Completion page and Finish finish the final Setup EXE", () => { Assert(Button(finish).Current.IsEnabled); Capture("07-finish"); Invoke(Button(finish)); Assert(process.WaitForExit(30000)); Assert(process.ExitCode == 0); });
            Step("Installed application identity is verified before UI shutdown", () =>
            {
                string exe = VerifyApplication(appDir);
                var shutdown = new ProcessStartInfo(exe) { UseShellExecute = false, CreateNoWindow = true };
                shutdown.ArgumentList.Add("/shutdown-ui"); shutdown.ArgumentList.Add("/quiet");
                using var child = Process.Start(shutdown) ?? throw new IOException("Verified application shutdown did not start.");
                Assert(child.WaitForExit(30000)); Assert(child.ExitCode == 0);
            });
            succeeded = true;
        }
        catch (Exception error)
        {
            stages.Add(new { Name = currentStage, Passed = false, Error = error.ToString() });
            Console.WriteLine("FAIL " + currentStage + ": " + error.Message);
            try { if (wizard != null) Capture("failure"); } catch (Exception captureError) { captures.Add(new { Name = "failure", ActualClientPixels = false, Error = captureError.Message }); }
        }
        finally
        {
            if (!process.HasExited) { process.Kill(entireProcessTree: true); process.WaitForExit(); }
            File.WriteAllText(Path.Combine(evidence, "wizard-results.json"), JsonSerializer.Serialize(new { Succeeded = succeeded, Language = language, SetupSha256 = Hash(setup), AppDir = appDir, Stages = stages, Captures = captures,
                Boundary = "Final Setup EXE, actual native controls, disposable GitHub-hosted Windows only" }, new JsonSerializerOptions { WriteIndented = true }));
        }
        return succeeded ? 0 : 1;
    }
    private static string Option(string[] args, string key) { int index = Array.IndexOf(args, key); return index >= 0 && index + 1 < args.Length ? args[index + 1] : throw new ArgumentException("Missing " + key); }
    private static void Step(string name, Action body) { currentStage = name; body(); stages.Add(new { Name = name, Passed = true }); Console.WriteLine("PASS " + name); }
    private static void Assert(bool value) { if (!value) throw new InvalidOperationException("Actual installer wizard assertion failed."); }
    private static string Normalize(string text) => Regex.Replace(text.Replace("&", ""), @"\([A-Za-z]\)", "").Trim();
    private static AutomationElement[] Elements() => wizard.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>().Where(e => !e.Current.IsOffscreen).ToArray();
    private static bool PageContains(string text) => Elements().Any(e => Normalize(e.Current.Name).Contains(text, StringComparison.Ordinal));
    private static AutomationElement FindName(string name) => Elements().FirstOrDefault(e => Normalize(e.Current.Name) == name) ?? throw new InvalidOperationException("Native wizard control missing: " + name);
    private static AutomationElement Button(string name) => Elements().FirstOrDefault(e => e.Current.ControlType == ControlType.Button && Normalize(e.Current.Name) == name) ?? throw new InvalidOperationException("Native wizard button missing: " + name);
    private static void Invoke(AutomationElement element)
    {
        Assert(element.Current.IsEnabled);
        if (element.TryGetCurrentPattern(InvokePattern.Pattern, out var invoke)) ((InvokePattern)invoke).Invoke();
        else NativeButtonClick(element);
    }
    private static void SelectNative(AutomationElement element)
    {
        if (element.TryGetCurrentPattern(InvokePattern.Pattern, out var invoke)) ((InvokePattern)invoke).Invoke();
        else if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var selection)) ((SelectionItemPattern)selection).Select();
        else NativeButtonClick(element);
    }
    private static void NativeButtonClick(AutomationElement element)
    {
        // VCL's TNewButton/TNewRadioButton inherit the native Button behavior.
        // BM_CLICK delivers real down/up and BN_CLICKED; it does not set checked
        // state or bypass the native OnClick event. Page changes are asserted later.
        Assert(element.Current.IsEnabled && element.Current.NativeWindowHandle != 0 && element.Current.ClassName is "TNewButton" or "TNewRadioButton");
        if (!PostMessage(new IntPtr(element.Current.NativeWindowHandle), 0x00F5, IntPtr.Zero, IntPtr.Zero)) throw new IOException("Native button activation was not delivered.");
    }
    private static void Wait(Func<bool> condition, int milliseconds = 10000, int interval = 100)
    {
        var clock = Stopwatch.StartNew(); while (clock.ElapsedMilliseconds < milliseconds) { try { if (condition()) return; } catch (Exception error) when (error is ElementNotAvailableException or InvalidOperationException) { } Thread.Sleep(interval); }
        throw new TimeoutException("Expected actual installer page/control was not observed.");
    }
    private static HashSet<int> Descendants(int root)
    {
        var parents = new Dictionary<int, int>(); var handle = CreateToolhelp32Snapshot(2, 0); if (handle == new IntPtr(-1)) throw new IOException("Cannot identify Setup child process.");
        try { var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf<ProcessEntry>(), File = "" }; if (Process32First(handle, ref entry)) do { parents[(int)entry.ProcessId] = (int)entry.ParentId; } while (Process32Next(handle, ref entry)); }
        finally { CloseHandle(handle); }
        var related = new HashSet<int> { root }; bool changed; do { changed = false; foreach (var item in parents) if (related.Contains(item.Value) && related.Add(item.Key)) changed = true; } while (changed); return related;
    }
    private static string Hash(string path) { using var stream = File.OpenRead(path); return Convert.ToHexString(SHA256.HashData(stream)); }
    private static string VerifyApplication(string appDir)
    {
        using var owner = JsonDocument.Parse(File.ReadAllText(Path.Combine(appDir, "installer-owned.json"))); var marker = owner.RootElement;
        Assert(marker.GetProperty("Product").GetString() == "WiFiProxyPilot-Inno-v1" && marker.GetProperty("OwnerSid").GetString() == WindowsIdentity.GetCurrent().User?.Value && string.Equals(marker.GetProperty("AppDir").GetString(), appDir, StringComparison.OrdinalIgnoreCase));
        string receipt = Path.Combine(appDir, "installer-files.json"); Assert(Hash(receipt) == marker.GetProperty("ReceiptSha256").GetString());
        using var files = JsonDocument.Parse(File.ReadAllText(receipt)); bool ownsExe = false;
        foreach (var file in files.RootElement.GetProperty("Files").EnumerateArray())
        {
            string name = file.GetProperty("Path").GetString() ?? throw new IOException("Invalid installed receipt.");
            Assert(!Path.IsPathRooted(name) && !name.Contains(':') && !name.Split('/', '\\').Any(part => part is "." or ".."));
            string path = Path.GetFullPath(Path.Combine(appDir, name)); Assert(path.StartsWith(appDir.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)); Assert(Hash(path) == file.GetProperty("Hash").GetString());
            if (name == "WiFiProxyPilot.exe") ownsExe = true;
        }
        Assert(ownsExe); Assert(Hash(Path.Combine(appDir, "unins000.exe")) == marker.GetProperty("UninstallerSha256").GetString());
        return Path.Combine(appDir, "WiFiProxyPilot.exe");
    }
    private static void Capture(string name)
    {
        var elements = Elements().Select(e => new { Name = e.Current.Name, Id = e.Current.AutomationId, Class = e.Current.ClassName, Type = e.Current.ControlType.ProgrammaticName, Enabled = e.Current.IsEnabled }).ToArray();
        File.WriteAllText(Path.Combine(evidence, name + ".json"), JsonSerializer.Serialize(elements, new JsonSerializerOptions { WriteIndented = true }));
        var rect = wizard.Current.BoundingRectangle; if (rect.Width <= 0 || rect.Height <= 0) { captures.Add(new { Name = name, ActualClientPixels = false, Reason = "No native window bounds" }); return; }
        using var bitmap = new System.Drawing.Bitmap((int)rect.Width, (int)rect.Height); using var graphics = System.Drawing.Graphics.FromImage(bitmap); var hdc = graphics.GetHdc(); bool printed;
        try { printed = PrintWindow(new IntPtr(wizard.Current.NativeWindowHandle), hdc, 2); } finally { graphics.ReleaseHdc(hdc); }
        var colors = new HashSet<int>(); for (int y = 60; y < bitmap.Height - 10; y += 8) for (int x = 12; x < bitmap.Width - 12; x += 8) colors.Add(bitmap.GetPixel(x, y).ToArgb());
        bool content = printed && colors.Count > 8; if (content) bitmap.Save(Path.Combine(evidence, name + ".png"), System.Drawing.Imaging.ImageFormat.Png);
        captures.Add(new { Name = name, ActualClientPixels = content, Source = "Actual native HWND PrintWindow", Reason = content ? "Actual pixels; review the image before visual acceptance" : "No complete client image captured; not screenshot evidence" });
    }
}
