using System.Globalization;
using System.IO;
using System.Resources;
using System.Text.Json;
using System.Xml.Linq;
using WiFiProxySwitcher;
using WiFiProxySwitcher.Core;

string fixture = Path.Combine(Path.GetTempPath(), "WiFiPilot-Localization-" + Guid.NewGuid().ToString("N"));
AppController.ControlDir = fixture;
int failed = 0;
var results = new List<object>();
void Assert(bool value) { if (!value) throw new InvalidOperationException("Localization assertion failed."); }
void Test(string name, Action test)
{
    try { test(); results.Add(new { Name = name, Passed = true }); Console.WriteLine("PASS " + name); }
    catch (Exception error) { failed++; results.Add(new { Name = name, Passed = false, Error = error.ToString() }); Console.WriteLine("FAIL " + name + ": " + error.Message); }
}
Test("CurrentUICulture selects supported Windows display language; explicit Traditional Chinese policy", () =>
{
    Assert(Localization.ResolveCulture("System", CultureInfo.GetCultureInfo("en-GB")) == "en-US");
    Assert(Localization.ResolveCulture("System", CultureInfo.GetCultureInfo("zh-CN")) == "zh-CN");
    Assert(Localization.ResolveCulture("System", CultureInfo.GetCultureInfo("zh-TW")) == "zh-CN");
    Assert(Localization.ResolveCulture("System", CultureInfo.GetCultureInfo("zh-HK")) == "zh-CN");
    Assert(Localization.ResolveCulture("System", CultureInfo.GetCultureInfo("fr-FR")) == "en-US");
    Assert(Localization.ResolveCulture("en-US", CultureInfo.GetCultureInfo("zh-CN")) == "en-US");
});
Test("ResourceManager loads complete matching English and Chinese satellite resources", () =>
{
    var resources = new ResourceManager("WiFiProxySwitcher.Resources.Strings", typeof(Localization).Assembly);
    var english = resources.GetResourceSet(CultureInfo.GetCultureInfo("en-US"), true, false)!;
    var chinese = resources.GetResourceSet(CultureInfo.GetCultureInfo("zh-CN"), true, false)!;
    var en = english.Cast<System.Collections.DictionaryEntry>().ToDictionary(x => (string)x.Key, x => (string)x.Value!);
    var zh = chinese.Cast<System.Collections.DictionaryEntry>().ToDictionary(x => (string)x.Key, x => (string)x.Value!);
    Assert(en.Count >= 272 && en.Keys.ToHashSet().SetEquals(zh.Keys));
    Assert(en.Values.All(s => !string.IsNullOrWhiteSpace(s)) && zh.Values.All(s => !string.IsNullOrWhiteSpace(s)));
    foreach (string key in en.Keys)
    {
        var enArgs = System.Text.RegularExpressions.Regex.Matches(en[key], @"\{\d+\}").Select(x => x.Value).ToHashSet();
        var zhArgs = System.Text.RegularExpressions.Regex.Matches(zh[key], @"\{\d+\}").Select(x => x.Value).ToHashSet();
        Assert(enArgs.SetEquals(zhArgs));
    }
});
Test("Runtime language refreshes indexer binding and culture without leaking resource keys", () =>
{
    bool bindingRefreshed = false, viewModelsRefreshed = false;
    Localization.Current.PropertyChanged += (_, e) => bindingRefreshed |= e.PropertyName == "Item[]";
    Localization.Current.LanguageChanged += () => viewModelsRefreshed = true;
    Localization.Current.SetLanguage("en-US"); Assert(Localization.Text("NavSettings") == "Settings");
    Localization.Current.SetLanguage("zh-CN"); Assert(Localization.Text("NavSettings") == "设置");
    Assert(bindingRefreshed && viewModelsRefreshed && CultureInfo.CurrentUICulture.Name == "zh-CN");
    Assert(Localization.Text("MissingResourceForTest") != "MissingResourceForTest");
});
Test("Language preference persists before watcher installation", () =>
{
    Localization.Current.SetLanguage("en-US"); Assert(UserPreferences.Language == "en-US");
    Localization.Current.SetLanguage("System"); Assert(UserPreferences.Language == "System");
    Assert(!File.Exists(Path.Combine(fixture, "state", "installation.json")));
});
Test("Unconfirmed setup draft persists without enabling proxy management", () =>
{
    var config = ConfigurationStore.CreateDefault(); config["Port"] = 7891;
    config["Whitelist"] = new System.Text.Json.Nodes.JsonArray("测试 Wi-Fi", " Home ");
    UserPreferences.SaveDraft(config); var readback = UserPreferences.ReadDraft()!;
    Assert(readback.Values["Port"]!.GetValue<int>() == 7891 && readback.Whitelist.SequenceEqual(new[] { "测试 Wi-Fi", " Home " }));
    Assert(readback.Intent == ManagementIntent.Paused && !readback.SetupComplete);
});
Test("Localized stable error codes exclude raw engine Chinese and retain unknown error code", () =>
{
    Localization.Current.SetLanguage("en-US");
    Assert(Localization.Error(new ConfigurationValidationException("Port")).Contains("port", StringComparison.OrdinalIgnoreCase));
    string fallback = Localization.Error(new UiOperationException("NovelEngineFailure", "原始中文诊断"));
    Assert(fallback.Contains("NovelEngineFailure") && !fallback.Contains("原始中文") && !fallback.Contains("Text unavailable"));
});
Test("Invalid language/theme are rejected by stable validation codes", () =>
{
    foreach (string field in new[] { "Language", "Theme" })
    {
        var config = ConfigurationStore.CreateDefault(); config[field] = "Invalid";
        bool rejected = false; try { ConfigurationStore.Validate(config); } catch (ConfigurationValidationException error) { rejected = error.Code == field; }
        Assert(rejected);
    }
});
if (args.Length > 0) File.WriteAllText(Path.GetFullPath(args[0]), JsonSerializer.Serialize(new { Total = results.Count, Failed = failed, Results = results, Boundary = "ResourceManager and owned temp files only; UI interactions verified by Desktop.Automation" }, new JsonSerializerOptions { WriteIndented = true }));
// Remove only files made by these tests; no recursive application-directory deletion.
foreach (string name in new[] { "preferences.json", "draft-config.json" }) { string path = Path.Combine(fixture, name); if (File.Exists(path)) File.Delete(path); }
if (Directory.Exists(fixture) && !Directory.EnumerateFileSystemEntries(fixture).Any()) Directory.Delete(fixture);
return failed == 0 ? 0 : 1;
