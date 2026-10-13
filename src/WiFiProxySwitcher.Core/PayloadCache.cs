using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace WiFiProxySwitcher.Core;

/// <summary>Immutable, content-addressed script cache. A hit is fully hashed, never trusted by timestamp.</summary>
public sealed class PayloadCache
{
    public string Root { get; private set; } = "";
    public bool Hit { get; private set; }
    public double VerifyMilliseconds { get; private set; }
    public double ExtractMilliseconds { get; private set; }
    private readonly Dictionary<string, string> hashes;
    public PayloadCache(Stream zip, Stream manifest, string parent, string version)
    {
        using var bytes = new MemoryStream(); manifest.CopyTo(bytes);
        hashes = JsonSerializer.Deserialize<Dictionary<string, string>>(bytes.ToArray()) ?? throw new InvalidDataException("包清单为空");
        if (hashes.Count is 0 or > 256) throw new InvalidDataException("包清单数量无效");
        string id = Convert.ToHexString(SHA256.HashData(bytes.ToArray()));
        SafeFiles.PlainPath(parent); Directory.CreateDirectory(parent);
        Root = Path.Combine(parent, version + "-" + id);
        using var gate = new Mutex(false, "Local\\WiFiPayload-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(Root).ToUpperInvariant()))));
        bool owned;
        try { owned = gate.WaitOne(TimeSpan.FromSeconds(30)); } catch (AbandonedMutexException) { owned = true; }
        if (!owned) throw new TimeoutException("脚本缓存正在准备，请稍后重试");
        try
        {
            var clock = Stopwatch.StartNew();
            if (Directory.Exists(Root))
            {
                try { Verify(); Hit = true; VerifyMilliseconds = clock.Elapsed.TotalMilliseconds; return; }
                catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException)
                {
                    // Keep damaged files for diagnosis; never recursively delete unexpected paths or links.
                    SafeFiles.PlainPath(Root); Directory.Move(Root, Root + ".damaged-" + Guid.NewGuid().ToString("N"));
                }
            }
            VerifyMilliseconds = clock.Elapsed.TotalMilliseconds;
            clock.Restart(); bytes.Position = 0;
            using var stage = new Payload(zip, bytes, parent);
            stage.Verify(); Directory.Move(stage.Root, Root);
            ExtractMilliseconds = clock.Elapsed.TotalMilliseconds;
        }
        finally { gate.ReleaseMutex(); }
    }
    public void Verify()
    {
        SafeFiles.PlainPath(Root);
        // One safe traversal avoids repeating ancestor metadata IO for every hash.
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        CheckDirectory(Root, seen);
        if (seen.Count != hashes.Count) throw new InvalidDataException("缓存文件缺失");
    }
    private void CheckDirectory(string directory, HashSet<string> seen)
    {
        foreach (string p in Directory.EnumerateFileSystemEntries(directory))
        {
            var attributes = File.GetAttributes(p);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("缓存包含链接或联接点");
            if ((attributes & FileAttributes.Directory) != 0) CheckDirectory(p, seen);
            else
            {
                string relative = Path.GetRelativePath(Root, p).Replace('\\', '/');
                if (!seen.Add(relative) || !hashes.TryGetValue(relative, out var hash)) throw new InvalidDataException("缓存包含未知文件");
                if (!string.Equals(SafeFiles.Hash(p), hash, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("缓存脚本校验失败：" + relative);
            }
        }
    }
}
