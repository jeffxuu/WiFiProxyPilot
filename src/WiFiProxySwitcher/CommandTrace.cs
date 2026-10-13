using System.Text.Json;
using WiFiProxySwitcher.Core;

namespace WiFiProxySwitcher;

// Bounded technical trace: no SSIDs, proxy addresses, credentials, or script output.
internal static class CommandTrace
{
    private static readonly object Gate = new();
    internal static void Write(string operation, string stage, string code = "", string? requestId = null)
    {
        try
        {
            lock (Gate)
            {
                string directory = AppController.ControlDir;
                SafeFiles.PlainPath(directory); Directory.CreateDirectory(directory);
                string path = Path.Combine(directory, "commands.jsonl"); SafeFiles.PlainPath(path);
                if (File.Exists(path) && new FileInfo(path).Length > 512 * 1024)
                { SafeFiles.PlainPath(path + ".1"); File.Move(path, path + ".1", true); }
                File.AppendAllText(path, JsonSerializer.Serialize(new { Time = DateTimeOffset.Now, Operation = operation, Stage = stage, Code = code, RequestId = requestId }) + Environment.NewLine);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { System.Diagnostics.Trace.WriteLine("Command trace unavailable: " + error.GetType().Name); }
    }
}
