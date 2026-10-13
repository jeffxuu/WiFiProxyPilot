namespace WiFiProxySwitcher.Core;

// Persisted in config.json and interpreted by the independent watcher, never owned by a window.
public enum ManagementIntent { Monitoring, Paused, Direct }
public enum ApplicationState { NotInstalled, SetupRequired, Monitoring, Paused, DirectMode, Degraded, PolicyManaged, UpgradeRequired }
public enum NetworkConnectionState { Unknown, Connected, Disconnected, NoWirelessAdapter, AccessDenied, WlanUnavailable, DhcpPending, GatewayUnavailable, Ambiguous }
public enum ProxyDiagnosticState { Unknown, TcpReachable, HttpValidated, Failed, Disabled }

public sealed record NetworkStatus(NetworkConnectionState State, string Ssid = "", string InterfaceGuid = "", string Gateway = "", DateTimeOffset? ObservedAt = null, bool Fresh = false, string Reason = "");
public sealed record ProxyStatus(bool ManualEnabled, string Server = "", bool PacPresent = false, bool AutoDetect = false, bool ExternallyChanged = false);
public sealed record ProxyDiagnosticStatus(ProxyDiagnosticState State, DateTimeOffset? CheckedAt = null, bool Fresh = false, string Reason = "");

public sealed record ApplicationStateFacts(bool Installed, bool SetupComplete, ManagementIntent Intent,
    bool WatcherRunning, bool HeartbeatFresh, bool EngineCompatible = true, bool PolicyManaged = false, string Error = "");

public static class ApplicationStateEvaluator
{
    public static ApplicationState Evaluate(ApplicationStateFacts facts)
    {
        if (!facts.Installed) return ApplicationState.NotInstalled;
        if (!facts.EngineCompatible) return ApplicationState.UpgradeRequired;
        if (!facts.SetupComplete) return ApplicationState.SetupRequired;
        if (facts.PolicyManaged) return ApplicationState.PolicyManaged;
        // A stale heartbeat never erases a deliberate persisted choice. Read failures remain visible independently.
        if (facts.Intent == ManagementIntent.Direct) return ApplicationState.DirectMode;
        if (facts.Intent == ManagementIntent.Paused) return ApplicationState.Paused;
        if (!facts.WatcherRunning || !facts.HeartbeatFresh || facts.Error.Length > 0) return ApplicationState.Degraded;
        return ApplicationState.Monitoring;
    }
}

public sealed record ConfigurationApplicationStatus(string ConfigRevision, string AppliedRevision, int EngineSchemaVersion, bool Stable, bool Fresh);
public static class ConfigurationApplication
{
    public static bool IsApplied(string savedRevision, ConfigurationApplicationStatus status) =>
        savedRevision.Length == 64 && status.EngineSchemaVersion >= ConfigurationStore.CurrentSchemaVersion && status.Stable && status.Fresh &&
        string.Equals(savedRevision, status.ConfigRevision, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(savedRevision, status.AppliedRevision, StringComparison.OrdinalIgnoreCase);
}
