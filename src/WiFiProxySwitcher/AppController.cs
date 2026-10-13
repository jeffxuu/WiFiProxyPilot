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
        string? installedDesktop = InstallerAppDirectory();
        var cache = installedDesktop == null ? new PayloadCache(zip, manifest, Path.Combine(ControlDir, "packages"), "3.3.0-beta.1")
            : new PayloadCache(Path.Combine(installedDesktop, "engine"), manifest);
        StartupMetrics.Value("CacheHit", cache.Hit);
        StartupMetrics.Value("ExtractMs", cache.ExtractMilliseconds); StartupMetrics.Value("VerifyMs", cache.VerifyMilliseconds);
        StartupMetrics.Mark("PayloadReady");
        return cache;
    }
    private static string? InstallerAppDirectory()
    {
        if (TestRoot != null) return null;
        using var owner = Registry.CurrentUser.OpenSubKey(@"Software\WiFiProxySwitcher");
        if (owner?.GetValue("DesktopOwner") as string != "Inno") return null;
        string directory = Path.GetFullPath(owner.GetValue("DesktopAppDir") as string ?? throw new IOException("Installer path missing."));
        SafeFiles.PlainPath(directory);
        string markerPath = Path.Combine(directory, "installer-owned.json"); SafeFiles.PlainPath(markerPath);
        using var marker = JsonDocument.Parse(File.ReadAllText(markerPath)); var data = marker.RootElement;
        if (data.GetProperty("Product").GetString() != "WiFiProxyPilot-Inno-v1" || data.GetProperty("OwnerSid").GetString() != SessionGuard.Sid ||
            !string.Equals(data.GetProperty("AppDir").GetString(), directory, StringComparison.OrdinalIgnoreCase) ||
            data.GetProperty("AppId").GetString() != "{15F7908C-5C54-4D45-9343-1973BFEA3B47}")
            throw new IOException("Installer ownership could not be verified.");
        // A portable copy must use its own embedded engine, even if an installed edition exists.
        return string.Equals(Path.GetFullPath(AppContext.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar), directory.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase) ? directory : null;
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
    internal Task<CommandResult> Execute(Options options) => Task.Run(async () =>
    {
        string request = Guid.NewGuid().ToString("N");
        CommandTrace.Write(options.Command, "ControllerReceived", requestId: request);
        try
        {
            var result = await ExecuteCore(options);
            CommandTrace.Write(options.Command, "EngineReturned", result.Code, request);
            if (result.Succeeded && options.Command is "install" or "resume" or "start" or "pause" or "direct")
                result = await VerifyManagementResult(options, result);
            CommandTrace.Write(options.Command, result.Succeeded ? "ReadbackConfirmed" : "Failed", result.Code, request);
            return result;
        }
        catch (Exception error)
        {
            CommandTrace.Write(options.Command, "Exception", error.GetType().Name, request);
            throw;
        }
    });
    private async Task<CommandResult> ExecuteCore(Options options)
    {
        if (TestRoot != null) throw new InvalidOperationException("隔离验证模式禁止代理、任务和安装写入");
        SessionGuard.Validate(); payload.Value.Verify();
        if (options.Command is "pause" or "resume" or "direct" or "check" && InstalledRoot() is string installed && !File.ReadAllText(Path.Combine(installed, "ProxyWatcher.ps1")).Contains("$script:EngineProtocol=2", StringComparison.Ordinal))
            return new(false, "EngineUpgradeRequired", "The installed watcher protocol requires an upgrade.");
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
                return new(false, "EngineUpgradeRequired", "The running watcher has not confirmed a compatible protocol.");
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
            CommandTrace.Write(options.Command, "PowerShellStarted");
            var run = await EngineProcess.RunAsync(EngineProcess.Prepare(PowerShell, Path.Combine(payload.Value.Root, "Control.ps1"), args), TimeSpan.FromMinutes(3));
            if (!File.Exists(resultPath)) return new(false, "EngineFailed", string.IsNullOrWhiteSpace(run.Error) ? "引擎未返回结果，请检查执行策略及控制日志。" : run.Error);
            return EngineProcess.ParseResult(await File.ReadAllTextAsync(resultPath), run.Code);
        }
        finally { if (File.Exists(resultPath)) File.Delete(resultPath); }
    }
    private static async Task<CommandResult> VerifyManagementResult(Options options, CommandResult result)
    {
        string? root = InstalledRoot();
        if (root == null) return new(false, "InstallNotConfirmed", "No owned installation was found after the command.");
        ManagementIntent expected = options.Command switch
        {
            "pause" => ManagementIntent.Paused, "direct" => ManagementIntent.Direct,
            "resume" or "start" => ManagementIntent.Monitoring, _ => ConfigurationStore.Read(root).Intent
        };
        var deadline = Stopwatch.StartNew();
        while (deadline.Elapsed < TimeSpan.FromSeconds(20))
        {
            var config = ConfigurationStore.Read(root);
            if (config.Intent != expected) return new(false, "IntentMismatch", "The persisted management intent did not match the requested operation.");
            bool running = StatusReader.IsWatcherRunning();
            bool acknowledged = expected != ManagementIntent.Monitoring && !running;
            string heartbeat = Path.Combine(root, "state", "status.json");
            if (running && File.Exists(heartbeat))
            {
                try
                {
                    using var file = new FileStream(heartbeat, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    if (file.Length > 65536) throw new InvalidDataException("Heartbeat exceeds the size limit.");
                    using var doc = JsonDocument.Parse(file); var h = doc.RootElement;
                    acknowledged = h.TryGetProperty("ManagementIntent", out var intent) && intent.GetString() == expected.ToString() &&
                        h.TryGetProperty("ConfigRevision", out var revision) && revision.GetString() == config.Revision &&
                        h.TryGetProperty("Outcome", out var outcome) && outcome.GetString() is not ("Starting" or "Stopped") &&
                        h.TryGetProperty("Time", out var time) && DateTimeOffset.TryParse(time.GetString(), out var updated) &&
                        (DateTimeOffset.Now - updated).TotalSeconds is >= -5 and < 30;
                }
                catch (Exception error) when (error is IOException or JsonException) { acknowledged = false; }
            }
            if (acknowledged)
            {
                var actual = WiFiProxy.Native.ReadProxy();
                using var registry = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings");
                bool enabled = Convert.ToInt32(registry?.GetValue("ProxyEnable", 0)) == 1;
                if (enabled != actual.Enable) return new(false, "ProxyReadbackMismatch", "WinINet and registry disagree about the current manual proxy.");
                if (expected == ManagementIntent.Direct && actual.Enable) return new(false, "DirectNotConfirmed", "The manual proxy is still enabled.");
                // A running watcher can deliberately keep existing proxy settings for unknown/ambiguous networks.
                return result with { Code = "ManagementConfirmed", Data = JsonSerializer.SerializeToElement(new { Intent = expected.ToString(), WatcherRunning = running, ManualProxyEnabled = actual.Enable }) };
            }
            await Task.Delay(150);
        }
        return new(false, "WatcherConfirmationTimeout", "The intent was saved, but the watcher did not acknowledge it. Read the actual state and command log before retrying.");
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
    internal bool BeginUninstall(Options o)
    {
        if (TestRoot != null) throw new InvalidOperationException("隔离验证禁止卸载");
        SessionGuard.Validate();
        using (var owner = Registry.CurrentUser.OpenSubKey(@"Software\WiFiProxySwitcher"))
        {
            if (owner?.GetValue("DesktopOwner") as string == "Inno")
            {
                string directory = Path.GetFullPath(owner.GetValue("DesktopAppDir") as string ?? throw new IOException("Installer application path missing."));
                SafeFiles.PlainPath(directory);
                string markerPath = Path.Combine(directory, "installer-owned.json"); SafeFiles.PlainPath(markerPath);
                using var marker = JsonDocument.Parse(File.ReadAllText(markerPath)); var data = marker.RootElement;
                if (data.GetProperty("Product").GetString() != "WiFiProxyPilot-Inno-v1" || data.GetProperty("OwnerSid").GetString() != SessionGuard.Sid ||
                    !string.Equals(data.GetProperty("AppDir").GetString(), directory, StringComparison.OrdinalIgnoreCase) ||
                    data.GetProperty("AppId").GetString() != "{15F7908C-5C54-4D45-9343-1973BFEA3B47}")
                    throw new IOException("Installer ownership could not be verified. Nothing was removed.");
                string uninstaller = Path.Combine(directory, "unins000.exe"); SafeFiles.PlainPath(uninstaller);
                var info = new ProcessStartInfo(uninstaller) { UseShellExecute = false };
                // Proxy disposition and user-data retention are chosen in the uninstaller itself.
                if (o.Quiet) throw new InvalidOperationException("Use the installed uninstaller for unattended removal with an explicit proxy disposition.");
                using var started = Process.Start(info) ?? throw new IOException("Cannot start the registered uninstaller.");
                return false; // Installer makes all choices before asking the running UI to exit.
            }
        }
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
        return true; // Legacy worker must wait for this executable to release its file.
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
