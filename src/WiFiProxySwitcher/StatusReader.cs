using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

namespace WiFiProxySwitcher;
internal sealed record StatusView(bool Installed, string Ssid, string Interface, string Gateway, string Proxy, string Watcher, string Updated, string Logs);
internal static class StatusReader
{
    internal static StatusView Read()
    {
        var root = AppController.InstalledRoot();
        if (root == null) return new(false, "等待安装", "—", "—", "—", "尚未安装", "—", "首次运行将完成当前用户安装。");
        string ssid = "尚无检测结果", iface = "—", gateway = "—", updated = "—";
        string heartbeatPath = Path.Combine(root, "state", "status.json");
        if (File.Exists(heartbeatPath))
        {
            // Do not block the engine's atomic File.Replace while the window reads a heartbeat.
            using var heartbeat = new FileStream(heartbeatPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var doc = JsonDocument.Parse(heartbeat); var h = doc.RootElement;
            string Text(string k) => h.TryGetProperty(k, out var v) ? v.ToString() : "";
            ssid = Text("SSID"); if (ssid.Length == 0) ssid = "未连接或暂不可识别";
            gateway = Text("Gateway"); iface = Text("InterfaceGuid"); updated = Text("Time");
            try { var nic = NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n => string.Equals(n.Id.Trim('{', '}'), iface.Trim('{', '}'), StringComparison.OrdinalIgnoreCase)); if (nic != null) iface = nic.Name + " · " + iface; }
            catch (NetworkInformationException) { }
        }
        bool running = false;
        try
        {
            using var m = Mutex.OpenExisting(@"Global\WiFiProxySwitcher." + SessionGuard.Sid + ".Watcher");
            bool taken; try { taken = m.WaitOne(0); } catch (AbandonedMutexException) { taken = true; }
            if (taken) m.ReleaseMutex(); running = !taken;
        }
        catch (WaitHandleCannotBeOpenedException) { }
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings");
        bool enabled = Convert.ToInt32(key?.GetValue("ProxyEnable", 0)) == 1;
        string server = key?.GetValue("ProxyServer", "") as string ?? "";
        if (!System.Text.RegularExpressions.Regex.IsMatch(server, @"^(\d{1,3}\.){3}\d{1,3}:\d{1,5}$")) server = "已有地址（未展示）";
        string bypass = key?.GetValue("ProxyOverride", "") as string ?? "";
        string proxy = enabled ? "已开启 · " + server : "已关闭";
        if (bypass.Split(';').Any(p => p.Trim().Equals("<local>", StringComparison.OrdinalIgnoreCase))) proxy += " · 绕过本地地址";
        return new(true, ssid, iface, gateway, proxy, running ? "正在运行" : "已停止 · 网络信息为上次检测", updated, Logs(root));
    }
    private static string Logs(string root)
    {
        string p = Path.Combine(root, "logs", "watcher.jsonl"); if (!File.Exists(p)) return "尚无监控日志";
        using var f = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        long start = Math.Max(0, f.Length - 32768); f.Position = start;
        using var reader = new StreamReader(f, Encoding.UTF8); string content = reader.ReadToEnd();
        var lines = content.Split('\n'); if (start > 0) lines = lines.Skip(1).ToArray();
        return string.Join(Environment.NewLine, lines.TakeLast(40));
    }
}
