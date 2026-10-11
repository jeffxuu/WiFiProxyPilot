# v3.0.0 文件变更

所有产品化变更在 feature/exe-productization，main 未修改。

- src/WiFiProxySwitcher：WinForms、命令入口、会话校验、引擎调用、状态读取及卸载交接。
- src/WiFiProxySwitcher.Core：跨平台参数/身份规则、包提取校验、进程与结果契约。
- lib/Desktop.ps1 与 Control.ps1：桌面安装/卸载、机器可读结果；其余网络决策留在原引擎。
- lib/Monitor.ps1、ProxyWatcher.ps1：增加立即检测请求，保留防抖与状态机。
- tools：迁移维护 BAT，保留旧安装清单的卸载归属。
- tests：保留原95项，新增8项PowerShell与22项C#测试；修复真实5.1测试编译参数兼容性。
- release、.github/workflows：自包含打包、校验值、Windows门禁、Release及证据回传。
- README/docs：面向普通用户的入口、架构、审计、测试与实机验收。

`lib/Core.ps1`、`lib/Windows.ps1`、`lib/Native.cs` 相对原提交 6895faa 无代码变更。

```text
A	.github/workflows/release.yml
M	.gitignore
M	Control.ps1
M	ProxyWatcher.ps1
M	README.md
A	docs/ADVANCED_USAGE.md
A	docs/PRODUCTIZATION.md
A	docs/PRODUCT_TEST_RESULTS.md
A	docs/PRODUCT_WINDOWS_ACCEPTANCE.md
A	docs/REPOSITORY_AUDIT_V3.md
A	docs/product-engine-tests.json
A	docs/product-launcher-tests.json
A	lib/Desktop.ps1
M	lib/Lifecycle.ps1
M	lib/Monitor.ps1
A	release/Build.ps1
A	release/NOTES-v3.0.0.md
A	release/ci-latest.json
A	release/ci-ui.png
A	src/WiFiProxySwitcher.Core/Launcher.cs
A	src/WiFiProxySwitcher.Core/WiFiProxySwitcher.Core.csproj
A	src/WiFiProxySwitcher/AppController.cs
A	src/WiFiProxySwitcher/MainForm.cs
A	src/WiFiProxySwitcher/Program.cs
A	src/WiFiProxySwitcher/SessionGuard.cs
A	src/WiFiProxySwitcher/StatusReader.cs
A	src/WiFiProxySwitcher/WiFiProxySwitcher.csproj
A	src/WiFiProxySwitcher/app.manifest
A	tests/Launcher.Tests/Launcher.Tests.csproj
A	tests/Launcher.Tests/Program.cs
A	tests/Productization.Tests.ps1
M	tests/Run-Tests.ps1
R094	Diagnose.bat	tools/Diagnose.bat
R091	Install.bat	tools/Install.bat
R091	RestoreProxy.bat	tools/RestoreProxy.bat
R092	Start.bat	tools/Start.bat
R091	Status.bat	tools/Status.bat
R092	Stop.bat	tools/Stop.bat
R091	Uninstall.bat	tools/Uninstall.bat
```

构建产物位于 publish/self-contained/win-x64 与 release/dist，未将155MiB可执行文件塞入Git源码历史；由GitHub Release分发。
