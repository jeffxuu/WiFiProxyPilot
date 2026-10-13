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
        int length;
        try { length = new UTF8Encoding(false, true).GetByteCount(name); }
        catch (EncoderFallbackException) { throw new ConfigurationValidationException("Ssid"); }
        if (name.Length == 0 || name.Any(char.IsControl) || length > 32)
            throw new ConfigurationValidationException("Ssid");
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
        ["Language"] = "System", ["Theme"] = "System", ["LoginMonitor"] = true, ["TrayAutoStart"] = true, ["CloseToTray"] = true, ["MinimizeToTray"] = false
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
        if (stream.Length > 1024 * 1024) throw new ConfigurationValidationException("ConfigTooLarge");
        using var bytes = new MemoryStream(); stream.CopyTo(bytes);
        string text = new UTF8Encoding(false, true).GetString(bytes.ToArray()).TrimStart('\uFEFF');
        using (var doc = JsonDocument.Parse(text)) RejectDuplicateProperties(doc.RootElement);
        var value = JsonNode.Parse(text) as JsonObject ?? throw new ConfigurationValidationException("ConfigObject");
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
            { if (!seen.Add(property.Name)) throw new ConfigurationValidationException("DuplicateField", property.Name); RejectDuplicateProperties(property.Value); }
        }
        else if (element.ValueKind == JsonValueKind.Array) foreach (var child in element.EnumerateArray()) RejectDuplicateProperties(child);
    }
    public static void Validate(JsonObject c)
    {
        if (c.ContainsKey("SchemaVersion") && (c["SchemaVersion"] is not JsonValue schema || !schema.TryGetValue<int>(out int version) || version < 1))
            throw new ConfigurationValidationException("SchemaVersion");
        if (c["SchemaVersion"] is JsonValue knownSchema && knownSchema.GetValue<int>() > CurrentSchemaVersion)
            throw new ConfigurationUpgradeRequiredException(knownSchema.GetValue<int>());
        if (c.ContainsKey("ManagementIntent") && (c["ManagementIntent"] is not JsonValue intent || !intent.TryGetValue<string>(out string? intentName) || intentName is not ("Monitoring" or "Paused" or "Direct")))
            throw new ConfigurationValidationException("ManagementIntent");
        if (c.ContainsKey("SetupComplete") && (c["SetupComplete"] is not JsonValue complete || !complete.TryGetValue<bool>(out _)))
            throw new ConfigurationValidationException("SetupComplete");
        if (c["SchemaVersion"]?.GetValue<int>() == CurrentSchemaVersion && (!c.ContainsKey("ManagementIntent") || !c.ContainsKey("SetupComplete")))
            throw new ConfigurationValidationException("MissingSetupFields");
        if (c["SetupComplete"] is JsonValue setup && !setup.GetValue<bool>() && c["ManagementIntent"]?.GetValue<string>() != "Paused")
            throw new ConfigurationValidationException("UnconfirmedSetup");
        foreach (var rule in new (string Name, int Min, int Max)[] { ("Port",1,65535),("PollSeconds",1,300),("DebounceMilliseconds",100,5000),("DisconnectConfirmSeconds",1,30),("RetrySeconds",1,30),("FastRetryWindowSeconds",1,60),("DiagnosticIntervalSeconds",5,3600),("DiagnosticTimeoutMilliseconds",100,5000),("SafeFailureThreshold",1,10),("LogMaxBytes",16384,10485760),("LogArchives",1,10) })
        {
            if (c[rule.Name] is not JsonValue v || !v.TryGetValue<int>(out int number) || number < rule.Min || number > rule.Max)
                throw new ConfigurationValidationException("Range", rule.Name);
        }
        string mode = c["Mode"]?.GetValue<string>() ?? "", diagnostics = c["Diagnostics"]?.GetValue<string>() ?? "";
        if (mode is not ("Strict" or "Safe") || diagnostics is not ("None" or "Tcp" or "Http") || mode == "Safe" && diagnostics == "None")
            throw new ConfigurationValidationException("DiagnosticMode");
        if (c["Whitelist"] is not JsonArray list) throw new ConfigurationValidationException("Whitelist");
        foreach (var item in list) ValidateSsid(item?.GetValue<string>() ?? "");
        string guid = c["PreferredInterfaceGuid"]?.GetValue<string>() ?? throw new ConfigurationValidationException("MissingInterface");
        if (guid.Length > 0 && !Guid.TryParse(guid, out _)) throw new ConfigurationValidationException("InterfaceGuid");
        string url = c["HttpProbeUrl"]?.GetValue<string>() ?? throw new ConfigurationValidationException("MissingProbeUrl");
        if (diagnostics == "Http" && (!Uri.TryCreate(url, UriKind.Absolute, out var u) || u.Scheme != "http" || u.UserInfo.Length > 0 || u.Query.Length > 0 || u.Fragment.Length > 0))
            throw new ConfigurationValidationException("ProbeUrl");
        if (c["Language"] is JsonNode language && (language is not JsonValue languageValue || !languageValue.TryGetValue<string>(out string? languageName) || languageName is not ("System" or "zh-CN" or "en-US"))) throw new ConfigurationValidationException("Language");
        if (c["Theme"] is JsonNode theme && (theme is not JsonValue themeValue || !themeValue.TryGetValue<string>(out string? themeName) || themeName is not ("System" or "Light" or "Dark"))) throw new ConfigurationValidationException("Theme");
        foreach (string flag in new[] { "LoginMonitor", "TrayAutoStart", "CloseToTray", "MinimizeToTray" })
            if (c[flag] is JsonNode node && (node is not JsonValue value || !value.TryGetValue<bool>(out _))) throw new ConfigurationValidationException("Boolean", flag);
    }
    public static ConfigurationDocument Save(string root, ConfigurationDocument original, JsonObject draft)
    {
        Validate(draft);
        draft = Migrate(draft);
        string path = Path.Combine(root, "config.json"); SafeFiles.PlainPath(path);
        using var gate = new Mutex(false, LockName(path));
        bool owned; try { owned = gate.WaitOne(TimeSpan.FromSeconds(10)); } catch (AbandonedMutexException) { owned = true; }
        if (!owned) throw new ConfigurationValidationException("SaveBusy");
        string stage = path + ".tmp." + Guid.NewGuid().ToString("N");
        try
        {
            if (Read(root).Revision != original.Revision) throw new ConfigurationValidationException("ConfigChanged");
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

public sealed class ConfigurationValidationException(string code, string field = "") : IOException(code + (field.Length > 0 ? ": " + field : ""))
{
    public string Code { get; } = code;
    public string Field { get; } = field;
}
