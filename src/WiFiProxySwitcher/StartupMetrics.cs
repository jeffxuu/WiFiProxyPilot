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
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(Data, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temp, Output, true);
        }
        catch (IOException)
        {
            // Diagnostic collection must never break payload verification or the UI lifecycle.
            Data["MetricsWriteFailures"] = Data.TryGetValue("MetricsWriteFailures", out var count) ? Convert.ToInt32(count) + 1 : 1;
        }
    }
}
