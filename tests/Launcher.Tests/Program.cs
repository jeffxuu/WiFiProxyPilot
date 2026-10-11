using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using WiFiProxySwitcher.Core;

var results = new List<object>(); int failed = 0;
void Check(bool b) { if (!b) throw new Exception("Assertion failed"); }
void Reject(Action a) { bool rejected = false; try { a(); } catch { rejected = true; } Check(rejected); }
void Test(string name, Action a)
{
    try { a(); results.Add(new { Name = name, Passed = true, Error = "" }); Console.WriteLine("PASS " + name); }
    catch (Exception e) { failed++; results.Add(new { Name = name, Passed = false, Error = e.Message }); Console.WriteLine("FAIL " + name + ": " + e.Message); }
}
(MemoryStream Zip, MemoryStream Manifest) Archive(params (string Name, string Content)[] files)
{
    var zip = new MemoryStream(); var hashes = new Dictionary<string, string>();
    using (var z = new ZipArchive(zip, ZipArchiveMode.Create, true)) foreach (var f in files)
    { var b = Encoding.UTF8.GetBytes(f.Content); hashes[f.Name] = Convert.ToHexString(SHA256.HashData(b)); using var s = z.CreateEntry(f.Name).Open(); s.Write(b); }
    zip.Position = 0; return (zip, new MemoryStream(JsonSerializer.SerializeToUtf8Bytes(hashes)));
}
string temp = Path.Combine(Path.GetTempPath(), "WiFi 中文 space & ! [qa] " + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temp);
try
{
    Test("默认启动进入状态窗口路由", () => Check(Options.Parse([]).Command == "gui"));
    foreach (string command in new[] { "install", "uninstall", "restore", "status", "start", "stop", "check" })
        Test("参数调用 /" + command, () => Check(Options.Parse(["/" + command]).Command == command));
    Test("未知参数/矛盾选择/缺失参数拒绝", () => { Reject(() => Options.Parse(["/bad"])); Reject(() => Options.Parse(["/uninstall", "/force-restore", "/keep-current"])); Reject(() => Options.Parse(["/status", "/output"])); Reject(() => Options.Parse(["/start", "/force-restore"])); });
    Test("中文与空格安装路径不会拆分", () => Check(Options.Parse(["/install", "/install-dir", temp]).InstallDir == temp));
    Test("普通用户身份接受", () => IdentityRules.Validate("S-1-5-21-1-2-3-1001", "S-1-5-21-1-2-3-1001", 1));
    Test("同一 SID 的管理员身份仍绑定当前桌面", () => IdentityRules.Validate("S-1-5-21-1-2-3-1001", "S-1-5-21-1-2-3-1001", 2));
    Test("SYSTEM/Session0/借用另一管理员拒绝", () => { Reject(() => IdentityRules.Validate("S-1-5-18", "S-1-5-18", 1)); Reject(() => IdentityRules.Validate("A", "A", 0)); Reject(() => IdentityRules.Validate("ADMIN", "USER", 1)); });
    Test("隐藏进程且不用 Shell 或拼接命令", () => { var p = EngineProcess.Prepare("powershell.exe", Path.Combine(temp, "Control.ps1"), ["-InstallDir", @"C:\中文 & space!\dir", "-Quiet"]); Check(!p.UseShellExecute && p.CreateNoWindow && p.RedirectStandardError); Check(p.ArgumentList.Contains(@"C:\中文 & space!\dir")); Check(p.ArgumentList.Contains("-NoProfile")); });
    Test("完整嵌入包提取/哈希/释放", () => { var a = Archive(("Control.ps1", "中文"), ("lib/Core.ps1", "core")); string root; using (var p = new Payload(a.Zip, a.Manifest, temp)) { root = p.Root; p.Verify(); Check(File.ReadAllText(Path.Combine(p.Root, "Control.ps1")) == "中文"); } Check(!Directory.Exists(root)); });
    Test("重复安装使用独立提取目录且原包不变", () => { var a = Archive(("config.json", "Strict")); var b = Archive(("config.json", "Strict")); using var p = new Payload(a.Zip, a.Manifest, temp); using var q = new Payload(b.Zip, b.Manifest, temp); Check(p.Root != q.Root); Check(SafeFiles.Hash(Path.Combine(p.Root, "config.json")) == SafeFiles.Hash(Path.Combine(q.Root, "config.json"))); });
    Test("脚本在提取后被修改就拒绝执行", () => { var a = Archive(("Control.ps1", "safe")); using var p = new Payload(a.Zip, a.Manifest, temp); File.WriteAllText(Path.Combine(p.Root, "Control.ps1"), "changed"); Reject(p.Verify); });
    Test("ZIP 路径穿越/绝对路径/盘符拒绝", () => { foreach (var path in new[] { "../outside", "/root/file", "C:/file", "a\\file", "a//file" }) { var a = Archive((path, "bad")); Reject(() => { using var p = new Payload(a.Zip, a.Manifest, temp); }); } Check(!File.Exists(Path.Combine(temp, "outside"))); });
    Test("重复 ZIP 文件拒绝", () => { var a = Archive(("Control.ps1", "a"), ("Control.ps1", "b")); Reject(() => { using var p = new Payload(a.Zip, a.Manifest, temp); }); });
    Test("卸载冲突从引擎结构化结果保留", () => { var r = EngineProcess.ParseResult("{\"Succeeded\":false,\"Code\":\"RestoreConflict\",\"Message\":\"changed\"}", 20); Check(!r.Succeeded && r.Code == "RestoreConflict"); });
    Test("异常退出不伪报成功，允许下一次重试", () => { Reject(() => EngineProcess.ParseResult("{\"Succeeded\":true,\"Code\":\"\",\"Message\":\"\"}", 1)); Reject(() => EngineProcess.ParseResult("truncated", 1)); Check(EngineProcess.ParseResult("{\"Succeeded\":true,\"Code\":\"\",\"Message\":\"\"}", 0).Succeeded); });
    Test("安静卸载冲突必须返回给调用者，不自动覆盖", () => { var o = Options.Parse(["/uninstall", "/quiet"]); Check(o.Quiet && !o.Force && !o.Keep); });
}
finally { Directory.Delete(temp, true); }
var report = new { Platform = Environment.OSVersion.Platform.ToString(), Total = results.Count, Passed = results.Count - failed, Failed = failed, Results = results, WindowsIntegration = "NOT RUN: launcher boundary simulations" };
if (args.Length > 0) File.WriteAllText(args[0], JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"Launcher tests: {results.Count}, failed: {failed}"); return failed == 0 ? 0 : 1;
