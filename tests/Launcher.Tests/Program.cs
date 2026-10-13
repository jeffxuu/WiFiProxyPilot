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
    Test("V31 托盘/暂停/恢复/设置/隔离测量参数", () => { foreach (var command in new[] { "tray", "pause", "resume", "settings" }) Check(Options.Parse(["/" + command]).Command == command); Check(Options.Parse(["/benchmark", "/output", "x.json"]).Output == "x.json"); });
    Test("V31 内容寻址缓存命中仍完整验证且不重复解压", () => { string cache = Path.Combine(temp, "cache-hit"); var a = Archive(("Control.ps1", "safe")); var p = new PayloadCache(a.Zip, a.Manifest, cache, "3.1.0"); Check(!p.Hit); var b = Archive(("Control.ps1", "safe")); var q = new PayloadCache(b.Zip, b.Manifest, cache, "3.1.0"); Check(q.Hit && q.Root == p.Root && q.ExtractMilliseconds == 0); q.Verify(); });
    Test("V31 修改缓存必须拒绝执行，再打开安全重建", () => { string cache = Path.Combine(temp, "cache-bad"); var a = Archive(("Control.ps1", "safe")); var p = new PayloadCache(a.Zip, a.Manifest, cache, "3.1.0"); File.WriteAllText(Path.Combine(p.Root, "Control.ps1"), "changed"); Reject(p.Verify); var b = Archive(("Control.ps1", "safe")); var q = new PayloadCache(b.Zip, b.Manifest, cache, "3.1.0"); Check(!q.Hit && File.ReadAllText(Path.Combine(q.Root, "Control.ps1")) == "safe"); });
    Test("V31 缓存未知内容被拒绝并隔离", () => { string cache = Path.Combine(temp, "cache-extra"); var a = Archive(("Control.ps1", "safe")); var p = new PayloadCache(a.Zip, a.Manifest, cache, "3.1.0"); File.WriteAllText(Path.Combine(p.Root, "extra.ps1"), "unsafe"); Reject(p.Verify); var b = Archive(("Control.ps1", "safe")); var q = new PayloadCache(b.Zip, b.Manifest, cache, "3.1.0"); Check(!q.Hit && !File.Exists(Path.Combine(q.Root, "extra.ps1"))); });
    Test("V31 更新版本与清单不复用旧脚本", () => { string cache = Path.Combine(temp, "cache-version"); var a = Archive(("Control.ps1", "old")); var p = new PayloadCache(a.Zip, a.Manifest, cache, "3.0.0"); var b = Archive(("Control.ps1", "new")); var q = new PayloadCache(b.Zip, b.Manifest, cache, "3.1.0"); Check(p.Root != q.Root && File.ReadAllText(Path.Combine(p.Root, "Control.ps1")) == "old"); });
    Test("V31 普通/中文/含空格 SSID 保持原样", () => { foreach (var ssid in new[] { "XiaoMi", "中文网络", " Office ", " ", "a\"b\\c" }) Check(ConfigurationStore.ValidateSsid(ssid) == ssid); });
    Test("V31 空/控制字符/过长 UTF-8/无效 Unicode 拒绝", () => { foreach (var name in new[] { "", "x\nx", new string('a',33), new string('中',11), "\ud800" }) Reject(() => ConfigurationStore.ValidateSsid(name)); Check(ConfigurationStore.ValidateSsid(new string('a',32)).Length == 32); });
    Test("V31 内置保护与 OrdinalIgnoreCase 去重，子串不匹配", () => { var names = ConfigurationStore.Normalize(["xiaomi", "XiaoMi", "meituan", "Meituan-Guest", " Meituan"]); Check(names.Length == 5 && names[0] == "MC-Office" && names.Contains("Meituan-Guest") && names.Contains(" Meituan")); });
    string fixture = Path.Combine(temp, "config"); Directory.CreateDirectory(fixture);
    File.Copy(Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../config.json")), Path.Combine(fixture,"config.json"));
    Test("V31 配置原子保存保留未知字段、Port/Mode/诊断与有效上一份", () => { var original=ConfigurationStore.Read(fixture); var draft=(System.Text.Json.Nodes.JsonObject)original.Values.DeepClone(); draft["CustomFutureField"]="keep"; draft["Whitelist"]=new System.Text.Json.Nodes.JsonArray("XiaoMi","中文", " Office "); var saved=ConfigurationStore.Save(fixture,original,draft); Check(saved.Whitelist.Contains("MC-Office") && saved.Whitelist.Contains("XiaoMi") && saved.Values["Port"]!.GetValue<int>()==7890 && saved.Values["CustomFutureField"]!.GetValue<string>()=="keep"); Check(File.Exists(Path.Combine(fixture,"config.json.previous"))); Check(!Directory.EnumerateFiles(fixture,"*.tmp.*").Any()); });
    Test("V31 删除自定义规则且内置规则仍受保护", () => { var original=ConfigurationStore.Read(fixture); var draft=(System.Text.Json.Nodes.JsonObject)original.Values.DeepClone(); draft["Whitelist"]=new System.Text.Json.Nodes.JsonArray(); var saved=ConfigurationStore.Save(fixture,original,draft); Check(saved.Whitelist.SequenceEqual(ConfigurationStore.BuiltIns)); });
    Test("V31 JSON 输入正确序列化而非配置注入", () => { var original=ConfigurationStore.Read(fixture); var draft=(System.Text.Json.Nodes.JsonObject)original.Values.DeepClone(); draft["Whitelist"]=new System.Text.Json.Nodes.JsonArray("x\",\"Port\":1"); ConfigurationStore.Save(fixture,original,draft); var result=ConfigurationStore.Read(fixture); Check(result.Values["Port"]!.GetValue<int>()==7890 && result.Whitelist.Contains("x\",\"Port\":1")); });
    Test("V31 并发编辑拒绝过期稿件，不覆盖外部修改", () => { var first=ConfigurationStore.Read(fixture); var second=ConfigurationStore.Read(fixture); var draft=(System.Text.Json.Nodes.JsonObject)first.Values.DeepClone(); draft["Port"]=9999; var saved=ConfigurationStore.Save(fixture,first,draft); Reject(()=>ConfigurationStore.Save(fixture,second,second.Values)); Check(ConfigurationStore.Read(fixture).Revision==saved.Revision); });
    Test("V31 连续快速保存后重新读取最终有效名单", () => { for(int i=0;i<25;i++){var old=ConfigurationStore.Read(fixture);var d=(System.Text.Json.Nodes.JsonObject)old.Values.DeepClone();d["Whitelist"]=new System.Text.Json.Nodes.JsonArray("SSID-"+i);ConfigurationStore.Save(fixture,old,d);} Check(ConfigurationStore.Read(fixture).Whitelist.Contains("SSID-24")); });
    Test("V31 验证失败及孤立临时文件不损坏当前配置", () => { var original=ConfigurationStore.Read(fixture); var draft=(System.Text.Json.Nodes.JsonObject)original.Values.DeepClone(); draft["Mode"]="Safe"; draft["Diagnostics"]="None"; Reject(()=>ConfigurationStore.Save(fixture,original,draft)); File.WriteAllText(Path.Combine(fixture,"config.json.tmp.interrupted"),"{truncated"); Check(ConfigurationStore.Read(fixture).Revision==original.Revision); });
    Test("V31 重复 JSON 字段拒绝", () => { string p=Path.Combine(fixture,"config.json");string old=File.ReadAllText(p);try{File.WriteAllText(p,old.Replace("\"Port\": 9999","\"Port\": 9999, \"Port\": 1"));Reject(()=>ConfigurationStore.Read(fixture));}finally{File.WriteAllText(p,old);} });
}
finally { Directory.Delete(temp, true); }
var report = new { Platform = Environment.OSVersion.Platform.ToString(), Total = results.Count, Passed = results.Count - failed, Failed = failed, Results = results, WindowsIntegration = "NOT RUN: launcher boundary simulations" };
if (args.Length > 0) File.WriteAllText(args[0], JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"Launcher tests: {results.Count}, failed: {failed}"); return failed == 0 ? 0 : 1;
