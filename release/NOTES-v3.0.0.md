Windows 11 Wi-Fi 智能代理自动切换工具。

- 下载 `WiFiProxySwitcher.exe`，首次可用当前账户右键“以管理员身份运行”，自动完成当前用户安装；普通用户权限允许时也可直接安装。以后从开始菜单或 EXE 打开状态窗口。
- 显示 SSID、无线接口、IPv4 网关、系统手动代理、Watcher 与最近日志；支持启动、停止、立即检测、恢复和卸载。
- 原 PowerShell 网络引擎保留：精确 SSID 白名单、接口关联 IPv4 网关、WinINet、Strict/Safe、原代理备份与冲突保护。
- `.NET 8 / win-x64` 自包含单文件，不要求用户安装 .NET、Python、Node.js；Windows PowerShell 5.1 与 WSH 使用系统自带组件。
- 提供 EXE、ZIP 和 SHA256.txt。该版本未进行 Authenticode 签名，不关闭或绕过 Windows 安全功能。

验证：发布流水线必须通过原有 PowerShell 模拟/回归套件、C# 启动器边界测试及 Windows EXE/WinForms 渲染冒烟测试。Windows 上运行的模拟测试仍不代表真实 Wi-Fi、代理修改、任务登录、管理员安装/卸载、睡眠唤醒或无闪烁已经验收；这些须按 docs/PRODUCT_WINDOWS_ACCEPTANCE.md 在本机验证。

首次安装若使用了另一个管理员账户，会被拒绝，避免修改错误用户的 HKCU。恢复/卸载遇到后续代理修改时需要明确选择；默认不覆盖。
