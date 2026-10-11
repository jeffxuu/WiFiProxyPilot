using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;
internal static class SessionGuard
{
    [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool WTSQuerySessionInformation(IntPtr server, int session, int info, out IntPtr buffer, out int bytes);
    [DllImport("wtsapi32.dll")] private static extern void WTSFreeMemory(IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)] internal static extern bool AttachConsole(uint processId);
    internal static string Sid => WindowsIdentity.GetCurrent().User?.Value ?? throw new InvalidOperationException("无法识别当前用户 SID");
    private static string Query(int session, int field)
    {
        if (!WTSQuerySessionInformation(IntPtr.Zero, session, field, out var p, out _)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "无法确认桌面会话账户");
        try { return Marshal.PtrToStringUni(p) ?? ""; } finally { WTSFreeMemory(p); }
    }
    internal static void Validate()
    {
        int session = Process.GetCurrentProcess().SessionId;
        if (session == 0) throw new InvalidOperationException("请在当前桌面用户会话运行，不能使用服务会话。");
        string user = Query(session, 5), domain = Query(session, 7);
        if (string.IsNullOrWhiteSpace(user)) throw new InvalidOperationException("无法确认当前桌面用户。");
        string account = string.IsNullOrEmpty(domain) ? user : domain + "\\" + user;
        string desktopSid = ((SecurityIdentifier)new NTAccount(account).Translate(typeof(SecurityIdentifier))).Value;
        IdentityRules.Validate(Sid, desktopSid, session);
    }
}
