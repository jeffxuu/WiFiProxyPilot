using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;
internal sealed record StatusView(bool Installed, string Ssid, string Interface, string Gateway, string Proxy, string Watcher, string Updated, string Logs,
    bool Running = false, bool Paused = false, bool Healthy = false, string Rule = "—", string Health = "尚未检测", string Revision = "", string Outcome = "", string Reason = "", bool ProxyEnabled = false, bool Connected = false,
    ApplicationState State = ApplicationState.NotInstalled, string EngineVersion = "未知", bool Fresh = false, string ManualServer = "", string ConfigRevision = "", string AppliedRevision = "", bool SetupComplete = false,
    ManagementIntent Intent = ManagementIntent.Paused, NetworkStatus? Network = null, ProxyDiagnosticStatus? Diagnostic = null, int EngineSchemaVersion = 0, string CheckRequestId = "");

internal static class StatusReader
{
    private static Dictionary<string, string> interfaces = new(StringComparer.OrdinalIgnoreCase);
    private static DateTime metadataTime;
    private static bool? hasWirelessAdapter;
    private static StatusView? lastSuccess;

    // Caller schedules this read on a worker thread. Routine refreshes do not parse logs.
    internal static StatusView Read(bool errorsOnly = false, bool raw = false, bool includeLogs = false)
    {
        try
        {
            var status = ReadCore(errorsOnly, raw, includeLogs);
            Volatile.Write(ref lastSuccess, status);
            return status;
        }
        catch (Exception e) when (e is IOException or JsonException or InvalidOperationException or UnauthorizedAccessException or ArgumentException or FormatException or System.ComponentModel.Win32Exception or System.Security.SecurityException)
        {
            var previous = Volatile.Read(ref lastSuccess);
            var state = e is ConfigurationUpgradeRequiredException ? ApplicationState.UpgradeRequired : ApplicationState.Degraded;
            string reason = "暂时无法读取：" + e.Message;
            if (previous != null)
                return previous with { Ssid = "暂时无法读取", Gateway = "暂时无法读取", Proxy = "暂时无法读取", Watcher = state == ApplicationState.UpgradeRequired ? "需要升级应用和后台组件" : "暂时无法读取", State = state, Fresh = false, Connected = false, Healthy = false,
                    Reason = reason + "；上次成功读取：" + previous.Updated, Network = new(NetworkConnectionState.Unknown, ObservedAt: previous.Network?.ObservedAt, Reason: reason), Diagnostic = new(ProxyDiagnosticState.Unknown, Reason: reason) };
            return new(true, "暂时无法读取", "—", "暂时无法读取", "暂时无法读取", "暂时无法读取", "尚无成功检测", "", State: state, Reason: reason);
        }
    }

    private static StatusView ReadCore(bool errorsOnly, bool raw, bool includeLogs)
    {
        var root = AppController.InstalledRoot();
        if (root == null) return new(false, "尚未开始", "—", "—", "等待配置", "未配置", "—", "", State: ApplicationState.NotInstalled, Reason: "根据 Wi-Fi 自动切换 Windows 手动代理；完成首次设置并确认后才会改变代理。", Network: new(NetworkConnectionState.Unknown), Diagnostic: new(ProxyDiagnosticState.Unknown));
        var configuration = ConfigurationStore.Read(root);
        string ssid = "暂不可确认", iface = "—", gateway = "—", updated = "尚无成功检测", outcome = "", reason = "", revision = "", appliedRevision = "", engineVersion = "未知", networkKind = "Unknown", checkRequestId = "", ruleReason = "";
        int engineSchema = 0;
        bool fresh = false, stable = false, heartbeatPresent = false, probeFresh = false;
        DateTimeOffset? observedAt = null, diagnosticAt = null;
        var diagnosticState = ProxyDiagnosticState.Unknown;
        string diagnosticReason = "尚无近期诊断";
        string heartbeatPath = Path.Combine(root, "state", "status.json");
        if (File.Exists(heartbeatPath))
        {
            using var heartbeat = new FileStream(heartbeatPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (heartbeat.Length > 65536) throw new InvalidDataException("后台状态文件过大。");
            using var doc = JsonDocument.Parse(heartbeat); var h = doc.RootElement;
            string Text(string k) => h.TryGetProperty(k, out var v) ? v.ToString() : "";
            heartbeatPresent = true;
            outcome = Text("Outcome"); reason = Text("Reason"); ruleReason = Text("RuleReason"); revision = Text("ConfigRevision"); appliedRevision = Text("AppliedRevision");
            engineVersion = Text("EngineVersion"); int.TryParse(Text("SchemaVersion"), out engineSchema);
            checkRequestId = Text("CheckRequestId"); networkKind = Text("NetworkKind");
            ssid = Text("SSID"); gateway = Text("Gateway"); iface = Text("InterfaceGuid");
            int poll = int.TryParse(Text("PollSeconds"), out int n) ? n : 5;
            if (DateTimeOffset.TryParse(Text("Time"), out var time))
            {
                observedAt = time; updated = time.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
                var age = DateTimeOffset.Now - time; fresh = age.TotalSeconds >= -5 && age.TotalSeconds < Math.Max(30, poll * 2 + 15);
            }
            stable = Text("Stable").Equals("True", StringComparison.OrdinalIgnoreCase);
            bool parsedProbe = double.TryParse(Text("HealthCheckedAt"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double checkedAt);
            bool parsedClock = double.TryParse(Text("ClockSeconds"), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double clock);
            int interval = int.TryParse(Text("DiagnosticIntervalSeconds"), out int seconds) ? seconds : 60;
            probeFresh = fresh && parsedProbe && parsedClock && checkedAt >= 0 && clock - checkedAt >= 0 && clock - checkedAt <= interval + 15;
            if (probeFresh)
            {
                diagnosticAt = observedAt?.AddSeconds(checkedAt - clock);
                diagnosticState = Text("Health") switch { "TcpOpen" => ProxyDiagnosticState.TcpReachable, "HttpResponse" => ProxyDiagnosticState.HttpValidated, "Unavailable" => ProxyDiagnosticState.Failed, _ => ProxyDiagnosticState.Unknown };
                diagnosticReason = diagnosticState switch { ProxyDiagnosticState.TcpReachable => "TCP 可达 · 尚未验证 HTTP 代理", ProxyDiagnosticState.HttpValidated => "HTTP 代理请求验证通过", ProxyDiagnosticState.Failed => "代理验证失败 · 请确认代理服务和端口", _ => "诊断结果未知" };
            }
            if (Text("Diagnostics") == "None") { diagnosticState = ProxyDiagnosticState.Disabled; diagnosticReason = "诊断已关闭"; }
        }
        bool running = IsWatcherRunning();
        bool compatible = !heartbeatPresent || engineSchema >= ConfigurationStore.CurrentSchemaVersion && Version.TryParse(engineVersion.Split('-')[0], out var engine) && engine >= new Version(3, 2);
        if (!heartbeatPresent || engineVersion.Length == 0) engineVersion = "未知";
        bool paused = configuration.Intent != ManagementIntent.Monitoring;
        var networkState = GetNetworkState(networkKind, ssid, gateway, ruleReason.Length > 0 ? ruleReason : reason);
        if (!fresh)
        {
            networkState = NetworkConnectionState.Unknown;
            ssid = "暂时无法读取"; gateway = "暂时无法读取";
            reason = string.Join("；", new[] { reason, "后台状态已过期，上次成功检测：" + updated }.Where(x => x.Length > 0));
        }
        else if (networkState == NetworkConnectionState.Disconnected) ssid = "Wi-Fi 未连接";
        else if (ssid.Length == 0) ssid = "暂不可确认";
        if (gateway.Length == 0) gateway = "尚无有效 IPv4 网关";
        if (iface.Length == 0) iface = "—";
        bool connected = fresh && networkState is NetworkConnectionState.Connected or NetworkConnectionState.GatewayUnavailable or NetworkConnectionState.DhcpPending;
        string proxy; bool enabled; string server; bool policyManaged = false;
        if (AppController.TestRoot != null)
        {
            enabled = outcome is not ("Disable" or "Direct"); server = enabled ? "192.0.2.1:7890" : "";
            proxy = enabled ? "手动代理已开启 · " + server : "手动代理已关闭";
        }
        else
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings");
            enabled = Convert.ToInt32(key?.GetValue("ProxyEnable", 0)) == 1;
            server = key?.GetValue("ProxyServer", "") as string ?? "";
            string bypass = key?.GetValue("ProxyOverride", "") as string ?? "";
            proxy = enabled ? "手动代理已开启 · " + (server.Length > 0 ? server : "地址缺失") : "手动代理已关闭";
            if (bypass.Split(';').Any(p => p.Trim().Equals("<local>", StringComparison.OrdinalIgnoreCase))) proxy += " · 绕过本地地址";
            var actual = WiFiProxy.Native.ReadProxy();
            if (actual.Enable != enabled || enabled && actual.Server != server) { reason = "注册表与 WinINet 状态不一致；" + reason; outcome = "Retry"; }
            if ((actual.Flags & 12) != 0 || actual.Pac.Length > 0) reason += "；已保留 PAC/自动检测，应用实际选路可能由其决定";
            policyManaged = IsPolicyManaged();
        }
        if (DateTime.UtcNow - metadataTime > TimeSpan.FromMinutes(1) && AppController.TestRoot == null)
        {
            try
            {
                var all = NetworkInterface.GetAllNetworkInterfaces();
                interfaces = all.GroupBy(n => n.Id.Trim('{', '}'), StringComparer.OrdinalIgnoreCase).ToDictionary(g => g.Key, g => g.First().Name, StringComparer.OrdinalIgnoreCase);
                hasWirelessAdapter = all.Any(n => n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211);
                metadataTime = DateTime.UtcNow;
            }
            catch (NetworkInformationException) { }
        }
        if (networkState == NetworkConnectionState.Disconnected && hasWirelessAdapter == false && AppController.TestRoot == null)
        {
            networkState = NetworkConnectionState.NoWirelessAdapter; ssid = "未发现无线网卡";
            reason = "请连接或启用 Wi-Fi 网卡；当前不会使用有线或虚拟网卡的网关。";
        }
        if (interfaces.TryGetValue(iface.Trim('{', '}'), out var name)) iface = name + " · " + iface;
        string stateError = fresh && (outcome is "Retry" or "Keep" || networkState is NetworkConnectionState.Unknown or NetworkConnectionState.Ambiguous or NetworkConnectionState.AccessDenied or NetworkConnectionState.WlanUnavailable or NetworkConnectionState.GatewayUnavailable or NetworkConnectionState.NoWirelessAdapter) ? reason : "";
        var state = ApplicationStateEvaluator.Evaluate(new(true, configuration.SetupComplete, configuration.Intent, running, fresh, compatible, policyManaged, stateError));
        bool healthy = state == ApplicationState.Monitoring && stable && outcome is "Enable" or "Disable" && enabled == (outcome == "Enable");
        string watcher = state switch
        {
            ApplicationState.SetupRequired => "请完成首次配置", ApplicationState.Paused => "已暂停 · 当前手动代理可能继续生效",
            ApplicationState.DirectMode => "已选择直连 · 自动切换保持暂停", ApplicationState.PolicyManaged => "代理由组织策略管理",
            ApplicationState.UpgradeRequired => "需要升级后台组件", ApplicationState.Degraded => !running ? "后台未运行 · 请开启自动切换或查看日志" : !fresh ? "后台状态已过期" : "检测异常 · 保留当前设置",
            _ => stable ? "自动切换运行中" : "正在确认当前网络"
        };
        string rule = configuration.Intent == ManagementIntent.Direct ? "直连 · 自动管理已暂停" : paused ? "已暂停 · 不写入代理" : !fresh ? "等待近期检测" : networkState == NetworkConnectionState.Disconnected ? "已确认 Wi-Fi 断开" : (ruleReason + reason).Contains("免代理", StringComparison.Ordinal) || (ruleReason + reason).Contains("白名单", StringComparison.Ordinal) ? "命中免代理 Wi-Fi 规则" : (ruleReason + reason).Contains("Safe", StringComparison.Ordinal) ? "Safe 失败回退直连" : connected ? "当前 Wi-Fi IPv4 网关" : "等待网络稳定确认";
        var network = new NetworkStatus(networkState, fresh && connected ? ssid : "", iface, fresh && connected ? gateway : "", observedAt, fresh, ruleReason.Length > 0 ? ruleReason : reason);
        var diagnostic = new ProxyDiagnosticStatus(diagnosticState, diagnosticAt, probeFresh, diagnosticReason);
        return new(true, ssid, iface, gateway, proxy, watcher, updated, includeLogs ? Logs(root, errorsOnly, raw) : "", running, paused, healthy, rule, diagnosticReason, revision, outcome, reason, enabled, connected,
            state, engineVersion, fresh, server, configuration.Revision, appliedRevision, configuration.SetupComplete, configuration.Intent, network, diagnostic, engineSchema, checkRequestId);
    }

    private static NetworkConnectionState GetNetworkState(string kind, string ssid, string gateway, string reason)
    {
        if (kind == "Disconnected") return NetworkConnectionState.Disconnected;
        if (reason.Contains("权限", StringComparison.Ordinal) || reason.Contains("ACCESS_DENIED", StringComparison.OrdinalIgnoreCase) || reason.Contains("位置", StringComparison.Ordinal)) return NetworkConnectionState.AccessDenied;
        if (reason.Contains("服务", StringComparison.Ordinal) || reason.Contains("WLAN", StringComparison.OrdinalIgnoreCase) && reason.Contains("异常", StringComparison.Ordinal)) return NetworkConnectionState.WlanUnavailable;
        if (reason.Contains("无线网卡", StringComparison.Ordinal) && reason.Contains("无", StringComparison.Ordinal)) return NetworkConnectionState.NoWirelessAdapter;
        if (reason.Contains("多个", StringComparison.Ordinal) || reason.Contains("歧义", StringComparison.Ordinal)) return NetworkConnectionState.Ambiguous;
        if (kind == "Connected" && ssid.Length > 0) return gateway.Length > 0 ? NetworkConnectionState.Connected : NetworkConnectionState.GatewayUnavailable;
        return NetworkConnectionState.Unknown;
    }
    private static bool IsPolicyManaged()
    {
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
            foreach (string path in new[] { @"Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings", @"Software\Policies\Microsoft\Internet Explorer\Control Panel" })
            {
                using var key = hive.OpenSubKey(path);
                if (key != null && (Convert.ToInt32(key.GetValue("ProxySettingsPerUser", 1)) == 0 || Convert.ToInt32(key.GetValue("Proxy", 0)) == 1 || Convert.ToInt32(key.GetValue("AutoConfig", 0)) == 1 || key.GetValueNames().Any(n => n is "ProxyEnable" or "ProxyServer" or "ProxyOverride" or "AutoConfigURL"))) return true;
            }
        return false;
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
        if (AppController.TestRoot != null) return "Demo Hotspot";
        using var native = new WiFiProxy.Native(); long generation = native.Generation;
        var first = native.ReadWifi(); var second = native.ReadWifi();
        if (first.Length != 1 || second.Length != 1 || !first[0].NameDecoded || !second[0].NameDecoded || first[0].Guid != second[0].Guid || first[0].SsidHex != second[0].SsidHex || native.Generation != generation)
            throw new InvalidOperationException("无法唯一确认当前真实 Wi-Fi 名称，请检查连接和 Windows 位置权限，或手动输入。");
        return ConfigurationStore.ValidateSsid(second[0].SSID);
    }
    internal static string Logs(string root, bool errorsOnly = false, bool raw = false)
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
