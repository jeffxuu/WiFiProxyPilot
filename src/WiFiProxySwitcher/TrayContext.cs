using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace WiFiProxySwitcher;
internal sealed class TrayContext : ApplicationContext
{
    internal MainForm Window { get; }
    internal NotifyIcon Tray { get; }
    private readonly ToolStripMenuItem stateItem = new("正在读取网络状态") { Enabled = false };
    private readonly ToolStripMenuItem toggle = new("开启自动切换");
    private readonly ToolStripMenuItem check = new("立即检测");
    private readonly ToolStripMenuItem restore = new("停止监控并恢复代理…");
    private readonly ShellWindow shell;
    private readonly RegisteredWaitHandle? activationWait;
    private readonly RegisteredWaitHandle? exitWait;
    private readonly Icon[] icons = [AppIcons.Create(Color.FromArgb(0, 103, 192)), AppIcons.Create(Color.SeaGreen), AppIcons.Create(Color.Gray), AppIcons.Create(Color.DarkOrange), AppIcons.Create(Color.SlateGray)];
    private bool exiting;
    private int iconIndex = -1;
    internal TrayContext(AppController? controller, bool hidden, EventWaitHandle? activation = null, EventWaitHandle? exit = null)
    {
        SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
        Window = new MainForm(controller); Window.ExitRequested += ExitUi;
        var menu = new ContextMenuStrip();
        menu.Items.Add("打开主界面", null, (_, _) => Open()); menu.Items.Add(stateItem); menu.Items.Add(new ToolStripSeparator());
        toggle.Click += async (_, _) => await Window.ToggleAutomatic(); menu.Items.Add(toggle);
        check.Click += async (_, _) => await Window.Operate("check"); menu.Items.Add(check);
        menu.Items.Add("免代理 Wi-Fi 管理", null, (_, _) => Open(1)); menu.Items.Add("查看日志", null, (_, _) => Open(3));
        restore.Click += async (_, _) => await Window.Operate("restore"); menu.Items.Add(restore); menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("退出界面（后台监控继续）", null, (_, _) => ExitUi());
        Tray = new NotifyIcon { Icon = icons[2], Text = "Wi-Fi 智能代理切换 · 正在读取", ContextMenuStrip = menu, Visible = true };
        Tray.DoubleClick += (_, _) => Open();
        Window.FormClosing += (_, e) =>
        {
            if (exiting || e.CloseReason != CloseReason.UserClosing) return;
            if (Window.CloseToTray) { e.Cancel = true; Window.Hide(); }
            else { e.Cancel = true; ExitUi(); }
        };
        Window.Resize += (_, _) => { if (Window.WindowState == FormWindowState.Minimized && Window.MinimizeToTray) Window.Hide(); };
        Window.StatusChanged += Update;
        Window.BusyChanged += busy => { toggle.Enabled = !busy; check.Enabled = !busy && Window.CurrentStatus?.Running == true && !Window.CurrentStatus.Paused; restore.Enabled = !busy && Window.CurrentStatus?.Installed == true; };
        shell = new ShellWindow(() => { if (!exiting) { Tray.Visible = false; Tray.Visible = true; } });
        SystemEvents.PowerModeChanged += PowerChanged; SystemEvents.SessionSwitch += SessionChanged;
        Window.FormClosed += (_, _) => ExitUi();
        // Keep a real handle while hidden so activation and resume events can marshal to the UI thread.
        _ = Window.Handle;
        if (activation != null) activationWait = ThreadPool.RegisterWaitForSingleObject(activation, (_, _) => Dispatch(() => Open()), null, Timeout.Infinite, false);
        if (exit != null) exitWait = ThreadPool.RegisterWaitForSingleObject(exit, (_, _) => Dispatch(ExitUi), null, Timeout.Infinite, false);
        if (hidden) _ = Window.InitializeAsync(); else Window.Show();
    }
    internal void Open(int page = 0)
    {
        if (exiting) return;
        var clock = System.Diagnostics.Stopwatch.StartNew();
        Window.Show(); Window.WindowState = FormWindowState.Normal; Window.SelectPage(page); Window.Activate();
        SetForegroundWindow(Window.Handle);
        Window.Update(); StartupMetrics.Value("TrayOpenMilliseconds", clock.Elapsed.TotalMilliseconds);
        StartupMetrics.Mark("Reopened"); _ = Window.RefreshAsync();
    }
    private void Update(StatusView s)
    {
        int next = !s.Running || s.Paused ? 4 : !s.Healthy || s.Health.Contains("失败") ? 3 : !s.Connected ? 2 : s.ProxyEnabled ? 0 : 1;
        if (next != iconIndex) { Tray.Icon = icons[next]; iconIndex = next; }
        string caption = $"{s.Ssid} · {s.Watcher}"; Tray.Text = caption[..Math.Min(caption.Length, 63)];
        stateItem.Text = $"Wi-Fi：{s.Ssid}  |  手动代理：{(s.ProxyEnabled ? "开启" : "关闭")}";
        toggle.Text = s.Running && !s.Paused ? "暂停自动切换（保留当前代理）" : "启用自动切换";
        toggle.Enabled = !Window.IsBusy; check.Enabled = !Window.IsBusy && s.Running && !s.Paused; restore.Enabled = !Window.IsBusy && s.Installed;
    }
    private void Dispatch(Action action) { if (!exiting && !Window.IsDisposed) { try { Window.BeginInvoke(action); } catch (InvalidOperationException) { } } }
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) { if (e.Mode == PowerModes.Resume) Dispatch(() => { _ = Window.RefreshAsync(); }); }
    private void SessionChanged(object sender, SessionSwitchEventArgs e) { if (e.Reason == SessionSwitchReason.SessionUnlock) Dispatch(() => { _ = Window.RefreshAsync(); }); }
    internal void ExitUi()
    {
        if (exiting) return;
        if (Window.IsBusy) { Window.Feedback("正在完成操作，请稍后退出界面。"); return; }
        exiting = true; activationWait?.Unregister(null); exitWait?.Unregister(null);
        SystemEvents.PowerModeChanged -= PowerChanged; SystemEvents.SessionSwitch -= SessionChanged;
        Tray.Visible = false; Tray.ContextMenuStrip?.Dispose(); Tray.Dispose(); shell.Dispose();
        Window.Close(); Window.Dispose(); foreach (var icon in icons) icon.Dispose();
        ExitThread(); // Deliberately no watcher stop, restore, task or proxy action.
    }
    internal void SimulateTaskbarCreated() => shell.SendRecreate();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    private sealed class ShellWindow : NativeWindow, IDisposable
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string value);
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
        private readonly uint message = RegisterWindowMessage("TaskbarCreated");
        private readonly Action recreate;
        internal ShellWindow(Action recreate) { this.recreate = recreate; CreateHandle(new CreateParams { Caption = "WiFiProxySwitcher.ShellListener" }); }
        protected override void WndProc(ref Message m) { if ((uint)m.Msg == message) recreate(); base.WndProc(ref m); }
        internal void SendRecreate() => SendMessage(Handle, message, IntPtr.Zero, IntPtr.Zero);
        public void Dispose() => DestroyHandle();
    }
}

internal static class AppIcons
{
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    internal static Icon Create(Color color)
    {
        using var bitmap = new Bitmap(32, 32); using var g = Graphics.FromImage(bitmap);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        using var background = new SolidBrush(color); g.FillEllipse(background, 1, 1, 30, 30);
        using var pen = new Pen(Color.White, 2.4F) { StartCap = System.Drawing.Drawing2D.LineCap.Round, EndCap = System.Drawing.Drawing2D.LineCap.Round };
        g.DrawArc(pen, 6, 8, 20, 18, 220, 100); g.DrawArc(pen, 10, 13, 12, 11, 220, 100);
        g.FillEllipse(Brushes.White, 14, 22, 4, 4);
        IntPtr handle = bitmap.GetHicon(); try { using var borrowed = Icon.FromHandle(handle); return (Icon)borrowed.Clone(); } finally { DestroyIcon(handle); }
    }
}
