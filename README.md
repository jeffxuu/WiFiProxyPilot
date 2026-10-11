# Wi-Fi 智能代理切换 · Windows 11

连接 `MC-Office` 或 `Meituan` 时关闭手动代理；连接其他 Wi-Fi 时使用当前无线网卡的 IPv4 网关和 `7890` 端口。安装一次，后台自动切换。

## 1. 下载

打开 **[v3.0.0 下载页面](https://github.com/jeffxuu/WiFi-test/releases/tag/v3.0.0)**，下载 `WiFiProxySwitcher.exe`，也可下载 ZIP。Windows 11 64 位适用，无需另装 .NET、Python 或 Node.js。可用同页 `SHA256.txt` 校验文件。

## 2. 安装

第一次可右键 EXE → **以管理员身份运行**，使用你当前 Windows 桌面的同一个账户。状态窗口会自动完成当前用户安装；普通权限满足要求时也可直接双击安装。请勿借用另一管理员账户，程序会拒绝更改错误用户的代理。

安装后会加入开始菜单与“设置 → 应用 → 已安装的应用”，保存原代理配置，并立即开始监控。默认安装在当前用户的本地应用目录。Windows 登录后自动运行后台监控。

## 3. 使用

从开始菜单或 EXE 打开状态窗口，可查看 SSID、接口、IPv4 网关、代理、Watcher 和最近日志。提供 **启动监控、停止监控、立即检测、恢复代理**。关闭窗口后后台监控继续；停止监控会同时禁用登录自启，启动监控可恢复。

默认 **Strict** 模式会按网关设置代理，即使该网关没有代理服务也不会擅自改规则。网关没有运行代理时可能无法上网；可停止并恢复，或按高级手册明确选用 **Safe** 模式。白名单是完整名称、忽略大小写匹配。

## 4. 卸载

点击窗口中的 **卸载**，或在 Windows“已安装的应用”中卸载。程序停止 Watcher、移除自己的登录任务和入口、恢复安装前手动代理。检测到后来手工修改时会让你选择恢复原配置、保留当前配置或取消，默认不覆盖。首次备份与用户配置在重复安装时保持。

> 本项目没有代码签名证书，Windows 可能显示信誉提示；不要关闭安全功能。构建/模拟/Windows 冒烟证据与真实网络验收分开记录，见下方测试文档。未完成本机验收前，不声称已验证你电脑上的无线驱动、位置权限、无闪烁、睡眠唤醒及长期稳定性。

---

[高级配置与维护](docs/ADVANCED_USAGE.md) · [EXE 架构与构建](docs/PRODUCTIZATION.md) · [EXE 本机验收](docs/PRODUCT_WINDOWS_ACCEPTANCE.md) · [网络功能验收](docs/WINDOWS_ACCEPTANCE.md) · [测试证据](docs/PRODUCT_TEST_RESULTS.md)

维护 BAT 保留在 `tools/`，普通用户无需使用。开发源码在 `src/WiFiProxySwitcher/`，PowerShell 网络引擎继续位于根目录和 `lib/`。本次仓库审计见 [REPOSITORY_AUDIT_V3.md](docs/REPOSITORY_AUDIT_V3.md)。
