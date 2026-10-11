using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Microsoft.Win32;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;
internal sealed class AppController : IDisposable
{
    internal static string ControlDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WiFiProxySwitcher-Control");
    internal string PowerShell => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    private readonly Payload payload;
    internal AppController()
    {
        SafeFiles.PlainPath(ControlDir); Directory.CreateDirectory(ControlDir);
        var asm = Assembly.GetExecutingAssembly();
        using var zip = asm.GetManifestResourceStream("payload.zip") ?? throw new InvalidDataException("内嵌脚本包缺失");
        using var manifest = asm.GetManifestResourceStream("payload.manifest.json") ?? throw new InvalidDataException("内嵌校验清单缺失");
        payload = new Payload(zip, manifest, Path.Combine(ControlDir, "packages"));
    }
    internal static string? InstalledRoot()
    {
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
    internal async Task<CommandResult> Execute(Options options)
    {
        SessionGuard.Validate(); payload.Verify();
        string resultPath = Path.Combine(ControlDir, "result-" + Guid.NewGuid().ToString("N") + ".json");
        var args = new List<string> { "-Action", options.Command, "-Quiet", "-ResultPath", resultPath };
        string? root = options.InstallDir ?? InstalledRoot();
        if (root != null) { args.Add("-InstallDir"); args.Add(root); }
        if (options.Command == "install") { args.Add("-DesktopSource"); args.Add(Environment.ProcessPath!); }
        if (options.Force) args.Add("-ForceRestore"); if (options.Keep) args.Add("-KeepCurrentProxy");
        try
        {
            var run = await EngineProcess.RunAsync(EngineProcess.Prepare(PowerShell, Path.Combine(payload.Root, "Control.ps1"), args), TimeSpan.FromMinutes(3));
            if (!File.Exists(resultPath)) return new(false, "EngineFailed", string.IsNullOrWhiteSpace(run.Error) ? "引擎未返回结果，请检查执行策略及控制日志。" : run.Error);
            return EngineProcess.ParseResult(await File.ReadAllTextAsync(resultPath), run.Code);
        }
        finally { if (File.Exists(resultPath)) File.Delete(resultPath); }
    }
    internal async Task<(int Code, string Json, string Path)> Diagnostic(string? path)
    {
        SessionGuard.Validate(); payload.Verify();
        path = Path.GetFullPath(path ?? Path.Combine(ControlDir, "diagnostics.json")); SafeFiles.PlainPath(path);
        var p = EngineProcess.Prepare(PowerShell, Path.Combine(payload.Root, "Diagnose.ps1"), new[] { "-Quiet", "-OutputPath", path });
        var r = await EngineProcess.RunAsync(p, TimeSpan.FromMinutes(2));
        if (!File.Exists(path)) throw new IOException("诊断未生成报告: " + r.Error);
        return (r.Code, await File.ReadAllTextAsync(path), path);
    }
    internal void BeginUninstall(Options o)
    {
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
    public void Dispose() => payload.Dispose();
}
