using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace WiFiProxySwitcher;
internal sealed class SingleInstance : IDisposable
{
    private readonly Mutex mutex;
    private readonly bool owned;
    internal EventWaitHandle Activation { get; }
    internal EventWaitHandle ExitRequest { get; }
    internal bool Primary => owned;
    internal SingleInstance()
    {
        string name = Name;
        mutex = new Mutex(false, name);
        try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
        Activation = new EventWaitHandle(false, EventResetMode.AutoReset, name + ".Activate");
        ExitRequest = new EventWaitHandle(false, EventResetMode.AutoReset, name + ".Exit");
        if (!owned) Activation.Set(); // The primary consumes even an early signal after creating its window handle.
    }
    private static string Name => "Local\\WiFiProxySwitcher.Tray." + SessionGuard.Sid + "." + Process.GetCurrentProcess().SessionId + "." + (AppController.TestRoot == null ? "desktop" : Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(AppController.TestRoot))));
    internal static void RequestExitAndWait()
    {
        try
        {
            using var exit = EventWaitHandle.OpenExisting(Name + ".Exit"); exit.Set();
            using var m = Mutex.OpenExisting(Name); bool taken;
            try { taken = m.WaitOne(TimeSpan.FromSeconds(20)); } catch (AbandonedMutexException) { taken = true; }
            if (!taken) throw new TimeoutException("界面仍在完成操作，请关闭界面后重试卸载；尚未停止监控或改写代理。");
            m.ReleaseMutex();
        }
        catch (WaitHandleCannotBeOpenedException) { }
    }
    public void Dispose() { Activation.Dispose(); ExitRequest.Dispose(); if (owned) mutex.ReleaseMutex(); mutex.Dispose(); }
}
