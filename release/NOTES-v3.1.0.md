# v3.1.0 候选 · 待真实 Windows 网络验收

四页 WinForms UI、系统托盘常驻及单实例窗口恢复；用户免代理名单、原子配置保存和 Watcher 安全热更新；版本化完整校验缓存与后台状态读取。

自包含 Windows 11 x64 EXE，无需额外 .NET、Python、Node.js、WebView2。默认 MC-Office / Meituan 和原 IPv4 网关、7890、Strict/Safe、<local>、冲突恢复规则保留。

升级：打开新 EXE，在设置的高级操作中确认“修复安装 / 升级”。不要先卸载，也不要覆盖自己的 config.json 或最初代理备份。仅关闭主窗口/退出界面不会停止 Watcher 或恢复代理。

已经执行原有及新增单元/模拟验证和隔离 Windows 桌面冒烟。开发机器上的真实安装升级、名单热更新、登录/休眠/Explorer、代理服务连通性和卸载尚未获得授权验收。**这是草稿预发布，不宣称关闭窗口后的真实断网原因已修复，也不宣称真实网络验收全部通过。**

详细结果见 docs/TEST_RESULTS_V3_1.md 和 docs/STARTUP_PERFORMANCE.md。CI 附件包含 EXE、ZIP、SHA256 和模拟/桌面证据；v3.0.0 Release 未修改。
