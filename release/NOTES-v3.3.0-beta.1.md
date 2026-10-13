# WiFi Proxy Pilot v3.3.0-beta.1

Prerelease candidate for Windows 11 x64. The previous v3.2.0-beta.1 Release is retained. This release must not be described as stable before the complete Setup → activation → background management → removal path has passed its recorded acceptance checks.

## User-visible changes

- Native Windows title bar and right-side caption controls, preserving system maximize, resize and close-to-tray semantics.
- One vector-derived Wi-Fi/routing product icon across EXE, taskbar, Setup and shortcuts; branded tray markers distinguish monitoring, direct, paused and attention states.
- Automatic switching enters Processing immediately, rejects duplicate commands and reads actual persisted intent and watcher acknowledgement before success. Pausing preserves the manual proxy; Restore direct remains a separate action.
- Every preview page identifies simulated network data and disables real proxy/watcher/installation controls.
- Complete en-US and zh-CN ResourceManager resources with runtime page/tray refresh and a persisted Follow Windows / 简体中文 / English setting. Unsupported display languages use English; Traditional Chinese deliberately uses Simplified Chinese. README translations are separate documentation.
- Real current-user **WiFiProxyPilot-Setup-x64.exe**, built with pinned Inno Setup 7.1.0. The installed application is **WiFiProxyPilot.exe**, with Start menu, optional desktop shortcut and Windows Installed Apps registration.
- Installer migration preserves the existing engine data root, rules, task ownership, management intent and first proxy backup while retiring verified legacy desktop records. Inno owns the single program installation/removal entry.
- Uninstall offers original-proxy restoration, current-proxy retention and cancellation, with separately controlled known user-data retention. Checked lifecycle failures retain retry/recovery information and do not claim success.
- Installed runtime files are unbundled self-contained files to avoid single-file cold-start extraction; the optional portable package retains single-file packaging.

## Download assets

1. **WiFiProxyPilot-Setup-x64.exe** — recommended installer;
2. **SHA256.txt** — hashes of the actual candidate files;
3. **WiFiProxyPilot-Portable-x64.zip** — optional extracted application, not an installer.

Installing or launching a fresh application does not enable proxy management. Configure the real gateway proxy service and Wi-Fi rules, then confirm activation. Upgrade existing users by running Setup directly; do not uninstall first or replace personal configuration with repository defaults.

## Validation and known limits

The authoritative [v3.3 acceptance record](../docs/TEST_RESULTS_V3_3.md) links executed UI automation, engine/lifecycle regressions, disposable Windows Setup/upgrade/uninstall/WinINet results and measured timings. A passing build, fixture test or screenshot is never substituted for a live operation. Candidate publication and checks are reported independently.

Actual wireless transitions require a Wi-Fi-equipped device. A runner without wireless hardware can validate Setup, persisted watcher intent, WinINet and restoration while that device boundary remains explicit. Full DPI/Snap, Explorer restart and sleep/login coverage must retain their actual executed or unexecuted status.

See [installation and removal](../docs/INSTALLATION_V3_3.md), [troubleshooting](../docs/TROUBLESHOOTING_V3_3.md) and the [v3.2 performance baseline](../docs/PERFORMANCE_V3_2.md).

## 简体中文

本版本为 Windows 11 x64 预发布候选版本，保留原 v3.2 Release。新增 Windows 原生窗口管理、统一品牌与托盘状态图标、真实后台状态回读的自动切换，以及可运行时切换的英文／简体中文界面。

默认下载 **WiFiProxyPilot-Setup-x64.exe**。安装器按当前用户安装，统一开始菜单、已安装应用及卸载入口；安装软件不会自动启用代理。旧版运行新 Setup 升级，保留原配置、规则、任务归属及最初代理备份。卸载支持恢复原代理、保留当前代理或取消，并另行选择用户数据保留策略。

所有验收结论以实际测试记录为准。未执行的设备行为不会写成通过，模拟数据与漂亮截图不能证明真实代理或安装生命周期正常。
