using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Resources;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Data;
using System.Windows.Markup;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;

// Strings are keyed by stable application facts, never translated from engine log prose.
internal sealed class Localization : INotifyPropertyChanged
{
    private static readonly CultureInfo windowsUiCulture = CultureInfo.CurrentUICulture;
    private readonly ResourceManager resources = new("WiFiProxySwitcher.Resources.Strings", typeof(Localization).Assembly);
    internal static Localization Current { get; } = new();
    private CultureInfo culture = CultureInfo.GetCultureInfo("en-US");
    public event PropertyChangedEventHandler? PropertyChanged;
    internal event Action? LanguageChanged;
    internal string Language { get; private set; } = "System";
    internal CultureInfo Culture => culture;
    public string this[string key] => resources.GetString(key, culture) ?? resources.GetString("ResourceUnavailable", CultureInfo.GetCultureInfo("en-US")) ?? "Text unavailable";
    private Localization() { SetLanguage(UserPreferences.Language, persist: false); }
    internal static string Text(string key) => Current[key];
    internal static string Format(string key, params object?[] values) => string.Format(Current.culture, Text(key), values);
    private static string ErrorCode(string code) => Current.resources.GetString("Error" + code, Current.culture) ?? Text("ErrorOperationFailed");
    // Traditional Chinese is deliberately mapped to Simplified Chinese for the first bilingual release.
    internal static string ResolveCulture(string preference, CultureInfo system) => preference switch
    {
        "zh-CN" => "zh-CN", "en-US" => "en-US", _ => system.TwoLetterISOLanguageName == "zh" ? "zh-CN" : "en-US"
    };
    internal void SetLanguage(string preference, bool persist = true)
    {
        if (preference is not ("System" or "zh-CN" or "en-US")) preference = "System";
        if (persist) UserPreferences.SaveLanguage(preference);
        Language = preference;
        culture = CultureInfo.GetCultureInfo(ResolveCulture(preference, windowsUiCulture));
        CultureInfo.CurrentUICulture = culture; CultureInfo.CurrentCulture = culture;
        CultureInfo.DefaultThreadCurrentUICulture = culture; CultureInfo.DefaultThreadCurrentCulture = culture;
        PropertyChanged?.Invoke(this, new("Item[]")); LanguageChanged?.Invoke();
    }
    internal static string Error(Exception error) => error switch
    {
        UiOperationException coded => Format("OperationCode", ErrorCode(coded.Code), coded.Code),
        ConfigurationValidationException validation => Format("ValidationField", ErrorCode(validation.Code), validation.Field),
        ConfigurationUpgradeRequiredException => Text("ErrorUpgradeRequired"),
        TimeoutException => Text("ErrorTimeout"),
        UnauthorizedAccessException => Text("ErrorPermission"),
        _ => Text("ErrorUnexpected")
    };
}

// Markup extension keeps cached pages and accessible names live when language changes.
[MarkupExtensionReturnType(typeof(object))]
public sealed class LocExtension : MarkupExtension
{
    public string Key { get; set; }
    public LocExtension(string key) { Key = key; }
    public override object ProvideValue(IServiceProvider serviceProvider) => new Binding("[" + Key + "]")
        { Source = Localization.Current, Mode = BindingMode.OneWay }.ProvideValue(serviceProvider);
}

internal sealed class UiOperationException(string code, string detail = "") : IOException(detail)
{
    internal string Code { get; } = code;
}

// UI preference and unconfirmed setup drafts persist independently from installation ownership.
internal static class UserPreferences
{
    private static string PathFor(string name) => Path.Combine(AppController.ControlDir, name);
    internal static string Language
    {
        get
        {
            try
            {
                string path = PathFor("preferences.json"); SafeFiles.PlainPath(path);
                if (!File.Exists(path)) return "System";
                using var stream = File.OpenRead(path); if (stream.Length > 8192) return "System";
                using var value = JsonDocument.Parse(stream);
                return value.RootElement.TryGetProperty("Language", out var language) && language.GetString() is "zh-CN" or "en-US" ? language.GetString()! : "System";
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException) { StartupMetrics.Value("PreferencesReadError", e.Message); return "System"; }
        }
    }
    internal static void SaveLanguage(string language) => Write("preferences.json", new JsonObject { ["Language"] = language });
    internal static ConfigurationDocument? ReadDraft()
    {
        string path = PathFor("draft-config.json"); SafeFiles.PlainPath(path); if (!File.Exists(path)) return null;
        using var stream = File.OpenRead(path); if (stream.Length > 1024 * 1024) throw new ConfigurationValidationException("ConfigTooLarge");
        var draft = JsonNode.Parse(stream) as JsonObject ?? throw new ConfigurationValidationException("ConfigObject");
        ConfigurationStore.Validate(draft); return new(ConfigurationStore.Migrate(draft), "");
    }
    internal static ConfigurationDocument SaveDraft(JsonObject draft)
    {
        var config = ConfigurationStore.Migrate(draft); Write("draft-config.json", config); return new(config, "");
    }
    private static void Write(string name, JsonObject value)
    {
        SafeFiles.PlainPath(AppController.ControlDir); Directory.CreateDirectory(AppController.ControlDir);
        string path = PathFor(name), stage = path + ".tmp." + Guid.NewGuid().ToString("N"); SafeFiles.PlainPath(path); SafeFiles.PlainPath(stage);
        using var gate = new Mutex(false, ConfigurationStore.LockName(path));
        bool owned; try { owned = gate.WaitOne(TimeSpan.FromSeconds(10)); } catch (AbandonedMutexException) { owned = true; }
        if (!owned) throw new TimeoutException();
        try
        {
            using (var stream = new FileStream(stage, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { byte[] bytes = System.Text.Encoding.UTF8.GetBytes(value.ToJsonString(new JsonSerializerOptions { WriteIndented = true })); stream.Write(bytes); stream.Flush(true); }
            if (File.Exists(path)) File.Replace(stage, path, null); else File.Move(stage, path);
        }
        finally { if (File.Exists(stage)) File.Delete(stage); gate.ReleaseMutex(); }
    }
}
