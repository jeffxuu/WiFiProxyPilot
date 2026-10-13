using System.Drawing;
using System.Windows.Media.Imaging;

namespace WiFiProxySwitcher;

internal enum TrayIconState { Brand, Monitoring, Direct, Paused, Attention }

// The executable, window and tray use the same SVG-derived multi-resolution assets.
// Loading a small embedded ICO avoids Shell extraction of the self-contained EXE.
internal static class AppIcons
{
    internal static Icon Create(TrayIconState state = TrayIconState.Brand)
    {
        using var stream = Open(state);
        using var asset = new Icon(stream);
        return new Icon(asset, System.Windows.Forms.SystemInformation.SmallIconSize);
    }

    internal static BitmapFrame CreateWindowIcon()
    {
        using var stream = Open(TrayIconState.Brand);
        var frame = BitmapFrame.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        frame.Freeze();
        return frame;
    }

    private static Stream Open(TrayIconState state) => typeof(AppIcons).Assembly.GetManifestResourceStream($"WiFiProxyPilot.Icon.{state}.ico")
        ?? throw new InvalidOperationException($"Missing application icon: {state}");
}
