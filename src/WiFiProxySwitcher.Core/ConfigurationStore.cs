using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace WiFiProxySwitcher.Core;

public sealed record ConfigurationDocument(JsonObject Values, string Revision, bool NeedsMigration = false)
{
    public string[] Whitelist => Values["Whitelist"]!.AsArray().Select(v => v!.GetValue<string>()).ToArray();
    public bool Flag(string name, bool fallback) => Values[name]?.GetValue<bool>() ?? fallback;
    public int SchemaVersion => Values["SchemaVersion"]?.GetValue<int>() ?? 1;
    public ManagementIntent Intent => Enum.Parse<ManagementIntent>(Values["ManagementIntent"]?.GetValue<string>() ?? "Monitoring", false);
    public bool SetupComplete => Flag("SetupComplete", true);
}

public static class ConfigurationStore
{
    public const int CurrentSchemaVersion = 2;
    public static string ValidateSsid(string name)
    {
        // UTF-8 is also the native reader's lossless name representation. Preserve all spaces.
        if (name.Length == 0 || name.Any(char.IsControl) || new UTF8Encoding(false, true).GetByteCount(name) > 32)
            throw new InvalidDataException("Wi-Fi 名称应为 1–32 个 UTF-8 字节，不能含控制字符；空格会原样保留。");
        return name;
    }
    public static string[] Normalize(IEnumerable<string> names) => names.Select(ValidateSsid).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    public static string LockName(string path) => "Local\\WiFiConfig-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToUpperInvariant())));
    public static JsonObject CreateDefault() => new()
    {
        ["SchemaVersion"] = CurrentSchemaVersion, ["ManagementIntent"] = "Paused", ["SetupComplete"] = false,
        ["Whitelist"] = new JsonArray(), ["Port"] = 7890, ["Mode"] = "Strict", ["PollSeconds"] = 5,
        ["DebounceMilliseconds"] = 400, ["DisconnectConfirmSeconds"] = 2, ["RetrySeconds"] = 1,
        ["FastRetryWindowSeconds"] = 15, ["PreferredInterfaceGuid"] = "", ["Diagnostics"] = "Tcp",
        ["DiagnosticIntervalSeconds"] = 60, ["DiagnosticTimeoutMilliseconds"] = 1200, ["HttpProbeUrl"] = "",
        ["SafeFailureThreshold"] = 2, ["LogMaxBytes"] = 1048576, ["LogArchives"] = 3,
        ["LoginMonitor"] = true, ["TrayAutoStart"] = true, ["CloseToTray"] = true, ["MinimizeToTray"] = false
    };
    public static JsonObject Migrate(JsonObject source, bool legacyPaused = false)
    {
        Validate(source);
        var migrated = (JsonObject)source.DeepClone();
        migrated["SchemaVersion"] = CurrentSchemaVersion;
        if (!migrated.ContainsKey("ManagementIntent")) migrated["ManagementIntent"] = legacyPaused ? "Paused" : "Monitoring";
        if (!migrated.ContainsKey("SetupComplete")) migrated["SetupComplete"] = true;
        migrated["Whitelist"] = new JsonArray(Normalize(migrated["Whitelist"]!.AsArray().Select(v => v!.GetValue<string>())).Select(v => (JsonNode?)JsonValue.Create(v)).ToArray());
        return migrated;
    }
    public static ConfigurationDocument Read(string root)
    {
        string path = Path.Combine(root, "config.json"); SafeFiles.PlainPath(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (stream.Length > 1024 * 1024) throw new InvalidDataException("配置文件过大");
        using var bytes = new MemoryStream(); stream.CopyTo(bytes);
        string text = new UTF8Encoding(false, true).GetString(bytes.ToArray()).TrimStart('\uFEFF');
        using (var doc = JsonDocument.Parse(text)) RejectDuplicateProperties(doc.RootElement);
        var value = JsonNode.Parse(text) as JsonObject ?? throw new InvalidDataException("配置必须是 JSON 对象");
        Validate(value);
        var migrated = Migrate(value, File.Exists(Path.Combine(root, "state", "pause.request")));
        return new(migrated, Convert.ToHexString(SHA256.HashData(bytes.ToArray())), !JsonNode.DeepEquals(value, migrated));
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
        if (c.ContainsKey("SchemaVersion") && (c["SchemaVersion"] is not JsonValue schema || !schema.TryGetValue<int>(out int version) || version < 1))
            throw new InvalidDataException("配置 SchemaVersion 必须是正整数。");
        if (c["SchemaVersion"] is JsonValue knownSchema && knownSchema.GetValue<int>() > CurrentSchemaVersion)
            throw new ConfigurationUpgradeRequiredException(knownSchema.GetValue<int>());
        if (c.ContainsKey("ManagementIntent") && (c["ManagementIntent"] is not JsonValue intent || !intent.TryGetValue<string>(out string? intentName) || intentName is not ("Monitoring" or "Paused" or "Direct")))
            throw new InvalidDataException("自动管理意图无效，必须为 Monitoring、Paused 或 Direct。");
        if (c.ContainsKey("SetupComplete") && (c["SetupComplete"] is not JsonValue complete || !complete.TryGetValue<bool>(out _)))
            throw new InvalidDataException("首次配置状态必须是布尔值。");
        if (c["SchemaVersion"]?.GetValue<int>() == CurrentSchemaVersion && (!c.ContainsKey("ManagementIntent") || !c.ContainsKey("SetupComplete")))
            throw new InvalidDataException("新版配置缺少自动管理意图或首次配置状态。");
        if (c["SetupComplete"] is JsonValue setup && !setup.GetValue<bool>() && c["ManagementIntent"]?.GetValue<string>() != "Paused")
            throw new InvalidDataException("首次配置尚未确认，只能保持暂停。");
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
        draft = Migrate(draft);
        string path = Path.Combine(root, "config.json"); SafeFiles.PlainPath(path);
        using var gate = new Mutex(false, LockName(path));
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

public sealed class ConfigurationUpgradeRequiredException(int schemaVersion)
    : IOException($"配置版本 {schemaVersion} 高于此版本支持的 {ConfigurationStore.CurrentSchemaVersion}，请升级应用和后台组件。")
{
    public int SchemaVersion { get; } = schemaVersion;
}
