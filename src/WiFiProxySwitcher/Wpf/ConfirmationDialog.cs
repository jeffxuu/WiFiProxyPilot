using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;

namespace WiFiProxySwitcher;

// Native Windows frame with application-localized content and action labels. CLI callers
// can show this STA dialog without creating a second Application or borrowing another user's UI.
internal static class ConfirmationDialog
{
    internal static bool Confirm(string title, string text) => Show(title, text,
        [("Continue", MessageBoxResult.OK, "ConfirmAccept"), ("Cancel", MessageBoxResult.Cancel, "ConfirmCancel")]) == MessageBoxResult.OK;
    internal static void Alert(string text, string title, bool warning = false) => Show(title, text,
        [("CloseDialog", MessageBoxResult.OK, "AlertClose")]);
    internal static MessageBoxResult RestoreChoice(string text, string title) => Show(title, text,
        [("RestoreOriginalChoice", MessageBoxResult.Yes, "RestoreOriginal"), ("KeepCurrentChoice", MessageBoxResult.No, "KeepCurrent"), ("Cancel", MessageBoxResult.Cancel, "ConfirmCancel")]);

    private static MessageBoxResult Show(string title, string text, (string Key, MessageBoxResult Result, string Id)[] choices)
    {
        var owner = Application.Current?.Windows.OfType<PilotWindow>().FirstOrDefault(window => window.IsVisible);
        var dialog = new Window
        {
            Title = title, Width = choices.Length > 2 ? 610 : 540, MinHeight = 190, MaxHeight = 720,
            SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStyle = WindowStyle.SingleBorderWindow,
            WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
            ShowInTaskbar = owner == null, FontFamily = new FontFamily("Segoe UI"), FontSize = 14,
            UseLayoutRounding = true, Icon = AppIcons.CreateWindowIcon(), Owner = owner
        };
        System.Windows.Automation.AutomationProperties.SetAutomationId(dialog, "PilotConfirmationDialog");
        if (Application.Current?.Resources.Contains("Canvas") == true) dialog.SetResourceReference(Window.BackgroundProperty, "Canvas");
        if (Application.Current?.Resources.Contains("Ink") == true) dialog.SetResourceReference(Window.ForegroundProperty, "Ink");
        var content = new DockPanel { Margin = new Thickness(24) };
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 20, 0, 0) };
        DockPanel.SetDock(actions, Dock.Bottom); content.Children.Add(actions);
        var body = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, LineHeight = 22 };
        content.Children.Add(new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = 560 });
        dialog.Content = content;
        MessageBoxResult result = MessageBoxResult.Cancel;
        foreach (var choice in choices)
        {
            var button = new Button { MinWidth = 100, MinHeight = 32, Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(8, 0, 0, 0), IsCancel = choice.Result == MessageBoxResult.Cancel };
            button.SetBinding(ContentControl.ContentProperty, new Binding("[" + choice.Key + "]") { Source = Localization.Current });
            System.Windows.Automation.AutomationProperties.SetAutomationId(button, choice.Id);
            button.Click += (_, _) => { result = choice.Result; if (choice.Result != MessageBoxResult.Cancel) dialog.DialogResult = true; };
            // Enter defaults to cancellation for a recovery conflict; restoration needs a deliberate choice.
            button.IsDefault = choices.Length == 1 || choices.Length > 2 && choice.Result == MessageBoxResult.Cancel;
            actions.Children.Add(button);
        }
        dialog.ShowDialog();
        return result;
    }
}
