# WiFi Proxy Pilot v3.3 installation, upgrade and removal

v3.3.0-beta.1 is a prerelease candidate. This guide describes the implemented user path; [TEST_RESULTS_V3_3.md](TEST_RESULTS_V3_3.md) records which steps were actually executed. Successful compilation or a preview image does not prove Setup, WinINet or uninstall acceptance.

## Install as the current user

1. Download **WiFiProxyPilot-Setup-x64.exe** and the accompanying **SHA256.txt** from the candidate Release. Verify the Setup SHA256 before running it.
2. Run Setup as the ordinary account that will use the software. The installer uses `PrivilegesRequired=lowest`; it does not require another administrator account or manage that account's HKCU proxy.
3. Complete the English or Simplified Chinese welcome and license pages. The installer uses Windows UI display language: English/unsupported languages select English, and Chinese display languages including zh-TW/zh-HK select Simplified Chinese. A previously selected installer language is retained on upgrade; an explicit language choice remains available.
4. Choose a dedicated program directory. The default is `%LOCALAPPDATA%\Programs\WiFiProxyPilot`. Optional desktop shortcut creation is unchecked by default.
5. Finish installation and optionally launch **WiFiProxyPilot.exe**, or open **WiFi Proxy Pilot** from Start.

Windows Settings → Apps → Installed apps shows **WiFi Proxy Pilot**, the candidate version, publisher and product icon. Its uninstall entry belongs to Inno Setup. The same product icon is embedded in Setup, the installed EXE, taskbar and shortcuts; tray icons preserve the brand and add state markers.

Installing the application and enabling its watcher are separate steps. A new installation does not enable the Windows manual proxy, create a watcher task or choose a nonexistent gateway proxy. Open the application, review the port and Wi-Fi rules, then confirm **Enable automatic switching**. WiFi Proxy Pilot supplies no proxy service or VPN: the selected Wi-Fi gateway must already run a reachable service at your configured port.

## Upgrade an existing installation

Run the new Setup over the existing installation. **Do not uninstall the old version first.** Migration checks SID, installation ownership and known file hashes before retiring legacy desktop registration. Modified or unowned records cause a checked failure rather than an overwrite.

Inno Setup owns application program files, the Start menu/optional desktop shortcut, and the sole Installed Apps entry. The existing engine remains responsible for its independent watcher, owned login task, configuration and proxy backup. Internal `WiFiProxySwitcher` registry, task and mutex identifiers continue to provide compatibility; the visible product name is WiFi Proxy Pilot.

An existing engine data directory is retained in place. Upgrade preserves:

- `config.json`, SSID rules, saved management intent and settings;
- `state/proxy-before-install.json`, the original backup from the first activation;
- task ownership and the prior enabled/running state;
- user logs, unknown files and upgrade recovery material.

Verified legacy desktop EXEs, startup pointers and uninstall entries are retired. Inno migration does not create an additional watcher or replace the original backup. Setup checkpoints and checked lifecycle results support retry after interruption. Read the reported failure before retrying; do not delete installation manifests or backups to force success.

## Daily operation

| Operation | Meaning |
| --- | --- |
| Enable automatic switching before activation | Open configuration and ask for explicit activation |
| Enable after activation | Persist Monitoring and confirm the independent watcher is running |
| Disable automatic switching | Persist Paused; retain the actual manual proxy |
| Restore direct | Pause management and disable the Windows manual proxy |
| Check now | Request fresh network observation; a request is distinct from stable evaluation |
| Native X | Hide to the tray; preserve the watcher and proxy |
| Minimize | Normal Windows minimize, or hide to tray if selected |
| Exit interface from tray | Exit GUI/tray while preserving the independent watcher |

The toggle shows Processing while its command is running and rejects duplicate clicks. Success requires persisted intent and checked backend acknowledgement. A paused manual proxy can still be enabled; **Restore direct** is a separate action.

## Language and demonstration mode

The UI uses `.resx` ResourceManager resources for en-US and zh-CN. **Settings → Language → Follow Windows** reads `CultureInfo.CurrentUICulture`, not the region or date format. Unsupported display languages use English; Traditional Chinese display languages deliberately use Simplified Chinese for this release. Selecting English or 简体中文 refreshes retained pages, tray menus and later dialogs immediately and persists across restart.

Preferences and an unconfirmed setup draft are saved under `%LOCALAPPDATA%\WiFiProxySwitcher-Control` before watcher activation. Existing installation configuration and original backup are separate from these UI files. Eleven translated README files are documentation; application UI support is the two languages listed above.

`/preview /output <report.json>` uses an owned fixture, simulated network facts and a visible Demo mode banner on every page. Proxy, automatic-switch, watcher and installation controls are disabled. Editing rules and UI preferences within that isolated fixture cannot modify the host WinINet state or scheduled tasks.

## Uninstall and proxy restoration

Use Windows Settings → Apps → Installed apps → WiFi Proxy Pilot → Uninstall. The application's advanced Uninstall action opens the same installer-owned removal path. The GUI remains available until the wizard commits removal; cancelling a choice or the final uninstall confirmation preserves the installation and running watcher.

The wizard offers:

1. **Restore the original manual proxy** or **keep current settings**. If a later external change is detected, the conflict explicitly provides Restore original / Keep current / Cancel. Forced restoration requires this deliberate choice. PAC and automatic detection retain the protection provided by the engine's restoration model.
2. **Keep known user data** or **delete known user data**. Keeping copies rules, configuration, original proxy backup and logs into `%LOCALAPPDATA%\WiFiProxyPilot-Retained`. Unknown files and upgrade backups are preserved regardless.

After the choices and native confirmation, the checked lifecycle stops the correct GUI/tray and watcher, removes owned login/startup entries and shortcuts, verifies engine cleanup and then allows Inno to remove its program files and uninstall registration. User-modified program files are verified and retained rather than silently overwritten or erased. No blanket recursive deletion of the application data root is used.

If a lifecycle step fails, the result reports failure and retains recovery/uninstall information for retry. The lifecycle logs are in `%LOCALAPPDATA%\WiFiProxySwitcher-Control`. Review [troubleshooting](TROUBLESHOOTING_V3_3.md) before changing retained data or registry entries.

## Portable package

**WiFiProxyPilot-Portable-x64.zip** contains the single-file self-contained application and documentation. Extraction is not installation: it creates no Inno registration or Start menu shortcut. Opening it does not enable proxy management. Confirming watcher activation uses the legacy engine/desktop ownership model, which can later be migrated by Setup. Avoid treating the contained application EXE as an installer; Setup is the recommended download.

## Build and verify

Use Windows PowerShell 5.1 and the .NET SDK pinned in `global.json`:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
dotnet run --project tests\Localization.Tests\Localization.Tests.csproj -- artifacts\localization-results.json
powershell.exe -NoProfile -File release\Build.ps1
Get-FileHash .\release\dist\WiFiProxyPilot-Setup-x64.exe -Algorithm SHA256
```

The build pins **Inno Setup 7.1.0** through `release/Get-InnoCompiler.ps1`, validates the package SHA256 and upstream Authenticode signatures, and verifies the compiler version. It extracts the build dependency locally without installing a compiler application or adding registry records. `-InnoCompiler` can supply a previously prepared compiler path. The regular build does not install the product, modify the host proxy or run installed-host acceptance.

Outputs under `release/dist`:

- **WiFiProxyPilot-Setup-x64.exe** — the current-user installer;
- **WiFiProxyPilot-Portable-x64.zip** — the secondary extracted application package;
- **SHA256.txt** — checksums for those exact files.

`release/generated/build-record.json` records version, pinned compiler, runtime packaging, ownership and hashes. The installed application uses an unbundled self-contained runtime to avoid cold-start single-file extraction. The portable application uses single-file packaging.

Real Setup/upgrade/uninstall/WinINet acceptance runs through `tests/Installed.Acceptance.ps1` on a disposable GitHub-hosted Windows runner. The script refuses an ordinary workstation. It snapshots and restores that runner's proxy state. Desktop.Automation operates actual WPF controls. Their results, native-caption screenshots and actual timings are uploaded by `.github/workflows/build.yml`; inspect the run linked by the acceptance record.

## 中文说明

请下载 **Setup EXE**，以日常使用的普通 Windows 用户完成安装，然后从开始菜单打开。安装软件不会自动接管代理；必须先配置已有网关代理服务的端口和免代理 Wi-Fi，再确认开启。关闭开关表示暂停自动管理，当前手动代理可能仍开启；“恢复直连”是独立操作。

旧版直接运行新 Setup 升级，不要先卸载。现有配置、SSID 规则、任务归属和最初备份继续保留，Inno 统一管理程序安装与卸载记录。卸载时可以恢复安装前代理、保留当前代理或取消，并另行选择保留或删除已知用户数据。保留数据位于 `%LOCALAPPDATA%\WiFiProxyPilot-Retained`；未知文件、用户修改文件及升级备份不会通过递归清空目录被删除。

界面语言支持 English 和简体中文；默认跟随 Windows 显示语言，其他语言回退英文，繁体中文明确回退简体中文。所有“通过”结论必须对应[实际验收记录](TEST_RESULTS_V3_3.md)，模拟网络不能证明真实无线切换或代理可用。
