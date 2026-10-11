using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace WiFiProxySwitcher.Core;

public sealed record Options(string Command, bool Quiet = false, bool Force = false, bool Keep = false,
    string? Output = null, string? InstallDir = null, int WorkerPid = 0, long WorkerStart = 0)
{
    public static Options Parse(string[] args)
    {
        if (args.Length == 0) return new("gui");
        var command = args[0].ToLowerInvariant();
        if (!new[] { "/install", "/uninstall", "/restore", "/status", "/start", "/stop", "/check", "/self-test" }.Contains(command))
            throw new ArgumentException("未知命令。支持 /install /uninstall /restore /status /start /stop /check。");
        var o = new Options(command[1..]);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (int i = 1; i < args.Length; i++)
        {
            string flag = args[i].ToLowerInvariant();
            if (!seen.Add(flag)) throw new ArgumentException("重复参数: " + flag);
            string Value() => ++i < args.Length && !string.IsNullOrWhiteSpace(args[i]) ? args[i] : throw new ArgumentException("参数缺少值: " + flag);
            o = flag switch
            {
                "/quiet" => o with { Quiet = true },
                "/force-restore" when o.Command is "restore" or "uninstall" => o with { Force = true },
                "/keep-current" when o.Command == "uninstall" => o with { Keep = true },
                "/output" when o.Command is "status" or "self-test" => o with { Output = Value() },
                "/install-dir" when o.Command == "install" => o with { InstallDir = Value() },
                "/worker" when o.Command == "uninstall" => o with { WorkerPid = int.Parse(Value()), WorkerStart = long.Parse(Value()) },
                _ => throw new ArgumentException("此命令不支持参数: " + flag)
            };
        }
        if (o.Force && o.Keep) throw new ArgumentException("恢复原配置和保留当前配置不能同时选择。");
        if (o.WorkerPid < 0 || o.WorkerStart < 0 || (o.WorkerPid != 0 && o.WorkerStart == 0)) throw new ArgumentException("卸载进程参数无效。");
        return o;
    }
}

public static class IdentityRules
{
    public static void Validate(string processSid, string desktopSid, int sessionId)
    {
        if (sessionId == 0 || new[] { "S-1-5-18", "S-1-5-19", "S-1-5-20" }.Contains(processSid))
            throw new InvalidOperationException("请在当前桌面用户会话运行，不能使用 SYSTEM 或服务账户。");
        if (string.IsNullOrEmpty(desktopSid) || !string.Equals(processSid, desktopSid, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("运行账户与当前桌面用户不同。请使用自己的桌面账户运行，避免更改另一账户的代理。");
    }
}

public static class SafeFiles
{
    public static void PlainPath(string path)
    {
        for (var p = Path.GetFullPath(path); !string.IsNullOrEmpty(p); p = Path.GetDirectoryName(p))
            if ((File.Exists(p) || Directory.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("路径含链接或联接点: " + p);
    }
    public static string Under(string root, string relative)
    {
        if (relative.Contains('\\') || relative.Contains(':') || relative.StartsWith('/') || relative.Split('/').Any(s => s is "" or "." or ".."))
            throw new InvalidDataException("包内路径无效: " + relative);
        string full = Path.GetFullPath(Path.Combine(root, relative));
        if (!full.StartsWith(Path.GetFullPath(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("包内路径越界");
        PlainPath(full); return full;
    }
    public static string Hash(string path) { using var s = File.OpenRead(path); return Convert.ToHexString(SHA256.HashData(s)); }
}

public sealed class Payload : IDisposable
{
    public string Root { get; }
    private readonly Dictionary<string, string> hashes;
    private readonly List<string> written = new();
    public Payload(Stream zip, Stream manifest, string parent)
    {
        hashes = JsonSerializer.Deserialize<Dictionary<string, string>>(manifest) ?? throw new InvalidDataException("包清单为空");
        if (hashes.Count == 0 || hashes.Count > 256) throw new InvalidDataException("包清单数量无效");
        SafeFiles.PlainPath(parent); Directory.CreateDirectory(parent);
        Root = Path.Combine(parent, "package-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(Root);
        try
        {
            using var archive = new ZipArchive(zip, ZipArchiveMode.Read, leaveOpen: true);
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase); long total = 0;
            foreach (var e in archive.Entries)
            {
                string target = SafeFiles.Under(Root, e.FullName);
                if (!seen.Add(e.FullName) || !hashes.TryGetValue(e.FullName, out var hash) || e.Length > 4 * 1024 * 1024 || (total += e.Length) > 16 * 1024 * 1024)
                    throw new InvalidDataException("包文件未知、重复或超出容量限制");
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                written.Add(target);
                using (var source = e.Open()) using (var dest = new FileStream(target, FileMode.CreateNew, FileAccess.Write)) source.CopyTo(dest);
                if (!string.Equals(SafeFiles.Hash(target), hash, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("包文件 SHA256 校验失败: " + e.FullName);
            }
            if (seen.Count != hashes.Count) throw new InvalidDataException("包文件缺失");
        }
        catch { Dispose(); throw; }
    }
    public void Verify()
    {
        foreach (var pair in hashes)
            if (!string.Equals(SafeFiles.Hash(SafeFiles.Under(Root, pair.Key)), pair.Value, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("提取后的脚本已改变，拒绝执行");
    }
    public void Dispose()
    {
        if (!Directory.Exists(Root)) return;
        SafeFiles.PlainPath(Root);
        foreach (var path in written)
        {
            try { SafeFiles.PlainPath(path); if (File.Exists(path)) File.Delete(path); }
            catch (IOException) { /* Leave unexpected cache content for diagnosis. */ }
        }
        foreach (var d in written.Select(p => Path.GetDirectoryName(p)!).Distinct().OrderByDescending(p => p.Length))
            if (Directory.Exists(d) && !Directory.EnumerateFileSystemEntries(d).Any()) Directory.Delete(d);
        if (Directory.Exists(Root) && !Directory.EnumerateFileSystemEntries(Root).Any()) Directory.Delete(Root);
    }
}

public sealed record CommandResult(bool Succeeded, string Code, string Message, JsonElement? Data = null);
public static class EngineProcess
{
    public static ProcessStartInfo Prepare(string executable, string script, IEnumerable<string> arguments)
    {
        var p = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = Path.GetDirectoryName(script)! };
        foreach (var arg in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script }.Concat(arguments)) p.ArgumentList.Add(arg);
        return p;
    }
    public static async Task<(int Code, string Output, string Error)> RunAsync(ProcessStartInfo info, TimeSpan timeout)
    {
        using var process = Process.Start(info) ?? throw new IOException("无法启动 Windows PowerShell");
        var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
        using var cts = new CancellationTokenSource(timeout);
        try { await process.WaitForExitAsync(cts.Token); }
        catch (OperationCanceledException) { process.Kill(entireProcessTree: true); await process.WaitForExitAsync(); throw new TimeoutException("操作超时。保留安装记录和备份，请查看诊断后重试。"); }
        return (process.ExitCode, await output, await error);
    }
    public static CommandResult ParseResult(string json, int processCode)
    {
        var r = JsonSerializer.Deserialize<CommandResult>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new InvalidDataException("引擎没有返回结果");
        if (r.Succeeded && processCode != 0) throw new InvalidDataException("引擎退出码与结果不一致");
        return r;
    }
}
