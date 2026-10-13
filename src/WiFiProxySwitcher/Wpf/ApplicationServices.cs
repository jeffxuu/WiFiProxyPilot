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
        if (logs)
        {
            string watcher = status.Logs.Length > 0 ? status.Logs : Localization.Text("NoWatcherLogs");
            try { if (AppController.InstalledRoot() is not string root || !File.Exists(Path.Combine(root, "logs", "watcher.jsonl"))) watcher = Localization.Text("NoWatcherLogs"); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { watcher = Localization.Text("LogReadFailed"); }
            string commands = ReadTechnicalTail("commands.jsonl", errors), control = ReadTechnicalTail("control-errors.log"), desktop = ReadTechnicalTail("desktop-errors.log");
            status = status with { Logs = Localization.Text("WatcherLogHeading") + Environment.NewLine + watcher + Environment.NewLine + Environment.NewLine +
                Localization.Text("CommandLogHeading") + Environment.NewLine + (commands.Length > 0 ? commands : Localization.Text("NoCommandLogs")) + Environment.NewLine + Environment.NewLine +
                Localization.Text("ControlErrorHeading") + Environment.NewLine + (control.Length > 0 ? control : Localization.Text("NoControlErrors")) + Environment.NewLine + Environment.NewLine +
                Localization.Text("DesktopErrorHeading") + Environment.NewLine + (desktop.Length > 0 ? desktop : Localization.Text("NoDesktopErrors")) };
        }
        return status;
    });
    private static string ReadTechnicalTail(string name, bool failedCommandsOnly = false)
    {
        try
        {
            string path = Path.Combine(AppController.ControlDir, name); SafeFiles.PlainPath(path);
            if (!File.Exists(path)) return "";
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            long start = Math.Max(0, file.Length - 16384); file.Position = start;
            using var reader = new StreamReader(file, System.Text.Encoding.UTF8); var lines = reader.ReadToEnd().Split('\n').AsEnumerable();
            if (start > 0) lines = lines.Skip(1);
            if (failedCommandsOnly) lines = lines.Where(line =>
            {
                try { using var value = System.Text.Json.JsonDocument.Parse(line); string stage = value.RootElement.TryGetProperty("Stage", out var property) ? property.GetString() ?? "" : ""; return stage is "Failed" or "Exception" or "WpfCommand.Failed"; }
                catch (System.Text.Json.JsonException) { return false; }
            });
            return string.Join(Environment.NewLine, lines.Where(line => !string.IsNullOrWhiteSpace(line)).TakeLast(100));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { return Localization.Text("LogReadFailed"); }
    }
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
    internal Task RecordUiError(string operation, Exception error) => Task.Run(() =>
    {
        try
        {
            SafeFiles.PlainPath(AppController.ControlDir); Directory.CreateDirectory(AppController.ControlDir);
            string path = Path.Combine(AppController.ControlDir, "desktop-errors.log"); SafeFiles.PlainPath(path);
            if (File.Exists(path) && new FileInfo(path).Length > 262144) { SafeFiles.PlainPath(path + ".1"); File.Move(path, path + ".1", true); }
            File.AppendAllText(path, DateTimeOffset.Now.ToString("o") + " " + operation + " " + error + Environment.NewLine, System.Text.Encoding.UTF8);
        }
        catch (Exception logError) when (logError is IOException or UnauthorizedAccessException) { System.Diagnostics.Trace.WriteLine("UI error log unavailable: " + logError.GetType().Name); }
    });
}
