# v3.0.0 架构与构建

```text
WiFiProxySwitcher.exe (.NET 8 WinForms, self-contained win-x64)
  ├─ 状态窗口：读取引擎心跳、当前 HKCU 手动值、最近有界日志
  ├─ 校验并提取内嵌脚本（SHA256、容量/路径限制）
  └─ ProcessStartInfo.ArgumentList + CreateNoWindow + UseShellExecute=false
       └─ Windows PowerShell 5.1 → 原 Control.ps1 / Diagnose.ps1
            ├─ 原安装、备份、恢复冲突、任务与单实例保护
            ├─ Desktop.ps1：版本目录 EXE、开始菜单、当前用户卸载项
            └─ 登录任务（当前 SID / Interactive / Limited）
                 └─ 原 SilentLauncher.vbs → 原 ProxyWatcher.ps1
```

SSID、接口/网关、WinINet、Strict/Safe、日志及状态机仍由现有引擎负责。只为立即检测添加 check.request 唤醒信号；分段等待和防抖仍生效。C# 不复制网络决策。默认窗口不会注册 GUI 登录弹出；后台任务沿用隐藏 VBS。

EXE 采用 asInvoker，允许用户第一次显式右键管理员运行；不自动索要提权。同用户提权和普通用户都必须匹配当前 WTS 桌面会话 SID，拒绝 SYSTEM、Session 0 和借用其他管理员账户。原引擎还有独立 SID/任务归属检查。

安装：脚本包提取到当前用户 Control 缓存，核验每个文件后调用原安装流程。桌面 EXE 安装到 `app/3.0.0-<哈希前缀>/`，不覆盖正在运行的旧版本。单独桌面清单按当前 SID、根目录、相对路径与哈希限制清理范围。用户配置和首次代理备份保留。

卸载：先交给有界临时卸载器，原窗口退出释放 EXE 文件锁。工作进程调用原恢复/卸载函数，冲突通过机器可读 RestoreConflict 返回。用户选择后再继续；未知错误不作为成功。文件锁或后续清理失败保留桌面清单/卸载记录供重试。默认保留日志、空目录、下载的源 EXE 与用户修改文件。

## 命令

```text
WiFiProxySwitcher.exe                 状态窗口；尚无桌面安装时自动安装
WiFiProxySwitcher.exe /install
WiFiProxySwitcher.exe /install /install-dir "D:\我的工具\WiFi 代理"
WiFiProxySwitcher.exe /status /output "%LOCALAPPDATA%\WiFiProxySwitcher\state\desktop-status.json"
WiFiProxySwitcher.exe /start
WiFiProxySwitcher.exe /stop
WiFiProxySwitcher.exe /check
WiFiProxySwitcher.exe /restore
WiFiProxySwitcher.exe /uninstall
```

支持 `/quiet`。恢复/卸载可显式 `/force-restore`，卸载可 `/keep-current`，两者互斥。静默冲突不弹窗、不自动覆盖，记录 RestoreConflict。退出码：0 完成；1 错误；20 代理恢复冲突；10 卸载已交给工作进程，最终结果见 Control/uninstall-result.json。GUI 子系统在命令模式尝试附加调用者终端，`/status /output` 是自动化保存完整输出的可靠方式。`/self-test` 仅供 CI：创建/绘制窗口并检查内嵌包，不安装或写代理。

## 构建

开发端需要 .NET SDK 8.0.425（Windows 用户运行 EXE 不需要 SDK 或 .NET 安装）。

```powershell
New-Item -ItemType Directory -Force release/generated | Out-Null
powershell.exe -NoProfile -File tests/Run-Tests.ps1 -ResultPath release/generated/engine-results.json
pwsh -NoProfile -File release/Build.ps1
```

Build.ps1 构造可核验的内嵌包，运行跨平台 C# 启动器测试，再执行 self-contained/single-file win-x64 publish。输出 `publish/self-contained/win-x64/WiFiProxySwitcher.exe` 与 `release/dist/{WiFiProxySwitcher.exe,WiFiProxySwitcher.zip,SHA256.txt}`。Linux 使用 pwsh 7 作编译/模拟，不能执行 Windows EXE。`-SkipTests` 只供已运行测试后的构建迭代；发布工作流必须运行全部测试。

GitHub Actions 在 feature/exe-productization 推送时构建、运行 Windows PowerShell 5.1 回归与 EXE/WinForms 冒烟。v3.0.0 tag 才创建 Release 并上传三个文件，任何失败阻止发布，不覆盖已有 tag/release。工作流把执行证据写回该开发分支的 release/ci-latest.json，receipt 的 SourceCommit 指向被验证提交；网络 UI/安装系统集成仍需本机验收。

程序集和 EXE 未 Authenticode 签名。打包 .NET 并非绕过执行策略：企业禁止 WSH、PowerShell、Add-Type、任务或 EXE 时仍会明确失败。没有关闭防火墙、DNS、防病毒或永久调整执行策略。HKCU 新增的桌面卸载项和开始菜单入口仅服务于本产品安装/卸载。
