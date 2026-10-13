using System.Text.Json.Nodes;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;

// The presentation layer never starts PowerShell, edits HKCU, or installs tasks itself.
internal sealed class ApplicationServices(AppController controller)
{
    internal Task<StatusView> ReadStatus(bool logs = false, bool errors = false) => Task.Run(() => StatusReader.Read(errors, false, logs));
    internal Task<ConfigurationDocument> ReadConfiguration() => Task.Run(() => AppController.InstalledRoot() is string root
        ? ConfigurationStore.Read(root) : new ConfigurationDocument(ConfigurationStore.CreateDefault(), ""));
    internal Task<ConfigurationDocument> Save(ConfigurationDocument original, JsonObject draft) => Task.Run(() =>
    {
        ConfigurationStore.Validate(draft);
        return AppController.InstalledRoot() is string root ? ConfigurationStore.Save(root, original, draft)
            : new ConfigurationDocument(ConfigurationStore.Migrate(draft), "");
    });
    internal Task<string> CurrentSsid() => Task.Run(StatusReader.ConfirmedSsid);
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
    internal Task Upgrade() => controller.Execute(new("install"));
    internal Task Uninstall() => Task.Run(() => controller.BeginUninstall(new("uninstall")));
    internal Task WarmCache() => controller.WarmCache();
}
