using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Microsoft.Win32;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;
internal sealed class AppController : IDisposable
{
    internal static string? TestRoot { get; set; }
    internal static string ControlDir => TestRoot == null ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WiFiProxySwitcher-Control") : Path.Combine(TestRoot, "control");
    internal string PowerShell => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    private readonly Lazy<PayloadCache> payload = new(CreatePayload, LazyThreadSafetyMode.ExecutionAndPublication);
    internal AppController() { }
    private static PayloadCache CreatePayload()
    {
        StartupMetrics.Mark("PayloadStart");
        SafeFiles.PlainPath(ControlDir); Directory.CreateDirectory(ControlDir);
        var asm = Assembly.GetExecutingAssembly();
        using var zip = asm.GetManifestResourceStream("payload.zip") ?? throw new InvalidDataException("内嵌脚本包缺失");
        using var manifest = asm.GetManifestResourceStream("payload.manifest.json") ?? throw new InvalidDataException("内嵌校验清单缺失");
        var cache = new PayloadCache(zip, manifest, Path.Combine(ControlDir, "packages"), "3.2.0-beta.1");
        StartupMetrics.Value("CacheHit", cache.Hit);
        StartupMetrics.Value("ExtractMs", cache.ExtractMilliseconds); StartupMetrics.Value("VerifyMs", cache.VerifyMilliseconds);
        StartupMetrics.Mark("PayloadReady");
        return cache;
    }
    internal Task WarmCache() => Task.Run(() => { _ = payload.Value; });
    internal static string? InstalledRoot()
    {
        if (TestRoot != null) return TestRoot;
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\WiFiProxySwitcher");
        string? root = key?.GetValue("InstallDir") as string;
        if (string.IsNullOrEmpty(root))
        {
            using var desktop = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\WiFiProxySwitcher");
            if (desktop?.GetValue("OwnerSid") as string == SessionGuard.Sid) root = desktop.GetValue("InstallLocation") as string;
        }
        if (!string.IsNullOrEmpty(root)) { SafeFiles.PlainPath(root); return root; }
        return null;
    }
    internal Task<CommandResult> Execute(Options options) => Task.Run(() => ExecuteCore(options));
    private async Task<CommandResult> ExecuteCore(Options options)
    {
        if (TestRoot != null) throw new InvalidOperationException("隔离验证模式禁止代理、任务和安装写入");
        SessionGuard.Validate(); payload.Value.Verify();
        if (options.Command is "pause" or "resume" or "direct" or "check" && InstalledRoot() is string installed && !File.ReadAllText(Path.Combine(installed, "ProxyWatcher.ps1")).Contains("ManagementIntent", StringComparison.Ordinal))
            throw new InvalidOperationException("当前后台引擎仍为旧版本。请先在设置的高级操作中修复安装，保留现有名单与原始代理备份。");
        if (options.Command is "pause" or "resume" or "direct" or "check" && StatusReader.IsWatcherRunning())
        {
            string activeRoot = InstalledRoot() ?? throw new InvalidOperationException("找不到运行中的后台安装。");
            using var file = new FileStream(Path.Combine(activeRoot, "state", "status.json"), FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (file.Length > 65536) throw new InvalidDataException("后台状态文件过大。");
            using var doc = JsonDocument.Parse(file); var h = doc.RootElement;
            if (!h.TryGetProperty("SchemaVersion", out var schema) || !schema.TryGetInt32(out int number) || number < 2 ||
                !h.TryGetProperty("EngineVersion", out var version) || !Version.TryParse(version.GetString()?.Split('-')[0], out var engine) || engine < new Version(3, 2) ||
                !h.TryGetProperty("Time", out var time) || !DateTimeOffset.TryParse(time.ToString(), out var heartbeatTime) ||
                (DateTimeOffset.Now - heartbeatTime).TotalSeconds is < -5 or > 615)
                throw new InvalidOperationException("运行中的后台尚未确认新协议。请升级后台组件后再管理代理。");
        }
        string resultPath = Path.Combine(ControlDir, "result-" + Guid.NewGuid().ToString("N") + ".json");
        var args = new List<string> { "-Action", options.Command, "-Quiet", "-ResultPath", resultPath };
        string? root = options.InstallDir ?? InstalledRoot();
        if (root != null) { args.Add("-InstallDir"); args.Add(root); }
        if (options.Command == "install") { args.Add("-DesktopSource"); args.Add(Environment.ProcessPath!); }
        if (options.SetupConfigPath != null) { args.Add("-SetupConfigPath"); args.Add(options.SetupConfigPath); }
        if (options.Force) args.Add("-ForceRestore"); if (options.Keep) args.Add("-KeepCurrentProxy");
        try
        {
            var run = await EngineProcess.RunAsync(EngineProcess.Prepare(PowerShell, Path.Combine(payload.Value.Root, "Control.ps1"), args), TimeSpan.FromMinutes(3));
            if (!File.Exists(resultPath)) return new(false, "EngineFailed", string.IsNullOrWhiteSpace(run.Error) ? "引擎未返回结果，请检查执行策略及控制日志。" : run.Error);
            return EngineProcess.ParseResult(await File.ReadAllTextAsync(resultPath), run.Code);
        }
        finally { if (File.Exists(resultPath)) File.Delete(resultPath); }
    }
    internal async Task<(int Code, string Json, string Path)> Diagnostic(string? path)
    {
        if (TestRoot != null) throw new InvalidOperationException("隔离验证禁止调用系统诊断进程");
        SessionGuard.Validate(); await WarmCache(); await Task.Run(() => payload.Value.Verify());
        path = Path.GetFullPath(path ?? Path.Combine(ControlDir, "diagnostics.json")); SafeFiles.PlainPath(path);
        var p = EngineProcess.Prepare(PowerShell, Path.Combine(payload.Value.Root, "Diagnose.ps1"), new[] { "-Quiet", "-OutputPath", path });
        var r = await EngineProcess.RunAsync(p, TimeSpan.FromMinutes(2));
        if (!File.Exists(path)) throw new IOException("诊断未生成报告: " + r.Error);
        return (r.Code, await File.ReadAllTextAsync(path), path);
    }
    internal void BeginUninstall(Options o)
    {
        if (TestRoot != null) throw new InvalidOperationException("隔离验证禁止卸载");
        // Execute from an owned temporary copy after this UI exits, so the installed EXE is not locked.
        string parent = Path.Combine(ControlDir, "uninstall-helper"); SafeFiles.PlainPath(parent); Directory.CreateDirectory(parent);
        foreach (var stale in Directory.EnumerateFiles(parent, "helper-*.exe"))
            if (File.GetLastWriteTimeUtc(stale) < DateTime.UtcNow.AddDays(-1)) { try { SafeFiles.PlainPath(stale); File.Delete(stale); } catch (IOException) { } }
        string helper = Path.Combine(parent, "helper-" + Guid.NewGuid().ToString("N") + ".exe");
        string resultPath = Path.Combine(ControlDir, "uninstall-result.json"); SafeFiles.PlainPath(resultPath);
        File.WriteAllText(resultPath, JsonSerializer.Serialize(new { Succeeded = false, Code = "UninstallStarted", Time = DateTimeOffset.Now }));
        File.Copy(Environment.ProcessPath!, helper);
        if (SafeFiles.Hash(helper) != SafeFiles.Hash(Environment.ProcessPath!)) throw new IOException("卸载程序复制校验失败");
        using var current = Process.GetCurrentProcess();
        var p = new ProcessStartInfo(helper) { UseShellExecute = false, CreateNoWindow = true };
        foreach (var a in new[] { "/uninstall", "/worker", current.Id.ToString(), current.StartTime.ToUniversalTime().Ticks.ToString() }) p.ArgumentList.Add(a);
        if (o.Quiet) p.ArgumentList.Add("/quiet"); if (o.Force) p.ArgumentList.Add("/force-restore"); if (o.Keep) p.ArgumentList.Add("/keep-current");
        using var child = Process.Start(p) ?? throw new IOException("无法启动卸载程序");
    }
    internal static void WaitForParent(Options options)
    {
        try
        {
            using var p = Process.GetProcessById(options.WorkerPid);
            if (p.StartTime.ToUniversalTime().Ticks != options.WorkerStart) throw new InvalidOperationException("卸载等待进程身份已改变");
            if (!p.WaitForExit(45000)) throw new TimeoutException("请关闭正在运行的状态窗口后重试卸载");
        }
        catch (ArgumentException) { /* Parent already exited. No process is killed. */ }
    }
    public void Dispose() { /* The verified cache persists across launches. */ }
}
