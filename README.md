# Wi-Fi 智能代理切换 v3.1.0

Windows 11 x64 桌面应用，包含所需 .NET 8 运行时。普通用户只需要 `WiFiProxySwitcher.exe`，无需安装 .NET SDK、Python、Node.js 或 WebView2。

**当前为待真实网络验收的候选版本。** 本轮仅进行了单元、模拟网络及隔离 Windows 桌面验证；没有升级开发机器上的安装或改动其代理、任务、DNS、路由、防火墙。v3.0.0 Release 保持原样。

## 安装与升级

1. 从本仓库新功能分支的 Windows Actions 构建产物下载 EXE 或 ZIP，核对 `SHA256.txt`。
2. 在自己的 Windows 桌面账户运行 EXE。首次打开先显示界面，不会擅自安装或改代理。
3. 首次使用点击“开启自动切换（安装）”；已有 v3.0.0 安装则打开“设置 → 高级操作 → 修复安装 / 升级”。确认后安装当前用户的后台监控、登录任务与托盘入口。
4. 默认安装位置为 `%LOCALAPPDATA%\WiFiProxySwitcher`。升级会复用已登记的安装目录，保留 `config.json` 和 `state\proxy-before-install.json` 中最初的手动代理备份。**请勿先卸载旧版，也不要用发行包的默认 JSON 覆盖自己的配置。**

旧引擎需要完成一次升级才能支持热更新和暂停命令。仅打开新 EXE 不会静默替换仍在运行的旧 Watcher；界面会明确提示。

## 日常使用

- **概览**：自动切换状态、Wi-Fi、IPv4 网关、Windows 手动代理、当前规则、最近检测及代理诊断。长文本悬停查看，接口 GUID 放在详细信息中。
- **免代理 Wi-Fi**：输入完整名称，或从已确认的当前真实 SSID 添加，然后“保存并应用”。删除仅针对自定义项。“取消修改 / 重新载入”放弃未保存的草稿。
- **设置**：监控登录自启、托盘登录自启、X 隐藏到托盘、可选最小化到托盘，以及 Strict/Safe、端口、轮询和诊断。
- **日志与诊断**：本地可读时间、警告/错误过滤、复制诊断、打开日志目录。原始 JSON 为可选高级视图。

`MC-Office` 和 `Meituan` 永远免代理。自定义项完整精确匹配、忽略大小写；合法空格原样保留，UTF-8 名称限制为 1–32 字节。连接其他 Wi-Fi 使用当前物理无线接口的 IPv4 网关和端口（默认 7890），绕过列表包含 `<local>`。SSID/网关无法确认时保留当前配置；确认断开后按原确认时序关闭手动代理。

## 托盘操作

X 默认隐藏窗口；后台监控和托盘继续运行。双击托盘或再次启动 EXE 打开原窗口。

“暂停自动切换”保留当前手动代理，并保留独立监控进程及登录偏好；不会宣称恢复直连。“退出界面（后台监控继续）”只退出 GUI/托盘。“停止监控并恢复代理”必须确认，沿用最初备份和后续修改冲突保护。卸载在设置的高级操作或 Windows 已安装应用中进行；后台未安全停止时拒绝恢复。

托盘颜色：蓝色为按规则开启代理，绿色为按规则关闭代理，灰色为无 Wi-Fi，橙色为识别/代理异常，石板灰为暂停或未运行。**代理开启不代表代理服务可用；TCP 开放也不代表 HTTP 代理可用。** 保留 PAC/自动检测设置及其提示。

## 开发与验证

维护者需要 .NET 8 SDK；发行版用户不需要。PowerShell 引擎继续兼容 Windows PowerShell 5.1。

```powershell
powershell.exe -NoProfile -File tests/Run-Tests.ps1 -ResultPath engine-results.json
dotnet run --project tests/Launcher.Tests --configuration Release -- launcher-results.json
powershell.exe -NoProfile -File release/Build.ps1
release/dist/WiFiProxySwitcher.exe /self-test /output smoke.json
powershell.exe -NoProfile -File tools/Measure-Startup.ps1 -Exe release/dist/WiFiProxySwitcher.exe
```

`/self-test` 和 `/benchmark` 创建隔离 fixture，禁止执行安装、代理或任务写入。常规 CLI 继续支持 `/install /start /stop /check /restore /status /uninstall /quiet`，新增 `/tray /pause /resume /settings`。`/stop` 沿用旧语义：停止监控并禁用监控登录任务，保留代理；与界面“暂停”不同。

详见 [UI 设计](docs/UI_DESIGN_V3_1.md)、[托盘生命周期](docs/TRAY_LIFECYCLE.md)、[配置热更新](docs/CONFIG_HOT_RELOAD.md)、[启动性能](docs/STARTUP_PERFORMANCE.md)、[验证记录](docs/TEST_RESULTS_V3_1.md)、[实际变更](docs/CHANGES_V3_1.md)。原始网络架构与高级恢复说明继续保留在 `docs/ARCHITECTURE.md` 和 `docs/ADVANCED_USAGE.md`。
