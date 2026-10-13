using System.Diagnostics;
using System.Text.Json;

namespace WiFiProxySwitcher;
internal static class StartupMetrics
{
    private static readonly Stopwatch Clock = Stopwatch.StartNew();
    private static readonly double EntryMs = (DateTime.UtcNow - Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds;
    private static readonly Dictionary<string, object> Data = new();
    private static readonly object Gate = new();
    internal static string? Output { get; set; }
    internal static void Mark(string stage) { lock (Gate) { if (stage == "Reopened" || !Data.ContainsKey(stage)) Data[stage] = EntryMs + Clock.Elapsed.TotalMilliseconds; Write(); } }
    internal static void Value(string name, object value) { lock (Gate) { Data[name] = value; Write(); } }
    private static void Write()
    {
        if (Output == null) return;
        string temp = Output + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(Data, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, Output, true);
    }
}
