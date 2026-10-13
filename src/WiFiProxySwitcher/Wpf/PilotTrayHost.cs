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
    private Drawing.Icon icon = AppIcons.Create();
    private TrayIconState iconState = TrayIconState.Brand;
    private readonly RegisteredWaitHandle? activationWait, exitWait;
    private readonly uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private bool exiting, pendingExit;
    private readonly Forms.ToolStripMenuItem state = new() { Enabled = false }, toggle = new(), open = new(), check = new(), rules = new(), logs = new(), exitUi = new();
    internal PilotTrayHost(AppController controller, bool trayMode, EventWaitHandle? activation = null, EventWaitHandle? exit = null)
    {
        Window = new PilotWindow(new PilotViewModel(new ApplicationServices(controller)));
        var menu = new Forms.ContextMenuStrip();
        open.Click += (_, _) => Open(); menu.Items.Add(open); menu.Items.Add(state); menu.Items.Add(new Forms.ToolStripSeparator());
        toggle.Click += (_, _) => Dispatch(() => Window.ViewModel.ToggleAutomatic.Execute(null)); menu.Items.Add(toggle);
        check.Click += (_, _) => Dispatch(() => Window.ViewModel.Action.Execute("check")); menu.Items.Add(check);
        rules.Click += (_, _) => Open("Rules"); menu.Items.Add(rules); logs.Click += (_, _) => Open("Logs"); menu.Items.Add(logs);
        menu.Items.Add(new Forms.ToolStripSeparator()); exitUi.Click += (_, _) => ExitUi(); menu.Items.Add(exitUi);
        Tray = new Forms.NotifyIcon { Icon = icon, Text = "WiFi Proxy Pilot", ContextMenuStrip = menu, Visible = true };
        RefreshLanguage(); Localization.Current.LanguageChanged += LanguageChanged;
        Tray.DoubleClick += (_, _) => Open();
        Window.ViewModel.ExitRequested += ExitUi; Window.ViewModel.StatusChanged += Update;
        Window.ViewModel.PropertyChanged += ViewModelChanged;
        var hwnd = new WindowInteropHelper(Window).EnsureHandle(); var source = HwndSource.FromHwnd(hwnd); source.AddHook(ShellMessages);
        if (activation != null) activationWait = ThreadPool.RegisterWaitForSingleObject(activation, (_, _) => Dispatch(() => Open()), null, Timeout.Infinite, false);
        if (exit != null) exitWait = ThreadPool.RegisterWaitForSingleObject(exit, (_, _) => Dispatch(ExitUi), null, Timeout.Infinite, false);
        SystemEvents.PowerModeChanged += PowerChanged; SystemEvents.SessionSwitch += SessionChanged;
        SystemEvents.DisplaySettingsChanged += DisplayChanged; SystemEvents.UserPreferenceChanged += ShellPreferenceChanged;
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
            Window.ViewModel.Navigate.Execute(page); Window.Show(); if (Window.WindowState == WindowState.Minimized) Window.WindowState = WindowState.Normal; Window.Activate(); SetForegroundWindow(new WindowInteropHelper(Window).Handle); Window.UpdateLayout(); StartupMetrics.Value("TrayOpenMilliseconds", clock.Elapsed.TotalMilliseconds); StartupMetrics.Mark("Reopened"); _ = Window.ViewModel.RefreshAsync();
        });
    }
    private void RefreshLanguage()
    {
        open.Text = Localization.Text("TrayOpen"); check.Text = Localization.Text("CheckNow");
        rules.Text = Localization.Text("NavRules"); logs.Text = Localization.Text("NavLogs"); exitUi.Text = Localization.Text("TrayExit");
        state.Text = Window.ViewModel.Headline; toggle.Text = Window.ViewModel.AutomaticLabel;
        string caption = "WiFi Proxy Pilot · " + Window.ViewModel.Headline; Tray.Text = caption[..Math.Min(63, caption.Length)];
        toggle.Enabled = Window.ViewModel.AutomaticControlEnabled; check.Enabled = Window.ViewModel.AutomaticControlEnabled;
    }
    private void LanguageChanged() => Dispatch(RefreshLanguage);
    private void Update(StatusView status)
    {
        RefreshLanguage();
        var next = status.State is WiFiProxySwitcher.Core.ApplicationState.Degraded or WiFiProxySwitcher.Core.ApplicationState.PolicyManaged or WiFiProxySwitcher.Core.ApplicationState.UpgradeRequired
            ? TrayIconState.Attention : status.Intent == WiFiProxySwitcher.Core.ManagementIntent.Paused ? TrayIconState.Paused
            : !status.ProxyEnabled ? TrayIconState.Direct : status.Intent == WiFiProxySwitcher.Core.ManagementIntent.Direct ? TrayIconState.Attention : TrayIconState.Monitoring;
        if (next != iconState)
        {
            var replacement = AppIcons.Create(next); var previous = icon;
            Tray.Icon = replacement; icon = replacement; iconState = next; previous.Dispose();
        }
    }
    private void ViewModelChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is null or nameof(PilotViewModel.Busy) or nameof(PilotViewModel.AutomaticLabel))
        {
            RefreshLanguage();
            if (pendingExit && !Window.ViewModel.Busy) Window.Dispatcher.BeginInvoke(ExitUi);
        }
    }
    private IntPtr ShellMessages(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) { if ((uint)message == taskbarCreated && !exiting) { Tray.Visible = false; Tray.Visible = true; } return IntPtr.Zero; }
    internal void SimulateTaskbarCreated() => SendMessage(new WindowInteropHelper(Window).Handle, taskbarCreated, IntPtr.Zero, IntPtr.Zero);
    private void Dispatch(Action action) { if (exiting) return; if (Window.Dispatcher.CheckAccess()) action(); else Window.Dispatcher.BeginInvoke(action); }
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) { if (e.Mode == PowerModes.Resume) Dispatch(() => { _ = Window.ViewModel.RefreshAsync(); }); }
    private void SessionChanged(object sender, SessionSwitchEventArgs e) { if (e.Reason == SessionSwitchReason.SessionUnlock) Dispatch(() => { _ = Window.ViewModel.RefreshAsync(); }); }
    private void DisplayChanged(object? sender, EventArgs e) => Dispatch(ReloadIcon);
    private void ShellPreferenceChanged(object sender, UserPreferenceChangedEventArgs e) => Dispatch(ReloadIcon);
    private void ReloadIcon()
    {
        var replacement = AppIcons.Create(iconState); var previous = icon;
        Tray.Icon = replacement; icon = replacement; previous.Dispose();
    }
    internal void ExitUi()
    {
        if (exiting) return; if (Window.ViewModel.Busy) { pendingExit = true; return; }
        exiting = true; activationWait?.Unregister(null); exitWait?.Unregister(null);
        SystemEvents.PowerModeChanged -= PowerChanged; SystemEvents.SessionSwitch -= SessionChanged;
        SystemEvents.DisplaySettingsChanged -= DisplayChanged; SystemEvents.UserPreferenceChanged -= ShellPreferenceChanged;
        Window.ViewModel.StatusChanged -= Update; Window.ViewModel.ExitRequested -= ExitUi;
        Window.ViewModel.PropertyChanged -= ViewModelChanged;
        Localization.Current.LanguageChanged -= LanguageChanged;
        Tray.Visible = false; Tray.ContextMenuStrip?.Dispose(); Tray.Dispose(); icon.Dispose();
        Window.ExitWindow(); Window.ViewModel.Dispose(); Application.Current?.Shutdown();
    }
    public void Dispose() => ExitUi();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string value);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
}
