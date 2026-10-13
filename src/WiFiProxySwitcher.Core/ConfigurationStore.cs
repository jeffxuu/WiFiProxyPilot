using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace WiFiProxySwitcher.Core;

public sealed record ConfigurationDocument(JsonObject Values, string Revision)
{
    public string[] Whitelist => Values["Whitelist"]!.AsArray().Select(v => v!.GetValue<string>()).ToArray();
    public bool Flag(string name, bool fallback) => Values[name]?.GetValue<bool>() ?? fallback;
}

public static class ConfigurationStore
{
    public static readonly string[] BuiltIns = ["MC-Office", "Meituan"];
    public static string ValidateSsid(string name)
    {
        // UTF-8 is also the native reader's lossless name representation. Preserve all spaces.
        if (name.Length == 0 || name.Any(char.IsControl) || new UTF8Encoding(false, true).GetByteCount(name) > 32)
            throw new InvalidDataException("Wi-Fi 名称应为 1–32 个 UTF-8 字节，不能含控制字符；空格会原样保留。");
        return name;
    }
    public static string[] Normalize(IEnumerable<string> names) => BuiltIns.Concat(names.Select(ValidateSsid)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    public static ConfigurationDocument Read(string root)
    {
        string path = Path.Combine(root, "config.json"); SafeFiles.PlainPath(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (stream.Length > 1024 * 1024) throw new InvalidDataException("配置文件过大");
        using var bytes = new MemoryStream(); stream.CopyTo(bytes);
        string text = Encoding.UTF8.GetString(bytes.ToArray()).TrimStart('\uFEFF');
        using (var doc = JsonDocument.Parse(text)) RejectDuplicateProperties(doc.RootElement);
        var value = JsonNode.Parse(text) as JsonObject ?? throw new InvalidDataException("配置必须是 JSON 对象");
        Validate(value);
        return new(value, Convert.ToHexString(SHA256.HashData(bytes.ToArray())));
    }
    private static void RejectDuplicateProperties(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in element.EnumerateObject())
            { if (!seen.Add(property.Name)) throw new InvalidDataException("配置字段重复：" + property.Name); RejectDuplicateProperties(property.Value); }
        }
        else if (element.ValueKind == JsonValueKind.Array) foreach (var child in element.EnumerateArray()) RejectDuplicateProperties(child);
    }
    public static void Validate(JsonObject c)
    {
        foreach (var rule in new (string Name, int Min, int Max)[] { ("Port",1,65535),("PollSeconds",1,300),("DebounceMilliseconds",100,5000),("DisconnectConfirmSeconds",1,30),("RetrySeconds",1,30),("FastRetryWindowSeconds",1,60),("DiagnosticIntervalSeconds",5,3600),("DiagnosticTimeoutMilliseconds",100,5000),("SafeFailureThreshold",1,10),("LogMaxBytes",16384,10485760),("LogArchives",1,10) })
        {
            if (c[rule.Name] is not JsonValue v || !v.TryGetValue<int>(out int number) || number < rule.Min || number > rule.Max)
                throw new InvalidDataException("配置范围错误：" + rule.Name);
        }
        string mode = c["Mode"]?.GetValue<string>() ?? "", diagnostics = c["Diagnostics"]?.GetValue<string>() ?? "";
        if (mode is not ("Strict" or "Safe") || diagnostics is not ("None" or "Tcp" or "Http") || mode == "Safe" && diagnostics == "None")
            throw new InvalidDataException("Safe 模式必须启用诊断，模式或诊断值无效。");
        if (c["Whitelist"] is not JsonArray list) throw new InvalidDataException("免代理名单必须是数组");
        foreach (var item in list) ValidateSsid(item?.GetValue<string>() ?? "");
        string guid = c["PreferredInterfaceGuid"]?.GetValue<string>() ?? throw new InvalidDataException("缺少接口字段");
        if (guid.Length > 0 && !Guid.TryParse(guid, out _)) throw new InvalidDataException("接口 GUID 无效");
        string url = c["HttpProbeUrl"]?.GetValue<string>() ?? throw new InvalidDataException("缺少 HTTP 诊断 URL");
        if (diagnostics == "Http" && (!Uri.TryCreate(url, UriKind.Absolute, out var u) || u.Scheme != "http" || u.UserInfo.Length > 0 || u.Query.Length > 0 || u.Fragment.Length > 0))
            throw new InvalidDataException("HTTP 诊断需填写不含凭据、查询和片段的 http URL。");
        foreach (string flag in new[] { "LoginMonitor", "TrayAutoStart", "CloseToTray", "MinimizeToTray" })
            if (c[flag] is JsonNode node && (node is not JsonValue value || !value.TryGetValue<bool>(out _))) throw new InvalidDataException("设置必须是布尔值：" + flag);
    }
    public static ConfigurationDocument Save(string root, ConfigurationDocument original, JsonObject draft)
    {
        Validate(draft);
        draft = (JsonObject)draft.DeepClone();
        draft["Whitelist"] = new JsonArray(Normalize(draft["Whitelist"]!.AsArray().Select(v => v!.GetValue<string>())).Select(v => (JsonNode?)JsonValue.Create(v)).ToArray());
        string path = Path.Combine(root, "config.json"); SafeFiles.PlainPath(path);
        using var gate = new Mutex(false, "Local\\WiFiConfig-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToUpperInvariant()))));
        bool owned; try { owned = gate.WaitOne(TimeSpan.FromSeconds(10)); } catch (AbandonedMutexException) { owned = true; }
        if (!owned) throw new TimeoutException("其他窗口正在保存配置");
        string stage = path + ".tmp." + Guid.NewGuid().ToString("N");
        try
        {
            if (Read(root).Revision != original.Revision) throw new IOException("配置已被其他程序修改，请重新载入后再保存。");
            byte[] bytes = Encoding.UTF8.GetBytes(draft.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            using (var stream = new FileStream(stage, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough)) { stream.Write(bytes); stream.Flush(true); }
            string backup = path + ".previous"; SafeFiles.PlainPath(backup);
            File.Replace(stage, path, backup);
            return new(draft, Convert.ToHexString(SHA256.HashData(bytes)));
        }
        finally { if (File.Exists(stage)) File.Delete(stage); gate.ReleaseMutex(); }
    }
}
