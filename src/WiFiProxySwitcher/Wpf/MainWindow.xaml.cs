using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Microsoft.Win32;

namespace WiFiProxySwitcher;

// Only window chrome, page presentation and theme resources live here.
public partial class PilotWindow : Window
{
    private readonly Dictionary<string, UserControl> pages = new();
    private readonly Dictionary<string, ResourceDictionary> themes = new();
    private readonly ResourceDictionary design;
    private bool exiting, dark;
    internal PilotViewModel ViewModel { get; }
    internal PilotWindow(PilotViewModel model)
    {
        var load = System.Diagnostics.Stopwatch.StartNew();
        design = new() { Source = new Uri("/WiFiProxySwitcher;component/Wpf/Theme.xaml", UriKind.Relative) };
        Application.Current.Resources.MergedDictionaries.Add(design);
        StartupMetrics.Value("ThemeLoadMilliseconds", load.Elapsed.TotalMilliseconds); load.Restart();
        ViewModel = model; InitializeComponent(); DataContext = model;
        StartupMetrics.Value("WindowXamlMilliseconds", load.Elapsed.TotalMilliseconds); load.Restart();
        Icon = AppIcons.CreateWindowIcon();
        StartupMetrics.Value("WindowIconMilliseconds", load.Elapsed.TotalMilliseconds); load.Restart();
        model.PropertyChanged += Changed; model.ThemeChanged += ApplyTheme;
        SourceInitialized += (_, _) => SetNativeAppearance();
        ContentRendered += (_, _) => { StartupMetrics.Mark("FirstPaint"); };
        Loaded += async (_, _) => { StartupMetrics.Mark("FirstVisible"); await ViewModel.InitializeAsync(); };
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); } };
        StateChanged += (_, _) => { if (WindowState == WindowState.Minimized && ViewModel.MinimizeToTray) Hide(); };
        SystemEvents.UserPreferenceChanged += PreferenceChanged;
        ShowPage();
        StartupMetrics.Value("FirstPageMilliseconds", load.Elapsed.TotalMilliseconds);
    }
    private void Changed(object? sender, PropertyChangedEventArgs e) { if (e.PropertyName == nameof(PilotViewModel.Page)) ShowPage(); }
    private void ShowPage()
    {
        string page = ViewModel.Page;
        if (!pages.TryGetValue(page, out var view)) { view = page switch { "Rules" => new RulesView(), "Settings" => new SettingsView(), "Logs" => new LogsView(), "Setup" => new SetupView(), _ => new DashboardView() }; pages[page] = view; }
        PageHost.Content = view;
        NavOverview.IsChecked = page is "Dashboard" or "Setup"; NavRules.IsChecked = page == "Rules"; NavSettings.IsChecked = page == "Settings"; NavLogs.IsChecked = page == "Logs";
        if (SystemParameters.ClientAreaAnimation && IsVisible && AppController.TestRoot == null) PageHost.BeginAnimation(OpacityProperty, new DoubleAnimation(0.75, 1, TimeSpan.FromMilliseconds(140)) { FillBehavior = FillBehavior.Stop });
    }
    internal void ApplyTheme(string theme)
    {
        dark = theme == "Dark" || theme == "System" && IsSystemDark();
        string name = SystemParameters.HighContrast ? "HighContrast" : dark ? "Dark" : "Light";
        if (!themes.TryGetValue(name, out var dictionary)) { dictionary = new ResourceDictionary { Source = new Uri($"/WiFiProxySwitcher;component/Wpf/Tokens.{name}.xaml", UriKind.Relative) }; themes[name] = dictionary; }
        // Application-owned entries invalidate DynamicResource expressions in every cached page.
        foreach (System.Collections.DictionaryEntry token in dictionary) Application.Current.Resources[token.Key] = token.Value;
        SetNativeAppearance();
    }
    private static bool IsSystemDark() { using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"); return key?.GetValue("AppsUseLightTheme") is int value && value == 0; }
    private void PreferenceChanged(object sender, UserPreferenceChangedEventArgs e) { Dispatcher.BeginInvoke(() => { if (!exiting) ApplyTheme(ViewModel.Settings.Theme); }); }
    private void ThemeClick(object sender, RoutedEventArgs e) { ViewModel.Settings.Theme = dark ? "Light" : "Dark"; ApplyTheme(ViewModel.Settings.Theme); }
    private void SetNativeAppearance()
    {
        var hwnd = new WindowInteropHelper(this).Handle; if (hwnd == IntPtr.Zero) return;
        // Keep native frame metrics and default caption colors. The system owns sizing,
        // maximized bounds, resize borders, shadow and Snap hit testing at every DPI.
        int corners = 0, mode = dark && !SystemParameters.HighContrast ? 1 : 0;
        _ = DwmSetWindowAttribute(hwnd, 33, ref corners, sizeof(int));
        _ = DwmSetWindowAttribute(hwnd, 20, ref mode, sizeof(int));
    }
    internal void ExitWindow() { exiting = true; ViewModel.PropertyChanged -= Changed; ViewModel.ThemeChanged -= ApplyTheme; SystemEvents.UserPreferenceChanged -= PreferenceChanged; Close(); }
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
public partial class DashboardView : UserControl { public DashboardView() => InitializeComponent(); }
public partial class RulesView : UserControl { public RulesView() => InitializeComponent(); }
public partial class SettingsView : UserControl { public SettingsView() => InitializeComponent(); }
public partial class LogsView : UserControl { public LogsView() => InitializeComponent(); }
public partial class SetupView : UserControl { public SetupView() => InitializeComponent(); }
