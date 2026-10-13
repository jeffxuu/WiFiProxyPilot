using System.Text.Json.Nodes;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;

// The presentation layer never starts PowerShell, edits HKCU, or installs tasks itself.
internal sealed class ApplicationServices(AppController controller)
{
    internal Task<StatusView> ReadStatus(bool logs = false, bool errors = false) => Task.Run(() =>
    {
        // Technical engine lines remain verbatim and are explicitly identified as raw in the Logs page.
        // The surrounding UI and the absence-of-logs message are always localized.
        var status = StatusReader.Read(errors, raw: true, includeLogs: logs);
        if (logs && AppController.InstalledRoot() is string root && !File.Exists(Path.Combine(root, "logs", "watcher.jsonl")))
            status = status with { Logs = Localization.Text("NoWatcherLogs") };
        return status;
    });
    internal Task<ConfigurationDocument> ReadConfiguration() => Task.Run(() => AppController.InstalledRoot() is string root
        ? ConfigurationStore.Read(root) : UserPreferences.ReadDraft() ?? new ConfigurationDocument(ConfigurationStore.CreateDefault(), ""));
    internal Task<ConfigurationDocument> Save(ConfigurationDocument original, JsonObject draft) => Task.Run(() =>
    {
        ConfigurationStore.Validate(draft);
        return AppController.InstalledRoot() is string root ? ConfigurationStore.Save(root, original, draft)
            : UserPreferences.SaveDraft(draft);
    });
    internal Task<string> CurrentSsid() => Task.Run(() =>
    {
        try { return StatusReader.ConfirmedSsid(); }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
        { throw new UiOperationException("CurrentSsid", error.Message); }
    });
    internal Task<CommandResult> Execute(string command) => controller.Execute(new(command));
    internal async Task<CommandResult> Install(JsonObject draft)
    {
        await controller.WarmCache();
        string path = Path.Combine(AppController.ControlDir, "setup-" + Guid.NewGuid().ToString("N") + ".json");
        SafeFiles.PlainPath(path);
        var config = (JsonObject)draft.DeepClone(); config["SetupComplete"] = true; config["ManagementIntent"] = "Monitoring";
        ConfigurationStore.Validate(config);
        try { await File.WriteAllTextAsync(path, config.ToJsonString()); return await controller.Execute(new("install", SetupConfigPath: path)); }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
    internal Task<CommandResult> Upgrade() => controller.Execute(new("install"));
    internal Task<bool> Uninstall() => Task.Run(() => controller.BeginUninstall(new("uninstall")));
    internal Task WarmCache() => controller.WarmCache();
    internal Task RecordUiResult(string operation, string phase, string code = "") => Task.Run(() =>
    {
        CommandTrace.Write(operation, "WpfCommand." + phase, code);
    });
}
