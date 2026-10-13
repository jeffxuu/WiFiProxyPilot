using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using System.Windows.Input;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;

internal abstract class ObservableModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    { if (EqualityComparer<T>.Default.Equals(field, value)) return false; field = value; Changed(name); return true; }
    protected internal void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
internal sealed class UiCommand(Action<object?> action, Func<bool>? enabled = null) : ICommand
{
    public event EventHandler? CanExecuteChanged;
    public bool CanExecute(object? parameter) => enabled?.Invoke() ?? true;
    public void Execute(object? parameter) => action(parameter);
    internal void Refresh() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}
internal sealed class NetworkRulesViewModel : ObservableModel
{
    public ObservableCollection<string> Names { get; } = [];
    private string input = "", selected = "";
    private bool dirty;
    public string Input { get => input; set => Set(ref input, value); }
    public string Selected { get => selected; set => Set(ref selected, value); }
    public bool Dirty { get => dirty; private set { Set(ref dirty, value); Changed(nameof(SaveState)); } }
    public string SaveState => Dirty ? "有未保存的修改" : "全部修改已保存";
    internal void Load(IEnumerable<string> names) { Names.Clear(); foreach (string name in names) Names.Add(name); Dirty = false; }
    internal void Add() { string name = ConfigurationStore.ValidateSsid(Input); if (Names.Contains(name, StringComparer.OrdinalIgnoreCase)) throw new InvalidDataException("这个 Wi-Fi 已在规则中。"); Names.Add(name); Input = ""; Dirty = true; }
    internal void Edit() { int index = Names.IndexOf(Selected); if (index < 0) throw new InvalidDataException("请先选择要编辑的网络。"); string name = ConfigurationStore.ValidateSsid(Input); if (Names.Where((_, i) => i != index).Contains(name, StringComparer.OrdinalIgnoreCase)) throw new InvalidDataException("这个 Wi-Fi 已在规则中。"); Names[index] = name; Selected = name; Input = ""; Dirty = true; }
    internal void Delete() { if (Names.Remove(Selected)) Dirty = true; }
}
internal sealed class SettingsViewModel : ObservableModel
{
    private string port = "7890", mode = "Strict", diagnostics = "Tcp", url = "", theme = "System";
    private bool login = true, tray = true, minimize;
    public string Port { get => port; set => Set(ref port, value); }
    public string Mode { get => mode; set { Set(ref mode, value); Changed(nameof(Strict)); Changed(nameof(Safe)); } }
    public bool Strict { get => Mode == "Strict"; set { if (value) Mode = "Strict"; } }
    public bool Safe { get => Mode == "Safe"; set { if (value) Mode = "Safe"; } }
    public string Diagnostics { get => diagnostics; set => Set(ref diagnostics, value); }
    public string HttpUrl { get => url; set => Set(ref url, value); }
    public string Theme { get => theme; set => Set(ref theme, value); }
    public bool Login { get => login; set => Set(ref login, value); }
    public bool Tray { get => tray; set => Set(ref tray, value); }
    public bool Minimize { get => minimize; set => Set(ref minimize, value); }
    internal void Load(JsonObject c) { Port = c["Port"]!.ToString(); Mode = c["Mode"]!.ToString(); Diagnostics = c["Diagnostics"]!.ToString(); HttpUrl = c["HttpProbeUrl"]!.ToString(); Login = c["LoginMonitor"]?.GetValue<bool>() ?? true; Tray = c["TrayAutoStart"]?.GetValue<bool>() ?? true; Minimize = c["MinimizeToTray"]?.GetValue<bool>() ?? false; Theme = c["Theme"]?.GetValue<string>() ?? "System"; }
    internal void Write(JsonObject c) { if (!int.TryParse(Port, out int p)) throw new InvalidDataException("代理端口应为 1–65535 的整数。"); c["Port"] = p; c["Mode"] = Mode; c["Diagnostics"] = Diagnostics; c["HttpProbeUrl"] = HttpUrl; c["LoginMonitor"] = Login; c["TrayAutoStart"] = Tray; c["CloseToTray"] = true; c["MinimizeToTray"] = Minimize; c["Theme"] = Theme; }
}
internal sealed class PilotViewModel : ObservableModel, IDisposable
{
    private readonly ApplicationServices services;
    private readonly System.Windows.Threading.DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(3) };
    private readonly CancellationTokenSource lifetime = new();
    private ConfigurationDocument? configuration;
    private StatusView? status;
    private Task? initialization;
    private bool busy, refreshing, errorsOnly;
    private string message = "正在读取当前用户的安装状态…", page = "Dashboard", logs = "尚无日志", pending = "";
    public NetworkRulesViewModel Rules { get; } = new();
    public SettingsViewModel Settings { get; } = new();
    public UiCommand Navigate { get; }
    public UiCommand Action { get; }
    public UiCommand ToggleAutomatic { get; }
    public UiCommand EditRule { get; }
    public UiCommand DeleteRule { get; }
    public event Action<StatusView>? StatusChanged;
    public event Action? ExitRequested;
    public event Action<string>? ThemeChanged;
    public string Page { get => page; private set { Set(ref page, value); Changed(nameof(PageTitle)); } }
    public string PageTitle => Page switch { "Rules" => "Wi-Fi 规则", "Settings" => "设置", "Logs" => "日志与诊断", "Setup" => "首次配置", _ => "Wi-Fi" };
    public string Message { get => message; private set => Set(ref message, value); }
    public string Logs { get => logs; private set => Set(ref logs, value); }
    public bool Busy { get => busy; private set { Set(ref busy, value); Action.Refresh(); ToggleAutomatic.Refresh(); EditRule.Refresh(); DeleteRule.Refresh(); Changed(nameof(AutomaticLabel)); Changed(nameof(AutomaticEnabled)); Changed(nameof(DashboardAutomaticStatus)); } }
    public bool ErrorsOnly { get => errorsOnly; set { Set(ref errorsOnly, value); _ = RefreshAsync(); } }
    public StatusView? Status => status;
    public bool SetupNeeded => status?.Installed != true || status.State == ApplicationState.SetupRequired;
    public bool MinimizeToTray => configuration?.Flag("MinimizeToTray", false) ?? false;
    public string AutomaticLabel => Busy ? "正在处理…" : SetupNeeded ? "开始配置" : status?.Intent == ManagementIntent.Monitoring ? "暂停自动切换" : "开启自动切换";
    public string Headline => status?.State switch { ApplicationState.Monitoring => "自动切换运行中", ApplicationState.Paused => "自动切换已暂停", ApplicationState.DirectMode => status.ProxyEnabled ? "已暂停，手动代理仍开启" : "已恢复直连", ApplicationState.UpgradeRequired => "需要升级后台组件", ApplicationState.PolicyManaged => "Windows 策略限制", ApplicationState.Degraded => "自动切换需要关注", _ => "让代理跟随你的 Wi-Fi" };
    public string Explanation => SetupNeeded ? "根据 Wi-Fi 自动切换 Windows 手动代理。首次配置完成前，不会更改你的网络设置。" : status?.Intent == ManagementIntent.Paused ? "后台停止写入。当前系统代理保留，可能仍然生效。" : status?.Intent == ManagementIntent.Direct ? status.ProxyEnabled ? "自动管理保持暂停，实际手动代理仍开启。可能关闭失败或被其他程序重新开启，请查看诊断。" : "自动管理已暂停，Windows 手动代理已关闭。" : "关闭窗口后，独立后台监控继续运行。";
    public string NetworkLabel => status?.Fresh == true ? status.Ssid : "暂时无法读取";
    public string NetworkDetail => status?.Fresh == true ? $"IPv4 默认网关  {status.Gateway}" : $"上次成功检测：{status?.Updated ?? "暂无"}";
    public string ConnectionLabel => status?.Fresh == true && status.Connected ? "已连接" : "等待确认";
    public string ProxyLabel => status?.Proxy.StartsWith("暂时无法读取", StringComparison.Ordinal) == true ? "暂时无法读取" : status?.Installed == true ? status.ProxyEnabled ? "手动代理已开启" : "手动代理已关闭" : "首次配置后显示";
    public string ProxyDetail => status?.ManualServer is { Length: > 0 } server ? server : "未配置代理地址";
    public string RuleLabel => status?.Rule ?? "等待配置";
    public string HealthLabel => status?.Health ?? "未知";
    public string Reason => status?.Reason is { Length: > 0 } reason ? reason : "配置开启后，将根据稳定确认的当前无线接口选择 IPv4 网关。";
    public string Engine => $"GUI 3.2.0-beta.1 · 后台 {status?.EngineVersion ?? "未安装"}";
    // The switch reflects persisted intent. Only a user command changes it; a binding update never writes proxy settings.
    public bool AutomaticEnabled => !SetupNeeded && status?.Intent == ManagementIntent.Monitoring;
    public string DashboardNetworkTitle => status == null ? "正在读取 Wi-Fi" : status.Installed ? NetworkLabel : "连接你的 Wi-Fi";
    public string DashboardNetworkSubtitle => SetupNeeded ? "首次配置前不会改变 Windows 代理" : !status!.Fresh ? $"上次检测：{status.Updated}" : status.Network?.State switch
    {
        NetworkConnectionState.Connected => "当前 Wi-Fi · 已连接", NetworkConnectionState.GatewayUnavailable or NetworkConnectionState.DhcpPending => "Wi-Fi 已连接 · 等待有效网关",
        NetworkConnectionState.Disconnected => "当前没有 Wi-Fi 连接", NetworkConnectionState.NoWirelessAdapter => "请连接或启用无线网卡", _ => "网络状态需要确认"
    };
    public string DashboardAutomaticStatus => Busy ? "正在处理，请稍候…" : SetupNeeded ? "未配置 · 开启前先完成设置" : status?.State switch
    {
        ApplicationState.Monitoring => "已开启 · 按 Wi-Fi 规则管理代理", ApplicationState.Paused => "已暂停 · 当前代理保持不变",
        ApplicationState.DirectMode => "已暂停 · 已选择直连", ApplicationState.UpgradeRequired => "后台需要升级 · 当前设置保持不变",
        ApplicationState.PolicyManaged => "受组织策略限制", _ => AutomaticEnabled ? "已启用 · 后台状态需要确认" : "已暂停 · 后台状态需要确认"
    };
    private bool ProxyUnreadable => status == null || status.Proxy.StartsWith("暂时无法读取", StringComparison.Ordinal);
    public string DashboardProxyStatus => SetupNeeded ? "尚未配置" : ProxyUnreadable ? "暂时无法读取" : status!.ProxyEnabled ? "已开启" : "已关闭";
    public string DashboardProxyAddress => !SetupNeeded && !ProxyUnreadable && status!.ProxyEnabled ? status.ManualServer : "";
    public string DashboardGateway => status?.Fresh == true ? status.Gateway : "等待确认";
    public string DashboardProxyWhy
    {
        get
        {
            if (SetupNeeded) return "完成设置并确认后，才会自动管理代理。";
            if (ProxyUnreadable) return "保留当前设置，等待重新读取。";
            if (status!.Intent == ManagementIntent.Paused) return "自动切换已暂停，当前手动代理保持不变。";
            if (status.Intent == ManagementIntent.Direct) return status.ProxyEnabled ? "手动代理仍开启，自动管理保持暂停。" : "已选择直连，自动管理保持暂停。";
            if (status.State == ApplicationState.UpgradeRequired) return "后台需要升级，当前设置保持不变。";
            if (status.State == ApplicationState.PolicyManaged) return "代理受组织策略管理，请联系管理员。";
            if (status.Reason.Contains("外部", StringComparison.Ordinal)) return "代理被其他程序修改，等待后台重新确认。";
            if (!status.Fresh || status.State == ApplicationState.Degraded) return "保留实际代理设置，等待后台确认当前网络。";
            if (status.Rule.Contains("等待", StringComparison.Ordinal)) return "当前规则尚未确认，保留实际代理设置。";
            if (!status.ProxyEnabled && status.Rule.Contains("免代理", StringComparison.Ordinal)) return "这个 Wi-Fi 在免代理规则中，使用直连。";
            if (!status.ProxyEnabled && status.Rule.Contains("Safe", StringComparison.Ordinal)) return "Safe 检测连续失败，已回退直连。";
            if (!status.ProxyEnabled && status.Network?.State == NetworkConnectionState.Disconnected) return "Wi-Fi 已断开，手动代理已关闭。";
            return status.ProxyEnabled ? "此 Wi-Fi 使用当前网关代理。" : "当前未使用 Windows 手动代理。";
        }
    }
    public string DashboardDiagnosticStatus => status?.Diagnostic?.State == ProxyDiagnosticState.Disabled ? "未启用诊断" : status?.Diagnostic?.Fresh != true ? "未知" : status.Diagnostic.State switch
    {
        ProxyDiagnosticState.TcpReachable => "仅 TCP 可达", ProxyDiagnosticState.HttpValidated => "HTTP 验证通过", ProxyDiagnosticState.Failed => "验证失败", _ => "未知"
    };
    public string DashboardDiagnosticDetail => status?.Diagnostic?.Fresh != true ? "尚无近期验证结果。立即检测会重新采集当前网络，再等待稳定确认。" : status.Diagnostic.State switch
    {
        ProxyDiagnosticState.TcpReachable => "TCP 端口可以连接，尚不能确认其提供可用的 HTTP 代理服务。",
        ProxyDiagnosticState.HttpValidated => "代理已返回有效 HTTP 响应；此检测不证明所有应用都能访问互联网。",
        ProxyDiagnosticState.Failed => "请确认手机或网关设备的代理服务正在运行，端口与你的配置一致。",
        _ => "尚无可确认的代理验证结果。"
    };
    internal PilotViewModel(ApplicationServices services)
    {
        this.services = services;
        Navigate = new(p => { Page = p?.ToString() ?? "Dashboard"; if (Page == "Logs") _ = RefreshAsync(); });
        Action = new(p => _ = Perform(p?.ToString() ?? ""), () => !Busy);
        ToggleAutomatic = new(p => _ = Perform("automatic"), () => !Busy);
        EditRule = new(p => { Rules.Selected = p?.ToString() ?? ""; Rules.Input = Rules.Selected; Message = "编辑名称后点击更新所选名称，再保存并应用。"; }, () => !Busy);
        DeleteRule = new(p => { Rules.Selected = p?.ToString() ?? ""; _ = Perform("delete"); }, () => !Busy);
        timer.Tick += Tick;
    }
    internal Task InitializeAsync() => initialization ??= InitializeCore();
    private async Task InitializeCore()
    {
        try { await Reload(); await RefreshAsync(); timer.Start(); await services.WarmCache(); if (AppController.TestRoot != null) Message = "隔离预览 · 网络数据为模拟，系统代理、任务和安装操作均已禁用。"; }
        catch (Exception e) { StartupMetrics.Value("InitializationError", e.Message); Message = "初始化未完成：" + e.Message; }
    }
    private void Tick(object? sender, EventArgs e) => _ = RefreshAsync();
    private async Task Reload() { configuration = await services.ReadConfiguration(); Rules.Load(configuration.Whitelist); Settings.Load(configuration.Values); ThemeChanged?.Invoke(Settings.Theme); }
    internal async Task RefreshAsync()
    {
        if (refreshing || lifetime.IsCancellationRequested) return; refreshing = true;
        var elapsed = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            var next = await services.ReadStatus(Page == "Logs", ErrorsOnly);
            if (lifetime.IsCancellationRequested) return;
            status = next; if (Page == "Logs") Logs = next.Logs;
            foreach (string name in new[] { nameof(Status), nameof(SetupNeeded), nameof(AutomaticLabel), nameof(Headline), nameof(Explanation), nameof(NetworkLabel), nameof(NetworkDetail), nameof(ProxyLabel), nameof(ProxyDetail), nameof(RuleLabel), nameof(HealthLabel), nameof(Reason), nameof(Engine), nameof(AutomaticEnabled), nameof(DashboardNetworkTitle), nameof(DashboardNetworkSubtitle), nameof(DashboardAutomaticStatus), nameof(DashboardProxyStatus), nameof(DashboardProxyAddress), nameof(DashboardProxyWhy), nameof(DashboardGateway), nameof(DashboardDiagnosticStatus), nameof(DashboardDiagnosticDetail) }) Changed(name);
            if (pending.Length > 0 && next.Healthy && ConfigurationApplication.IsApplied(pending, new(next.Revision, next.AppliedRevision, next.EngineSchemaVersion, next.Healthy, next.Fresh))) { pending = ""; Message = "规则已应用：后台已完成当前网络的稳定确认。"; }
            StatusChanged?.Invoke(next); StartupMetrics.Mark("FirstStatus"); StartupMetrics.Value("StatusRefreshMilliseconds", elapsed.Elapsed.TotalMilliseconds);
        }
        catch (Exception e) { Message = "暂时无法读取，保留上次检测时间：" + e.Message; Changed(nameof(NetworkLabel)); }
        finally { refreshing = false; }
    }
    internal async Task Perform(string operation)
    {
        if (Busy) return;
        Busy = true; Message = "正在处理…";
        try
        {
            if (status?.State == ApplicationState.UpgradeRequired && operation is "automatic" or "direct" or "check")
                throw new InvalidOperationException("当前运行的后台不支持新配置。请在设置的高级操作中升级后台组件，保留配置和最初备份。");
            switch (operation)
            {
                case "rules": Page = "Rules"; break;
                case "add": Rules.Add(); Message = "网络已添加，尚未保存。"; break;
                case "edit": Rules.Edit(); Message = "网络名称已修改，尚未保存。"; break;
                case "delete": Rules.Delete(); Message = "网络已删除，尚未保存。"; break;
                case "current": Rules.Input = await services.CurrentSsid(); Rules.Add(); Message = "当前网络已添加，尚未保存。"; break;
                case "cancel": await Reload(); Message = "未保存的修改已取消。"; break;
                case "save-rules": case "save-settings":
                    if (configuration == null) throw new InvalidOperationException("配置尚未载入。");
                    var draft = (JsonObject)configuration.Values.DeepClone();
                    if (operation == "save-rules") draft["Whitelist"] = new JsonArray(Rules.Names.Select(n => (JsonNode?)JsonValue.Create(n)).ToArray()); else Settings.Write(draft);
                    configuration = await services.Save(configuration, draft); pending = configuration.Revision;
                    if (operation == "save-rules") Rules.Load(configuration.Whitelist);
                    if (operation == "save-settings") { ThemeChanged?.Invoke(Settings.Theme); if (status?.Installed == true && AppController.TestRoot == null) Ensure(await services.Execute("settings")); }
                    Message = SetupNeeded ? "首次配置草稿已保存；确认开启后才改变 Windows 设置。" : "已保存，等待后台应用。暂停或直连时不会改写代理。"; break;
                case "automatic":
                    if (SetupNeeded) { Page = "Setup"; Message = "请设置端口和 Wi-Fi 规则，最后确认开启。"; break; }
                    Ensure(await services.Execute(status?.Intent == ManagementIntent.Monitoring ? "pause" : "resume"));
                    Message = status?.Intent == ManagementIntent.Monitoring ? "已暂停；当前代理保持不变。" : "已开启，等待后台稳定确认。"; await Reload(); break;
                case "check": Ensure(await services.Execute("check")); Message = "已请求重新采集，等待稳定确认；未使用旧网关强制写入。"; break;
                case "direct": if (Confirm("恢复直连", "将暂停自动管理并关闭 Windows 手动代理。PAC、自动检测和最初备份保留。")) { Ensure(await services.Execute("direct")); await Reload(); Message = "已恢复直连，自动管理保持暂停。"; } break;
                case "restore": if (Confirm("恢复安装前配置", "将停止自动管理，按最初备份恢复手动代理。检测到后来修改时保留冲突保护。")) { Ensure(await services.Execute("restore")); await Reload(); Message = "安装前配置已恢复。"; } break;
                case "upgrade": if (Confirm("升级后台组件", "将保留实际安装配置、原始备份和运行意图，更新当前用户组件。")) { Ensure(await services.Execute("install")); await Reload(); Message = "后台组件已升级。"; } break;
                case "enable-setup":
                    if (configuration == null) throw new InvalidOperationException("配置尚未载入。");
                    var setup = (JsonObject)configuration.Values.DeepClone(); Settings.Write(setup); setup["Whitelist"] = new JsonArray(Rules.Names.Select(n => (JsonNode?)JsonValue.Create(n)).ToArray());
                    if (Confirm("确认开启自动切换", $"软件不自带代理服务。将安装当前用户后台任务，并管理 Windows 手动代理。\n规则中的网络关闭手动代理；其他 Wi-Fi 使用当前 IPv4 网关:{Settings.Port}。\nPAC 和自动检测保持原样。")) { Ensure(await services.Install(setup)); await Reload(); Page = "Dashboard"; Message = "已完成配置，等待后台确认网络。"; } break;
                case "uninstall": if (Confirm("彻底卸载", "将退出界面、停止后台、清理自身任务并安全恢复。后续代理修改冲突不会自动覆盖。")) { await services.Uninstall(); Busy = false; ExitRequested?.Invoke(); } break;
                case "refresh": await RefreshAsync(); Message = "状态已读取。"; break;
                case "copy": System.Windows.Clipboard.SetText($"WiFi Proxy Pilot\n{Engine}\n{Headline}\n{NetworkLabel}\n{NetworkDetail}\n{ProxyLabel}\n{ProxyDetail}\n{Reason}\n{Logs}"); Message = "已复制。分享前请检查网络名称和地址等私人信息。"; break;
            }
        }
        catch (Exception e) { Message = "操作未完成：" + e.Message; }
        finally { Busy = false; await RefreshAsync(); }
    }
    private static void Ensure(CommandResult result) { if (!result.Succeeded) throw new IOException(result.Code == "RestoreConflict" ? "检测到后来修改的代理配置，当前设置及备份已保留；自动管理已停止。请查看日志后决定是否强制恢复。" : result.Message); }
    private static bool Confirm(string title, string text) => System.Windows.MessageBox.Show(text, title, System.Windows.MessageBoxButton.OKCancel, System.Windows.MessageBoxImage.Information) == System.Windows.MessageBoxResult.OK;
    public void Dispose() { lifetime.Cancel(); timer.Stop(); timer.Tick -= Tick; lifetime.Dispose(); }
}
