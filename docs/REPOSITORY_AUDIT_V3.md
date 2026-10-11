# v3.0.0 产品化开始前审计

2026-10-12（Asia/Shanghai），从 `https://github.com/jeffxuu/WiFi-test.git` 克隆到临时只读审计目录；实际修改继续在原仓库工作目录，没有另建产品或重写网络引擎。

- 远端默认分支 `main`：`38799dcad92646ad11b6c2f3f1fc6afc2808bd95`（Initial commit）。
- 远端最新完整功能分支 `codex/wifi-proxy-round2`：`6895faa4b5c64aa191d4e519d3fdd3f6ca1dc95c`。
- 从该完整功能提交创建 `feature/exe-productization`；未修改 main。
- 修改前实际运行 `bash tools/cloud-setup.sh`：95 项通过、0 失败，Linux PowerShell 7.4.6；不代表 Windows 系统集成通过。

审计时的完整项目分组：

```text
Control.ps1  ProxyWatcher.ps1  Diagnose.ps1  SilentLauncher.vbs  config.json
Install.bat  Start.bat  Stop.bat  Uninstall.bat  RestoreProxy.bat  Status.bat  Diagnose.bat
lib/       Core.ps1 Windows.ps1 Native.cs Monitor.ps1 Lifecycle.ps1
tests/     Run-Tests.ps1 Run-Tests.bat Round2.Tests.ps1 TaskOwnership.Tests.ps1 ProbeServer.cs
docs/      ARCHITECTURE.md REVIEW_ROUND2.md TASK_OWNERSHIP_FIX.md
           TEST_RESULTS.md test-results.json WINDOWS_ACCEPTANCE.md
tools/     cloud-setup.sh
README.md .gitattributes .gitignore
```

新的桌面层调用原 Control.ps1；网络决策仍在上述 PowerShell/C# Native 引擎。BAT 移到 tools 后，旧安装清单里的根 BAT 归属继续保留，卸载仍可按哈希清理。
