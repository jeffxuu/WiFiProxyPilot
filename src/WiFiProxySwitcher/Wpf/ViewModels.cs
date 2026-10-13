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
    internal void RefreshLocalized() => Changed(null);
}
internal sealed class UiCommand(Action<object?> action, Func<bool>? enabled = null) : ICommand
{
    public event EventHandler? CanExecuteChanged;
    public bool CanExecute(object? parameter) => enabled?.Invoke() ?? true;
    public void Execute(object? parameter) { if (CanExecute(parameter)) action(parameter); }
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
    public string SaveState => Localization.Text(Dirty ? "UnsavedChanges" : "AllSaved");
    internal void Load(IEnumerable<string> names) { Names.Clear(); foreach (string name in names) Names.Add(name); Dirty = false; }
    internal void Add() { string name = ConfigurationStore.ValidateSsid(Input); if (Names.Contains(name, StringComparer.OrdinalIgnoreCase)) throw new UiOperationException("DuplicateRule"); Names.Add(name); Input = ""; Dirty = true; }
    internal void Edit() { int index = Names.IndexOf(Selected); if (index < 0) throw new UiOperationException("SelectRule"); string name = ConfigurationStore.ValidateSsid(Input); if (Names.Where((_, i) => i != index).Contains(name, StringComparer.OrdinalIgnoreCase)) throw new UiOperationException("DuplicateRule"); Names[index] = name; Selected = name; Input = ""; Dirty = true; }
    internal void Delete() { if (Names.Remove(Selected)) Dirty = true; }
}
internal sealed class SettingsViewModel : ObservableModel
{
    private string port = "7890", mode = "Strict", diagnostics = "Tcp", url = "", theme = "System", language = Localization.Current.Language;
    private bool login = true, tray = true, minimize;
    internal event Action<Exception>? PreferenceError;
    public string Port { get => port; set => Set(ref port, value); }
    public string Mode { get => mode; set { Set(ref mode, value); Changed(nameof(Strict)); Changed(nameof(Safe)); } }
    public bool Strict { get => Mode == "Strict"; set { if (value) Mode = "Strict"; } }
    public bool Safe { get => Mode == "Safe"; set { if (value) Mode = "Safe"; } }
    public string Diagnostics { get => diagnostics; set => Set(ref diagnostics, value); }
    public string HttpUrl { get => url; set => Set(ref url, value); }
    public string Theme { get => theme; set => Set(ref theme, value); }
    public string Language
    {
        get => language;
        set
        {
            if (value is not ("System" or "zh-CN" or "en-US") || language == value) return;
            try { Localization.Current.SetLanguage(value); Set(ref language, value); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { Changed(nameof(Language)); PreferenceError?.Invoke(error); }
        }
    }
    public bool Login { get => login; set => Set(ref login, value); }
    public bool Tray { get => tray; set => Set(ref tray, value); }
    public bool Minimize { get => minimize; set => Set(ref minimize, value); }
    internal void Load(JsonObject c) { Port = c["Port"]!.ToString(); Mode = c["Mode"]!.ToString(); Diagnostics = c["Diagnostics"]!.ToString(); HttpUrl = c["HttpProbeUrl"]!.ToString(); Login = c["LoginMonitor"]?.GetValue<bool>() ?? true; Tray = c["TrayAutoStart"]?.GetValue<bool>() ?? true; Minimize = c["MinimizeToTray"]?.GetValue<bool>() ?? false; Theme = c["Theme"]?.GetValue<string>() ?? "System"; Language = UserPreferences.Language; }
    internal void Write(JsonObject c) { if (!int.TryParse(Port, System.Globalization.NumberStyles.Integer, Localization.Current.Culture, out int p) || p is < 1 or > 65535) throw new UiOperationException("Port"); c["Port"] = p; c["Mode"] = Mode; c["Diagnostics"] = Diagnostics; c["HttpProbeUrl"] = HttpUrl; c["LoginMonitor"] = Login; c["TrayAutoStart"] = Tray; c["CloseToTray"] = true; c["MinimizeToTray"] = Minimize; c["Theme"] = Theme; c["Language"] = Language; }
}
internal sealed class PilotViewModel : ObservableModel, IDisposable
{
    private readonly ApplicationServices services;
    private readonly System.Windows.Threading.DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(3) };
    private readonly CancellationTokenSource lifetime = new();
    private ConfigurationDocument? configuration;
    private StatusView? status;
    private Task? initialization;
    private bool busy, refreshing, errorsOnly, pendingMayNotify = true;
    private string page = "Dashboard", logs = "", pending = "", messageKey = "ReadingInstall";
    private object?[] messageArguments = [];
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
    public string PageTitle => Localization.Text(Page switch { "Rules" => "NavRules", "Settings" => "NavSettings", "Logs" => "NavLogs", "Setup" => "SetupTitle", _ => "NavOverview" });
    public string Message => Localization.Format(messageKey, messageArguments.Select(value => value is Exception error ? Localization.Error(error) : value).ToArray());
    public string Logs { get => logs.Length == 0 ? Localization.Text("NoLogs") : logs; private set => Set(ref logs, value); }
    public bool Busy { get => busy; private set { Set(ref busy, value); Action.Refresh(); ToggleAutomatic.Refresh(); EditRule.Refresh(); DeleteRule.Refresh(); Changed(nameof(AutomaticLabel)); Changed(nameof(AutomaticEnabled)); Changed(nameof(AutomaticControlEnabled)); Changed(nameof(DashboardAutomaticStatus)); } }
    public bool ErrorsOnly { get => errorsOnly; set { Set(ref errorsOnly, value); _ = RefreshAsync(); } }
    public StatusView? Status => status;
    public bool IsDemo => AppController.TestRoot != null;
    public string DemoDescription => Localization.Text("DemoBanner");
    public bool AutomaticControlEnabled => !Busy && !IsDemo;
    public bool SetupNeeded => status?.Installed != true || status.State == ApplicationState.SetupRequired;
    public bool MinimizeToTray => configuration?.Flag("MinimizeToTray", false) ?? false;
    public string AutomaticLabel => Localization.Text(IsDemo ? "DemoDisabled" : Busy ? "Working" : SetupNeeded ? "BeginSetup" : status?.Intent == ManagementIntent.Monitoring ? "PauseAutomatic" : "EnableAutomatic");
    public string Headline => Localization.Text(status?.State switch { ApplicationState.Monitoring => "HeadlineMonitoring", ApplicationState.Paused => status.ProxyEnabled ? "HeadlinePausedProxy" : "HeadlinePaused", ApplicationState.DirectMode => status.ProxyEnabled ? "HeadlinePausedProxy" : "HeadlineDirect", ApplicationState.UpgradeRequired => "HeadlineUpgrade", ApplicationState.PolicyManaged => "HeadlinePolicy", ApplicationState.Degraded => "HeadlineDegraded", _ => "HeadlineSetup" });
    public string Explanation => Localization.Text(SetupNeeded ? "ExplanationSetup" : status?.Intent == ManagementIntent.Paused ? "ExplanationPaused" : status?.Intent == ManagementIntent.Direct ? status.ProxyEnabled ? "ExplanationDirectProxy" : "ExplanationDirect" : "ExplanationMonitoring");
    public string NetworkLabel => status?.Fresh == true && status.Connected ? status.Network?.Ssid ?? status.Ssid : Localization.Text(status?.Network?.State == NetworkConnectionState.Disconnected ? "WifiDisconnected" : "Unreadable");
    private string LastDetection => status?.ObservedAt?.ToLocalTime().ToString("g", Localization.Current.Culture) ?? Localization.Text("NoneYet");
    public string NetworkDetail => status?.Fresh == true ? Localization.Format("GatewayDetail", DashboardGateway) : Localization.Format("LastDetection", LastDetection);
    public string ConnectionLabel => Localization.Text(status?.Fresh == true && status.Connected ? "Connected" : "Waiting");
    public string ProxyLabel => Localization.Text(ProxyUnreadable ? "Unreadable" : status?.Installed == true ? status.ProxyEnabled ? "ProxyOn" : "ProxyOff" : "AfterSetup");
    public string ProxyDetail => status?.ManualServer is { Length: > 0 } server ? server : Localization.Text("NoProxyAddress");
    public string RuleLabel => Localization.Text(status?.RuleCode switch { "Direct" => "RuleDirect", "Paused" => "RulePaused", "Pending" => "RulePending", "Disconnected" => "RuleDisconnected", "Whitelist" => "RuleBypass", "Gateway" => "RuleGateway", "SafeFallback" => "RuleSafe", _ => "Waiting" });
    public string CurrentRuleLabel => Localization.Format("CurrentRule", RuleLabel);
    public string DraftNetworks => Localization.Format("DraftNetworks", Rules.Names.Count);
    public string HealthLabel => DashboardDiagnosticStatus;
    public string Reason => Localization.Text(status?.ReasonCode switch { "ExternallyChanged" => "ProxyWhyExternal", "ProxyReadbackMismatch" => "ErrorProxyMismatch", "PreferredUnavailable" => "ReasonPreferredUnavailable", "Ambiguous" => "ReasonAmbiguous", "GatewayUnavailable" => "ReasonGatewayPending", "Stale" or "ReadFailed" => "ProxyWhyUnreadable", _ => status?.Network?.State switch { NetworkConnectionState.AccessDenied => "ReasonAccessDenied", NetworkConnectionState.WlanUnavailable => "ReasonWlanUnavailable", NetworkConnectionState.Ambiguous => "ReasonAmbiguous", NetworkConnectionState.NoWirelessAdapter => "WifiAdapterMissing", NetworkConnectionState.DhcpPending or NetworkConnectionState.GatewayUnavailable => "ReasonGatewayPending", NetworkConnectionState.Disconnected => "ReasonDisconnected", NetworkConnectionState.Connected => "ReasonMonitoring", _ => "ReasonUnknown" } });
    public string Engine => Localization.Format("EngineVersion", typeof(PilotViewModel).Assembly.GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), false).OfType<System.Reflection.AssemblyInformationalVersionAttribute>().FirstOrDefault()?.InformationalVersion.Split('+')[0] ?? "3.3.0-beta.1", status?.EngineVersion is { Length: > 0 } version && Version.TryParse(version.Split('-')[0], out _) ? version : Localization.Text("NotInstalled"));
    // One-way intent binding cannot write network settings. Confirmed readback is the only source.
    public bool AutomaticEnabled => !SetupNeeded && status?.Intent == ManagementIntent.Monitoring;
    public string DashboardNetworkTitle => status == null ? Localization.Text("ReadingWifi") : status.Installed ? NetworkLabel : Localization.Text("ConnectWifi");
    public string DashboardNetworkSubtitle => SetupNeeded ? Localization.Text("SetupKeepsProxy") : !status!.Fresh ? Localization.Format("LastDetection", LastDetection) : Localization.Text(status.Network?.State switch { NetworkConnectionState.Connected => "WifiConnected", NetworkConnectionState.GatewayUnavailable or NetworkConnectionState.DhcpPending => "WifiPendingGateway", NetworkConnectionState.Disconnected => "WifiDisconnected", NetworkConnectionState.NoWirelessAdapter => "WifiAdapterMissing", _ => "WifiUnknown" });
    public string DashboardAutomaticStatus => Localization.Text(IsDemo ? "DemoDisabled" : Busy ? "ProcessingWait" : SetupNeeded ? "AutomaticSetup" : status?.State switch { ApplicationState.Monitoring => "AutomaticMonitoring", ApplicationState.Paused => status.ProxyEnabled ? "HeadlinePausedProxy" : "AutomaticPaused", ApplicationState.DirectMode => status.ProxyEnabled ? "HeadlinePausedProxy" : "AutomaticDirect", ApplicationState.UpgradeRequired => "AutomaticUpgrade", ApplicationState.PolicyManaged => "AutomaticPolicy", _ => AutomaticEnabled ? "AutomaticUnknownEnabled" : "AutomaticUnknownPaused" });
    private bool ProxyUnreadable => status == null || !status.ProxyReadable;
    public string DashboardProxyStatus => Localization.Text(SetupNeeded ? "NotConfigured" : ProxyUnreadable ? "Unreadable" : status!.ProxyEnabled ? "Enabled" : "Disabled");
    public string DashboardProxyAddress => !SetupNeeded && !ProxyUnreadable && status!.ProxyEnabled ? status.ManualServer : "";
    public string DashboardGateway => status?.Fresh == true && status.Network?.Gateway is { Length: > 0 } gateway ? gateway : Localization.Text("Waiting");
    public string DashboardProxyWhy => Localization.Text(SetupNeeded ? "ProxyWhySetup" : ProxyUnreadable ? "ProxyWhyUnreadable" : status!.Intent == ManagementIntent.Paused ? status.ProxyEnabled ? "HeadlinePausedProxy" : "ProxyWhyPaused" : status.Intent == ManagementIntent.Direct ? status.ProxyEnabled ? "ProxyWhyDirectOn" : "ProxyWhyDirectOff" : status.State == ApplicationState.UpgradeRequired ? "ProxyWhyUpgrade" : status.State == ApplicationState.PolicyManaged ? "ProxyWhyPolicy" : status.ReasonCode == "ExternallyChanged" ? "ProxyWhyExternal" : !status.Fresh || status.State == ApplicationState.Degraded ? "ProxyWhyDegraded" : !status.ConfigApplied ? "ProxyWhyRulePending" : !status.ProxyEnabled && status.RuleCode == "Whitelist" ? "ProxyWhyBypass" : !status.ProxyEnabled && status.RuleCode == "SafeFallback" ? "ProxyWhySafe" : !status.ProxyEnabled && status.Network?.State == NetworkConnectionState.Disconnected ? "ProxyWhyDisconnect" : status.ProxyEnabled ? "ProxyWhyGateway" : "ProxyWhyOff");
    public string DashboardDiagnosticStatus => Localization.Text(status?.Diagnostic?.State == ProxyDiagnosticState.Disabled ? "DiagnosticDisabled" : status?.Diagnostic?.Fresh != true ? "Unknown" : status.Diagnostic.State switch { ProxyDiagnosticState.TcpReachable => "DiagnosticTcp", ProxyDiagnosticState.HttpValidated => "DiagnosticHttp", ProxyDiagnosticState.Failed => "DiagnosticFailed", _ => "Unknown" });
    public string DashboardDiagnosticDetail => Localization.Text(status?.Diagnostic?.Fresh != true ? "DiagnosticPending" : status.Diagnostic.State switch { ProxyDiagnosticState.TcpReachable => "DiagnosticTcpDetail", ProxyDiagnosticState.HttpValidated => "DiagnosticHttpDetail", ProxyDiagnosticState.Failed => "DiagnosticFailedDetail", _ => "DiagnosticUnknownDetail" });

    internal PilotViewModel(ApplicationServices services)
    {
        this.services = services;
        Navigate = new(p => { Page = p?.ToString() ?? "Dashboard"; if (Page == "Logs") _ = RefreshAsync(); });
        Action = new(p => _ = Perform(p?.ToString() ?? ""), () => !Busy);
        ToggleAutomatic = new(p => _ = Perform("automatic"), () => AutomaticControlEnabled);
        EditRule = new(p => { Rules.Selected = p?.ToString() ?? ""; Rules.Input = Rules.Selected; SetMessage("EditHint"); }, () => !Busy);
        DeleteRule = new(p => { Rules.Selected = p?.ToString() ?? ""; _ = Perform("delete"); }, () => !Busy);
        timer.Tick += Tick;
        Localization.Current.LanguageChanged += LanguageChanged;
        Rules.Names.CollectionChanged += RulesChanged;
        Settings.PropertyChanged += SettingsChanged;
        Settings.PreferenceError += PreferenceError;
    }
    private void SetMessage(string key, params object?[] args) { messageKey = key; messageArguments = args; Changed(nameof(Message)); }
    private void LanguageChanged() { Changed(null); Rules.RefreshLocalized(); Settings.RefreshLocalized(); if (Page == "Logs") _ = RefreshAsync(); }
    private void RulesChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e) => Changed(nameof(DraftNetworks));
    private void SettingsChanged(object? sender, PropertyChangedEventArgs e) { if (e.PropertyName == nameof(SettingsViewModel.Theme)) ThemeChanged?.Invoke(Settings.Theme); }
    private void PreferenceError(Exception error) { StartupMetrics.Value("LanguagePreferenceError", error.ToString()); SetMessage("OperationFailed", error); }
    internal Task InitializeAsync() => initialization ??= InitializeCore();
    private async Task InitializeCore()
    {
        Exception? configurationError = null;
        try { await Reload(); }
        catch (Exception error) { configurationError = error; StartupMetrics.Value("InitializationError", error.Message); await services.RecordUiError("initialize", error); }
        // Configuration failure must not suppress actual installation/status reads or the Logs page.
        await RefreshAsync(); timer.Start();
        if (configurationError != null) SetMessage("InitializationFailed", configurationError);
        else if (IsDemo) SetMessage("DemoBanner");
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
            Changed(null); ToggleAutomatic.Refresh();
            if (!Busy && pending.Length > 0 && next.Healthy && ConfigurationApplication.IsApplied(pending, new(next.Revision, next.AppliedRevision, next.EngineSchemaVersion, next.Healthy, next.Fresh))) { pending = ""; if (pendingMayNotify) SetMessage("RulesApplied"); }
            StatusChanged?.Invoke(next); StartupMetrics.Mark("FirstStatus"); StartupMetrics.Value("StatusRefreshMilliseconds", elapsed.Elapsed.TotalMilliseconds);
        }
        catch (Exception e) { StartupMetrics.Value("StatusReadError", e.Message); SetMessage("ReadFailed", e); Changed(nameof(NetworkLabel)); }
        finally { refreshing = false; }
    }
    internal async Task Perform(string operation)
    {
        if (Busy) return;
        Busy = true; SetMessage("Working");
        await services.RecordUiResult(operation, "Started");
        try
        {
            if (IsDemo && operation is "automatic" or "check" or "direct" or "restore" or "upgrade" or "enable-setup" or "uninstall")
                throw new UiOperationException("DemoDisabled");
            if (status?.State == ApplicationState.UpgradeRequired && operation is "automatic" or "direct" or "check")
                throw new UiOperationException("UpgradeRequired");
            switch (operation)
            {
                case "rules": Page = "Rules"; break;
                case "add": Rules.Add(); SetMessage("RuleAdded"); break;
                case "edit": Rules.Edit(); SetMessage("RuleEdited"); break;
                case "delete": Rules.Delete(); SetMessage("RuleDeleted"); break;
                case "current": Rules.Input = await services.CurrentSsid(); Rules.Add(); SetMessage("CurrentRuleAdded"); break;
                case "cancel": await Reload(); SetMessage("ChangesCanceled"); break;
                case "save-rules": case "save-settings":
                    if (configuration == null) throw new UiOperationException("ConfigurationNotLoaded");
                    var draft = (JsonObject)configuration.Values.DeepClone();
                    if (operation == "save-rules") draft["Whitelist"] = new JsonArray(Rules.Names.Select(n => (JsonNode?)JsonValue.Create(n)).ToArray()); else Settings.Write(draft);
                    configuration = await services.Save(configuration, draft); pending = configuration.Revision; pendingMayNotify = true;
                    if (operation == "save-rules") Rules.Load(configuration.Whitelist);
                    if (operation == "save-settings" && status?.Installed == true && !IsDemo) Ensure(await services.Execute("settings"));
                    SetMessage(SetupNeeded ? "DraftSaved" : "SavedPending"); break;
                case "automatic":
                    if (SetupNeeded) { Page = "Setup"; SetMessage("SetupHint"); break; }
                    bool pausing = status?.Intent == ManagementIntent.Monitoring;
                    Ensure(await services.Execute(pausing ? "pause" : "resume")); await Reload();
                    var readback = await services.ReadStatus();
                    if (readback.Intent != (pausing ? ManagementIntent.Paused : ManagementIntent.Monitoring)) throw new UiOperationException("IntentMismatch");
                    if (!pausing && (!readback.Running || !readback.Fresh)) throw new UiOperationException("WatcherNotRunning");
                    status = readback; SetMessage(pausing ? readback.ProxyEnabled ? "HeadlinePausedProxy" : "PausedConfirmed" : "EnabledConfirmed"); break;
                case "check": Ensure(await services.Execute("check")); SetMessage("CheckRequested"); break;
                case "direct":
                    if (Confirm("ConfirmDirectTitle", "ConfirmDirect")) { Ensure(await services.Execute("direct")); await Reload(); var actual = await services.ReadStatus(); if (!actual.ProxyReadable || actual.ProxyEnabled || actual.Intent != ManagementIntent.Direct) throw new UiOperationException("ProxyMismatch"); status = actual; SetMessage("DirectConfirmed"); } break;
                case "restore": if (Confirm("ConfirmRestoreTitle", "ConfirmRestore")) { Ensure(await services.Execute("restore")); await Reload(); SetMessage("RestoreConfirmed"); } break;
                case "upgrade": if (Confirm("ConfirmUpgradeTitle", "ConfirmUpgrade")) { Ensure(await services.Upgrade()); await Reload(); SetMessage("UpgradeConfirmed"); } break;
                case "enable-setup":
                    if (configuration == null) throw new UiOperationException("ConfigurationNotLoaded");
                    var setup = (JsonObject)configuration.Values.DeepClone(); Settings.Write(setup); setup["Whitelist"] = new JsonArray(Rules.Names.Select(n => (JsonNode?)JsonValue.Create(n)).ToArray());
                    if (Confirm("ConfirmSetupTitle", "ConfirmSetup", Settings.Port)) { Ensure(await services.Install(setup)); await Reload(); var enabled = await services.ReadStatus(); if (enabled.Intent != ManagementIntent.Monitoring || !enabled.Running || !enabled.Fresh) throw new UiOperationException("WatcherNotRunning"); status = enabled; Page = "Dashboard"; SetMessage("SetupConfirmed"); } break;
                case "uninstall": if (Confirm("ConfirmUninstallTitle", "ConfirmUninstall")) { bool exit = await services.Uninstall(); SetMessage("UninstallStartedMessage"); if (exit) { Busy = false; ExitRequested?.Invoke(); } } break;
                case "refresh": await RefreshAsync(); SetMessage("StatusRead"); break;
                case "copy": System.Windows.Clipboard.SetText($"WiFi Proxy Pilot\n{Engine}\n{Headline}\n{NetworkLabel}\n{NetworkDetail}\n{ProxyLabel}\n{ProxyDetail}\n{Reason}\n{Logs}"); SetMessage("Copied"); break;
            }
            await services.RecordUiResult(operation, "Completed");
        }
        catch (Exception e) { pendingMayNotify = false; StartupMetrics.Value("UiOperationError", e.ToString()); await services.RecordUiResult(operation, "Failed", e is UiOperationException known ? known.Code : e is ConfigurationValidationException validation ? validation.Code : e.GetType().Name); await services.RecordUiError(operation, e); SetMessage("OperationFailed", e); }
        finally { Busy = false; await RefreshAsync(); }
    }
    private static void Ensure(CommandResult result) { if (!result.Succeeded) throw new UiOperationException(result.Code, result.Message); }
    private bool Confirm(string titleKey, string textKey, params object?[] args)
    {
        bool accepted = ConfirmationDialog.Confirm(Localization.Text(titleKey), Localization.Format(textKey, args));
        if (!accepted) { pendingMayNotify = false; SetMessage("OperationCanceled"); }
        return accepted;
    }
    public void Dispose() { lifetime.Cancel(); timer.Stop(); timer.Tick -= Tick; Localization.Current.LanguageChanged -= LanguageChanged; Rules.Names.CollectionChanged -= RulesChanged; Settings.PropertyChanged -= SettingsChanged; Settings.PreferenceError -= PreferenceError; lifetime.Dispose(); }
}
