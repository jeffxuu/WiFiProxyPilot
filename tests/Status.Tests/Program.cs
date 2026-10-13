using System.Text.Json;
using System.Text.Json.Nodes;
using WiFiProxySwitcher;
using WiFiProxySwitcher.Core;

var results = new List<object>(); int failed = 0;
void Check(bool value) { if (!value) throw new Exception("Assertion failed"); }
void Test(string name, Action test)
{
    try { test(); results.Add(new { Name=name, Passed=true, Error="" }); Console.WriteLine("PASS "+name); }
    catch(Exception e) { failed++; results.Add(new { Name=name, Passed=false, Error=e.Message }); Console.WriteLine("FAIL "+name+": "+e.Message); }
}
string fixture=Path.GetFullPath(Path.Combine(Path.GetTempPath(), "WiFiStatus-"+Guid.NewGuid().ToString("N")));
Directory.CreateDirectory(Path.Combine(fixture,"state"));
JsonObject config=ConfigurationStore.CreateDefault();
config["ManagementIntent"]="Monitoring"; config["SetupComplete"]=true;
void SaveConfig() => File.WriteAllText(Path.Combine(fixture,"config.json"), config.ToJsonString());
string sha=new string('A',64);
JsonObject heartbeat=new()
{
    ["Time"]=DateTimeOffset.Now.ToString("o"),["EngineVersion"]="3.2.0-beta.1",["SchemaVersion"]=2,["Outcome"]="Enable",
    ["NetworkKind"]="Connected",["SSID"]="Test Hotspot",["Gateway"]="192.0.2.1",["InterfaceGuid"]="11111111-1111-1111-1111-111111111111",
    ["Stable"]=true,["ConfigRevision"]=sha,["AppliedRevision"]=sha,["Reason"]="当前 Wi-Fi 未命中免代理规则，使用其 IPv4 网关",
    ["Health"]="TcpOpen",["HealthCheckedAt"]=50.0,["ClockSeconds"]=52.0,["Diagnostics"]="Tcp",["PollSeconds"]=5,["DiagnosticIntervalSeconds"]=60
};
void SaveHeartbeat() => File.WriteAllText(Path.Combine(fixture,"state","status.json"), heartbeat.ToJsonString());
try
{
    AppController.TestRoot=fixture; SaveConfig(); SaveHeartbeat();
    Test("TCP 可达和代理开启独立，不宣称 HTTP 验证或互联网畅通",()=>
    {
        var s=StatusReader.Read(); Check(s.State==ApplicationState.Monitoring && s.ProxyEnabled && s.Network?.State==NetworkConnectionState.Connected);
        Check(s.Diagnostic?.State==ProxyDiagnosticState.TcpReachable && s.Health.Contains("尚未验证 HTTP"));
    });
    Test("暂停和直连保留当前网络读数及持久意图，直连外部开启代理仍显示真实代理",()=>
    {
        config["ManagementIntent"]="Paused"; SaveConfig(); heartbeat["Outcome"]="Paused"; SaveHeartbeat(); var paused=StatusReader.Read();
        Check(paused.State==ApplicationState.Paused && paused.Connected && paused.Ssid=="Test Hotspot" && paused.ProxyEnabled);
        config["ManagementIntent"]="Direct"; SaveConfig(); var direct=StatusReader.Read();
        Check(direct.State==ApplicationState.DirectMode && direct.ProxyEnabled && direct.Intent==ManagementIntent.Direct);
        config["ManagementIntent"]="Monitoring"; SaveConfig(); heartbeat["Outcome"]="Enable"; SaveHeartbeat();
    });
    Test("过期后台网络与诊断显式未知，保留上次时间",()=>
    {
        heartbeat["Time"]=DateTimeOffset.Now.AddMinutes(-5).ToString("o"); SaveHeartbeat(); var stale=StatusReader.Read();
        Check(stale.State==ApplicationState.Degraded && !stale.Fresh && !stale.Connected && stale.Network?.State==NetworkConnectionState.Unknown && stale.Diagnostic?.State==ProxyDiagnosticState.Unknown);
        Check(stale.Ssid=="暂时无法读取" && stale.Reason.Contains("上次成功检测"));
        heartbeat["Time"]=DateTimeOffset.Now.ToString("o"); SaveHeartbeat();
    });
    Test("旧引擎不能伪报新规则已应用",()=>
    {
        heartbeat.Remove("EngineVersion"); heartbeat.Remove("SchemaVersion"); SaveHeartbeat(); Check(StatusReader.Read().State==ApplicationState.UpgradeRequired);
        heartbeat["EngineVersion"]="3.2.0-beta.1"; heartbeat["SchemaVersion"]=2; SaveHeartbeat();
    });
    Test("读取失败保留上次成功时间且不把旧状态当实时",()=>
    {
        var successful=StatusReader.Read(); File.WriteAllText(Path.Combine(fixture,"state","status.json"),"{broken"); var failedRead=StatusReader.Read();
        Check(failedRead.State==ApplicationState.Degraded && !failedRead.Fresh && !failedRead.Healthy && !failedRead.Connected && failedRead.Updated==successful.Updated && failedRead.Reason.Contains("上次成功读取") && failedRead.Health.Contains("未知") && failedRead.ManualServer==""); SaveHeartbeat();
    });
    Test("未命中免代理的原因文本不会被误读为命中，新名单需等待后台稳定应用",()=>
    {
        config["Whitelist"]=new JsonArray("Test Hotspot"); SaveConfig();
        var pending=StatusReader.Read(); Check(pending.Rule.Contains("等待后台") && !pending.Rule.Contains("命中免代理"));
        heartbeat["ConfigRevision"]=ConfigurationStore.Read(fixture).Revision; heartbeat["AppliedRevision"]=ConfigurationStore.Read(fixture).Revision; SaveHeartbeat();
        Check(StatusReader.Read().Rule.Contains("命中免代理"));
        config["Whitelist"]=new JsonArray(); SaveConfig(); heartbeat["ConfigRevision"]=sha; heartbeat["AppliedRevision"]=sha; SaveHeartbeat();
    });
    Test("代理仍开启但地址被外部更改时不能伪报健康或沿用旧诊断",()=>
    {
        heartbeat["ActualServer"]="198.51.100.2:7890"; SaveHeartbeat();
        var changed=StatusReader.Read(); Check(changed.State==ApplicationState.Degraded && !changed.Healthy && changed.Diagnostic?.State==ProxyDiagnosticState.Unknown && changed.Reason.Contains("外部"));
        heartbeat.Remove("ActualServer"); SaveHeartbeat();
    });
    Test("常规刷新不读日志，日志按需只取近期有界内容",()=>
    {
        Directory.CreateDirectory(Path.Combine(fixture,"logs")); string path=Path.Combine(fixture,"logs","watcher.jsonl");
        using(var writer=File.CreateText(path)) for(int i=0;i<120;i++) writer.WriteLine(JsonSerializer.Serialize(new {Time=DateTimeOffset.Now.ToString("o"),Level="INFO",Message="isolated "+i}));
        Check(StatusReader.Read().Logs==""); string tail=StatusReader.Logs(fixture); Check(tail.Contains("isolated 119") && !tail.Contains("isolated 0"));
    });
    Test("未完成首次配置保持 SetupRequired，不以运行中替代确认",()=>
    {
        config["SetupComplete"]=false; config["ManagementIntent"]="Paused"; SaveConfig(); Check(StatusReader.Read().State==ApplicationState.SetupRequired);
    });
}
finally
{
    AppController.TestRoot=null;
    string parent=Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
    if(!fixture.StartsWith(parent,StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(fixture).StartsWith("WiFiStatus-",StringComparison.Ordinal)) throw new IOException("Refuse fixture cleanup outside owned temp directory");
    SafeFiles.PlainPath(fixture); Directory.Delete(fixture,true);
}
if(args.Length>0) File.WriteAllText(args[0],JsonSerializer.Serialize(new {Total=results.Count,Passed=results.Count-failed,Failed=failed,Results=results,WindowsIntegration="NOT RUN: isolated production status reader with forbidden Windows boundaries"},new JsonSerializerOptions{WriteIndented=true}));
Console.WriteLine($"Status tests: {results.Count}, failed: {failed}"); return failed==0?0:1;
