using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Win32;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace WiFiProxySwitcher;

internal sealed class PilotTrayHost : IDisposable
{
    internal PilotWindow Window { get; }
    internal Forms.NotifyIcon Tray { get; }
    private readonly Drawing.Icon icon = AppIcons.Create(Drawing.Color.FromArgb(0, 122, 255));
    private readonly RegisteredWaitHandle? activationWait, exitWait;
    private readonly uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private bool exiting, pendingExit;
    private readonly Forms.ToolStripMenuItem state = new("正在读取状态") { Enabled = false }, toggle = new("开启自动切换");
    internal PilotTrayHost(AppController controller, bool trayMode, EventWaitHandle? activation = null, EventWaitHandle? exit = null)
    {
        Window = new PilotWindow(new PilotViewModel(new ApplicationServices(controller)));
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("打开 WiFi Proxy Pilot", null, (_, _) => Open()); menu.Items.Add(state); menu.Items.Add(new Forms.ToolStripSeparator());
        toggle.Click += (_, _) => Dispatch(() => Window.ViewModel.Action.Execute("automatic")); menu.Items.Add(toggle);
        menu.Items.Add("立即检测", null, (_, _) => Dispatch(() => Window.ViewModel.Action.Execute("check")));
        menu.Items.Add("Wi-Fi 规则", null, (_, _) => Open("Rules")); menu.Items.Add("日志与诊断", null, (_, _) => Open("Logs"));
        menu.Items.Add(new Forms.ToolStripSeparator()); menu.Items.Add("退出界面（后台继续）", null, (_, _) => ExitUi());
        Tray = new Forms.NotifyIcon { Icon = icon, Text = "WiFi Proxy Pilot", ContextMenuStrip = menu, Visible = true };
        Tray.DoubleClick += (_, _) => Open();
        Window.ViewModel.ExitRequested += ExitUi; Window.ViewModel.StatusChanged += Update;
        Window.ViewModel.PropertyChanged += ViewModelChanged;
        var hwnd = new WindowInteropHelper(Window).EnsureHandle(); var source = HwndSource.FromHwnd(hwnd); source.AddHook(ShellMessages); source.AddHook(Window.WindowMessages);
        if (activation != null) activationWait = ThreadPool.RegisterWaitForSingleObject(activation, (_, _) => Dispatch(() => Open()), null, Timeout.Infinite, false);
        if (exit != null) exitWait = ThreadPool.RegisterWaitForSingleObject(exit, (_, _) => Dispatch(ExitUi), null, Timeout.Infinite, false);
        SystemEvents.PowerModeChanged += PowerChanged; SystemEvents.SessionSwitch += SessionChanged;
        if (trayMode) _ = Window.ViewModel.InitializeAsync(); else Window.Show();
    }
    internal void Open(string page = "Dashboard")
    {
        if (exiting) return;
        var clock = System.Diagnostics.Stopwatch.StartNew();
        Dispatch(() =>
        {
            if (AppController.TestRoot != null)
            {
                EventHandler? painted = null;
                painted = (_, _) => { System.Windows.Media.CompositionTarget.Rendering -= painted; StartupMetrics.Value("TrayPaintMilliseconds", clock.Elapsed.TotalMilliseconds); };
                System.Windows.Media.CompositionTarget.Rendering += painted;
            }
            Window.ViewModel.Navigate.Execute(page); Window.Show(); Window.WindowState = WindowState.Normal; Window.Activate(); SetForegroundWindow(new WindowInteropHelper(Window).Handle); Window.UpdateLayout(); StartupMetrics.Value("TrayOpenMilliseconds", clock.Elapsed.TotalMilliseconds); StartupMetrics.Mark("Reopened"); _ = Window.ViewModel.RefreshAsync();
        });
    }
    private void Update(StatusView status)
    {
        state.Text = status.Watcher; toggle.Text = Window.ViewModel.AutomaticLabel;
        string caption = "WiFi Proxy Pilot · " + Window.ViewModel.Headline; Tray.Text = caption[..Math.Min(63, caption.Length)];
        toggle.Enabled = !Window.ViewModel.Busy;
    }
    private void ViewModelChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PilotViewModel.Busy)) { toggle.Enabled = !Window.ViewModel.Busy; if (pendingExit && !Window.ViewModel.Busy) Window.Dispatcher.BeginInvoke(ExitUi); }
    }
    private IntPtr ShellMessages(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) { if ((uint)message == taskbarCreated && !exiting) { Tray.Visible = false; Tray.Visible = true; } return IntPtr.Zero; }
    internal void SimulateTaskbarCreated() => SendMessage(new WindowInteropHelper(Window).Handle, taskbarCreated, IntPtr.Zero, IntPtr.Zero);
    private void Dispatch(Action action) { if (exiting) return; if (Window.Dispatcher.CheckAccess()) action(); else Window.Dispatcher.BeginInvoke(action); }
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) { if (e.Mode == PowerModes.Resume) Dispatch(() => { _ = Window.ViewModel.RefreshAsync(); }); }
    private void SessionChanged(object sender, SessionSwitchEventArgs e) { if (e.Reason == SessionSwitchReason.SessionUnlock) Dispatch(() => { _ = Window.ViewModel.RefreshAsync(); }); }
    internal void ExitUi()
    {
        if (exiting) return; if (Window.ViewModel.Busy) { pendingExit = true; return; }
        exiting = true; activationWait?.Unregister(null); exitWait?.Unregister(null);
        SystemEvents.PowerModeChanged -= PowerChanged; SystemEvents.SessionSwitch -= SessionChanged;
        Window.ViewModel.StatusChanged -= Update; Window.ViewModel.ExitRequested -= ExitUi;
        Window.ViewModel.PropertyChanged -= ViewModelChanged;
        Tray.Visible = false; Tray.ContextMenuStrip?.Dispose(); Tray.Dispose(); icon.Dispose();
        Window.ExitWindow(); Window.ViewModel.Dispose(); Application.Current?.Shutdown();
    }
    public void Dispose() => ExitUi();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string value);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
}
