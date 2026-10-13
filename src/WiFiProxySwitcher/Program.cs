using System.Text;
using System.Text.Json;
using WiFiProxySwitcher.Core;
using System.Windows.Forms;

namespace WiFiProxySwitcher;
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        StartupMetrics.Mark("ManagedEntry");
        bool quiet = args.Contains("/quiet", StringComparer.OrdinalIgnoreCase);
        try
        {
            Options options = Options.Parse(args);
            if (options.Command is "benchmark" or "preview")
            {
                if (options.Output == null) throw new ArgumentException("隔离运行需要 /output 指定报告路径");
                AppController.TestRoot = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(options.Output))!, "fixture");
            }
            StartupMetrics.Mark("ManagedEntry");
            ApplicationConfiguration.Initialize();
            if (options.Command == "self-test") return SelfTest(options);
            if (options.Command == "ui-review") return DesktopVerification.RunHomeReview(options);
            SessionGuard.Validate();
            if (options.Command is "gui" or "tray" or "benchmark" or "preview")
            {
                using var instance = new SingleInstance();
                if (!instance.Primary) return 0;
                if (options.Command is "benchmark" or "preview") { StartupMetrics.Output = Path.GetFullPath(options.Output!); Directory.CreateDirectory(Path.GetDirectoryName(StartupMetrics.Output)!); DesktopVerification.CreateFixture(AppController.TestRoot!); StartupMetrics.Mark("ManagedEntry"); }
                using var app = new AppController();
                var desktop = new System.Windows.Application { ShutdownMode = System.Windows.ShutdownMode.OnExplicitShutdown };
                SynchronizationContext.SetSynchronizationContext(new System.Windows.Threading.DispatcherSynchronizationContext(desktop.Dispatcher));
                using var context = new PilotTrayHost(app, options.Command == "tray", instance.Activation, instance.ExitRequest);
                if (options.Command == "benchmark") DesktopVerification.AttachBenchmark(context);
                desktop.Run(); return 0;
            }
            using var controller = new AppController();
            SessionGuard.AttachConsole(uint.MaxValue); Console.OutputEncoding = new UTF8Encoding(false);
            if (options.Command == "status")
            {
                var result = controller.Diagnostic(options.Output).GetAwaiter().GetResult(); Console.WriteLine(result.Json); return result.Code;
            }
            if (options.Command == "uninstall" && options.WorkerPid == 0)
            {
                controller.BeginUninstall(options);
                Console.WriteLine(JsonSerializer.Serialize(new { Succeeded = false, Code = "UninstallStarted", Message = "卸载程序已启动；最终结果见 WiFiProxySwitcher-Control/uninstall-result.json。" }));
                return 10; // Handoff accepted, not a claim that restoration/deletion already succeeded.
            }
            if (options.WorkerPid != 0) { AppController.WaitForParent(options); SingleInstance.RequestExitAndWait(); }
            var r = controller.Execute(options).GetAwaiter().GetResult();
            if (r.Code == "RestoreConflict" && !options.Quiet)
            {
                var answer = MessageBox.Show("检测到后续手动代理修改。\n\n“是”：恢复安装前配置。\n“否”：保留当前配置（卸载时继续卸载）。\n“取消”：保留安装与备份。", "代理配置冲突", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
                if (answer == DialogResult.Yes) r = controller.Execute(options with { Force = true }).GetAwaiter().GetResult();
                else if (answer == DialogResult.No && options.Command == "uninstall") r = controller.Execute(options with { Keep = true }).GetAwaiter().GetResult();
            }
            Console.WriteLine(JsonSerializer.Serialize(r));
            if (options.WorkerPid != 0) File.WriteAllText(Path.Combine(AppController.ControlDir, "uninstall-result.json"), JsonSerializer.Serialize(r));
            if (!options.Quiet) MessageBox.Show(r.Succeeded ? "操作完成。" : r.Message, "WiFi Proxy Pilot", MessageBoxButtons.OK, r.Succeeded ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
            return r.Succeeded ? 0 : r.Code == "RestoreConflict" ? 20 : 1;
        }
        catch (Exception ex)
        {
            try
            {
                string dir = AppController.ControlDir; SafeFiles.PlainPath(dir); Directory.CreateDirectory(dir); string path = Path.Combine(dir, "desktop-errors.log");
                if (File.Exists(path) && new FileInfo(path).Length > 262144) File.Move(path, path + ".1", true);
                File.AppendAllText(path, DateTimeOffset.Now.ToString("o") + " " + ex + Environment.NewLine, Encoding.UTF8);
                if (args.Contains("/worker", StringComparer.OrdinalIgnoreCase))
                    File.WriteAllText(Path.Combine(dir, "uninstall-result.json"), JsonSerializer.Serialize(new { Succeeded = false, Code = "WorkerFailed", Message = ex.Message }));
            }
            catch (Exception logError) { Console.Error.WriteLine("日志写入失败: " + logError.Message); }
            Console.Error.WriteLine(ex.Message);
            if (!quiet) MessageBox.Show(ex.Message, "WiFi Proxy Pilot", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
    private static int SelfTest(Options options)
    {
        return DesktopVerification.Run(options);
    }
}
