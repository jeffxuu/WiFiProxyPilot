namespace WiFiProxySwitcher
{
    // Production StatusReader is linked unchanged; every actual Windows boundary is forbidden here.
    internal static class AppController
    {
        internal static string? TestRoot { get; set; }
        internal static string? InstalledRoot() => TestRoot;
    }
    internal static class SessionGuard { internal static string Sid => throw new InvalidOperationException("Tests forbid Windows identity queries"); }
}
namespace WiFiProxy
{
    public sealed record Proxy(bool Enable, string Server, int Flags, string Pac);
    public sealed record Link(string SSID, string Guid, string SsidHex, bool NameDecoded);
    public sealed class Native : IDisposable
    {
        public long Generation => throw new InvalidOperationException("Tests forbid native WLAN queries");
        public static Proxy ReadProxy() => throw new InvalidOperationException("Tests forbid native proxy queries");
        public Link[] ReadWifi() => throw new InvalidOperationException("Tests forbid native WLAN queries");
        public void Dispose() { }
    }
}
