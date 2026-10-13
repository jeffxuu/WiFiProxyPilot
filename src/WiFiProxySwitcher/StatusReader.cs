using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;
internal sealed record StatusView(bool Installed, string Ssid, string Interface, string Gateway, string Proxy, string Watcher, string Updated, string Logs,
    bool Running = false, bool Paused = false, bool Healthy = false, string Rule = "—", string Health = "尚未检测", string Revision = "", string Outcome = "", string Reason = "", bool ProxyEnabled = false, bool Connected = false);
internal static class StatusReader
{
    private static Dictionary<string, string> interfaces = new(StringComparer.OrdinalIgnoreCase);
    private static DateTime metadataTime;
    internal static StatusView Read(bool errorsOnly = false, bool raw = false)
    {
        var root = AppController.InstalledRoot();
        if (root == null) return new(false, "等待安装", "—", "—", "—", "—", "—", "请开启自动切换，完成当前用户安装。");
        string ssid = "未连接或暂不可识别", iface = "—", gateway = "—", updated = "—", outcome = "", reason = "", revision = "", health = "尚未检测";
        bool fresh = false, stable = false, connected = false;
        string heartbeatPath = Path.Combine(root, "state", "status.json");
        if (File.Exists(heartbeatPath))
        {
            using var heartbeat = new FileStream(heartbeatPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var doc = JsonDocument.Parse(heartbeat); var h = doc.RootElement;
            string Text(string k) => h.TryGetProperty(k, out var v) ? v.ToString() : "";
            outcome = Text("Outcome"); reason = Text("Reason"); revision = Text("ConfigRevision");
            string observed = Text("SSID"); connected = observed.Length > 0 && outcome is "Enable" or "Disable";
            if (observed.Length > 0) ssid = observed;
            gateway = Text("Gateway"); iface = Text("InterfaceGuid");
            int poll = int.TryParse(Text("PollSeconds"), out int n) ? n : 5;
            if (DateTimeOffset.TryParse(Text("Time"), out var time))
            { updated = time.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss"); var age = DateTimeOffset.Now - time; fresh = age.TotalSeconds >= -5 && age.TotalSeconds < Math.Max(30, poll * 2 + 15); }
            stable = Text("Stable").Equals("True", StringComparison.OrdinalIgnoreCase);
            double.TryParse(Text("HealthCheckedAt"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double checkedAt);
            double.TryParse(Text("ClockSeconds"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double clock);
            int interval = int.TryParse(Text("DiagnosticIntervalSeconds"), out int seconds) ? seconds : 60;
            bool probeFresh = fresh && clock - checkedAt >= 0 && clock - checkedAt <= interval + 15;
            health = !probeFresh ? "尚无近期诊断" : Text("Health") switch { "TcpOpen" => "TCP 可连接（未验证代理服务）", "HttpResponse" => "收到 HTTP 代理响应", "Unavailable" => "代理连通性检测失败", _ => "诊断结果未知" };
            if (Text("Diagnostics") == "None") health = "诊断已关闭";
        }
        bool running = IsWatcherRunning();
        bool paused = File.Exists(Path.Combine(root, "state", "pause.request")) || outcome == "Paused";
        if (paused)
        {
            // Pausing stops proxy management, not the UI's read-only ability to identify the current Wi-Fi.
            try { ssid = ConfirmedSsid(); connected = true; } catch (Exception e) { ssid = "当前 Wi-Fi 无法确认"; connected = false; reason += "；" + e.Message; }
            gateway = "—"; iface = "暂停管理，接口详情等待重新启用";
        }
        string proxy; bool enabled;
        if (AppController.TestRoot != null) { enabled = true; proxy = "已开启 · 10.0.0.1:7890 · 绕过本地地址（模拟）"; }
        else
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings");
            enabled = Convert.ToInt32(key?.GetValue("ProxyEnable", 0)) == 1;
            string server = key?.GetValue("ProxyServer", "") as string ?? "";
            string bypass = key?.GetValue("ProxyOverride", "") as string ?? "";
            proxy = enabled ? "已开启 · " + (server.Length > 0 ? server : "地址缺失") : "已关闭";
            if (bypass.Split(';').Any(p => p.Trim().Equals("<local>", StringComparison.OrdinalIgnoreCase))) proxy += " · 绕过本地地址";
            var actual = WiFiProxy.Native.ReadProxy();
            if (actual.Enable != enabled || enabled && actual.Server != server) { reason = "注册表与 WinINet 状态不一致"; outcome = "Retry"; }
            if ((actual.Flags & 12) != 0 || actual.Pac.Length > 0) reason += "；已保留 PAC/自动检测，实际选路可能由其决定";
        }
        if (DateTime.UtcNow - metadataTime > TimeSpan.FromMinutes(1) && AppController.TestRoot == null)
        {
            try { interfaces = NetworkInterface.GetAllNetworkInterfaces().ToDictionary(n => n.Id.Trim('{', '}'), n => n.Name, StringComparer.OrdinalIgnoreCase); metadataTime = DateTime.UtcNow; }
            catch (NetworkInformationException) { }
        }
        if (interfaces.TryGetValue(iface.Trim('{', '}'), out var name)) iface = name + " · " + iface;
        bool healthy = running && !paused && fresh && stable && outcome is "Enable" or "Disable" && enabled == (outcome == "Enable");
        string watcher = !running ? "监控未运行 · 请检查日志或开启自动切换" : paused ? "已暂停 · 保留当前手动代理" : !fresh ? "检测异常 · 心跳已过期" : outcome is "Retry" or "Keep" ? "检测异常 · 保留当前配置" : !stable ? "正在确认网络" : "自动切换正常";
        string rule = paused ? "已暂停 · 当前规则未应用" : !connected && outcome == "Disable" ? "无 Wi-Fi 连接" : outcome == "Disable" && reason.Contains("白名单") ? "免代理名单" : outcome == "Disable" && reason.Contains("Safe") ? "Safe 连通性保护" : connected ? "普通 Wi-Fi" : "网络尚未确认";
        return new(true, ssid, iface, gateway, proxy, watcher, updated, Logs(root, errorsOnly, raw), running, paused, healthy, rule, health, revision, outcome, reason, enabled, connected);
    }
    internal static bool IsWatcherRunning()
    {
        if (AppController.TestRoot != null) return true;
        try
        {
            using var m = Mutex.OpenExisting(@"Global\WiFiProxySwitcher." + SessionGuard.Sid + ".Watcher");
            bool taken; try { taken = m.WaitOne(0); } catch (AbandonedMutexException) { taken = true; }
            if (taken) m.ReleaseMutex(); return !taken;
        }
        catch (WaitHandleCannotBeOpenedException) { return false; }
    }
    internal static string ConfirmedSsid()
    {
        if (AppController.TestRoot != null) return "XiaoMi";
        using var native = new WiFiProxy.Native(); long generation = native.Generation;
        var first = native.ReadWifi(); var second = native.ReadWifi();
        if (first.Length != 1 || second.Length != 1 || !first[0].NameDecoded || !second[0].NameDecoded || first[0].Guid != second[0].Guid || first[0].SsidHex != second[0].SsidHex || native.Generation != generation)
            throw new InvalidOperationException("无法唯一确认当前真实 SSID，请检查连接和 Windows 位置权限，或手动输入。");
        return ConfigurationStore.ValidateSsid(second[0].SSID);
    }
    private static string Logs(string root, bool errorsOnly, bool raw)
    {
        string p = Path.Combine(root, "logs", "watcher.jsonl"); if (!File.Exists(p)) return "尚无监控日志";
        using var f = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        long start = Math.Max(0, f.Length - 65536); f.Position = start;
        using var reader = new StreamReader(f, Encoding.UTF8); var lines = reader.ReadToEnd().Split('\n');
        if (start > 0) lines = lines.Skip(1).ToArray();
        var output = new List<string>();
        foreach (string line in lines.Where(l => !string.IsNullOrWhiteSpace(l)).TakeLast(100))
        {
            try
            {
                using var d = JsonDocument.Parse(line.TrimStart('\uFEFF')); var h = d.RootElement;
                string Get(JsonElement e, string key) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) ? v.ToString() : "";
                string level = Get(h, "Level"); if (errorsOnly && level is not ("WARN" or "ERROR")) continue;
                if (raw) { output.Add(line); continue; }
                string time = DateTimeOffset.TryParse(Get(h, "Time"), out var t) ? t.ToLocalTime().ToString("MM-dd HH:mm:ss") : "时间未知";
                var data = h.TryGetProperty("Data", out var x) ? x : default;
                string details = string.Join(" · ", new[] { Get(data, "SSID"), Get(data, "Target"), Get(data, "Reason"), Get(data, "Error"), Get(data, "Health") }.Where(s => s.Length > 0));
                output.Add($"{time}  {level switch { "ERROR" => "错误", "WARN" => "警告", _ => "信息" }}  {Get(h, "Message")}" + (details.Length == 0 ? "" : Environment.NewLine + "    " + details));
            }
            catch (JsonException) { if (!errorsOnly) output.Add("日志记录不完整：" + line[..Math.Min(line.Length, 160)]); }
        }
        return string.Join(Environment.NewLine, output);
    }
}
