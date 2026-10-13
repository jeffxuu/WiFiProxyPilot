using System.Drawing;
using System.Runtime.InteropServices;
namespace WiFiProxySwitcher;
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
