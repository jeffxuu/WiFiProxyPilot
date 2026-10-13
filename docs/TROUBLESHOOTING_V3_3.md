# WiFi Proxy Pilot v3.3 troubleshooting

Start with the actual UI state, persisted configuration and checked command result. A click, a green-looking switch or a successful build does not prove that the independent watcher changed Windows proxy settings. See [installation and removal](INSTALLATION_V3_3.md) and [acceptance evidence](TEST_RESULTS_V3_3.md).

## Automatic switching appears ineffective

| Observation | Check and action |
| --- | --- |
| Demo mode banner is visible | Network facts are simulated and system controls are disabled. Close the preview and open the installed Start menu application for real operation. |
| First activation opens Setup | Review proxy port and Wi-Fi rules and confirm activation. Opening or installing the application alone does not manage proxy. |
| Processing persists or the operation fails | Read the displayed stable error code and command trace. The switch is refreshed from actual persisted intent; repeat clicks are disabled during processing. |
| Paused, manual proxy still enabled | This is the defined pause behavior. Use Restore direct to disable the manual proxy without discarding the original backup. |
| Monitoring is enabled but background state needs confirmation | Check the owned scheduled task, fresh heartbeat and compatible watcher schema. The UI does not manufacture a running watcher from the saved intent. |
| Watcher upgrade required | Use the checked Upgrade watcher action or run the newer Setup. Preserve configuration and original backup; do not replace them with defaults. |

The trace at `%LOCALAPPDATA%\WiFiProxySwitcher-Control\commands.jsonl` records WPF command start/result, controller processing and backend acknowledgement. It is bounded and rotated; it excludes SSIDs and proxy addresses. Backend technical diagnostics may contain private network information. Review them before sharing.

## Proxy enabled but traffic fails

The gateway must run a real proxy service; a hotspot or gateway address alone supplies none. Confirm the service is running, its port matches Settings, and tethered clients are allowed to connect. TCP diagnosis establishes a connectable port only. HTTP diagnosis validates an actual proxy request to the configured HTTP URL. Neither proves every application's connectivity.

Strict mode follows the Wi-Fi rule even when diagnostics fail. Safe mode can fall back to direct after consecutive confirmed failures, allowing some traffic to bypass the proxy. PAC/auto-detection and applications with their own proxy settings can determine a different route.

If the UI reports a WinINet/registry mismatch or an external proxy change, inspect diagnostics and the current Windows proxy settings. The UI keeps actual settings visible and requests reevaluation; it does not translate a raw Chinese log sentence into a success state.

## Wi-Fi cannot be confirmed

Check that the physical wireless adapter is enabled and the Windows WLAN service is running. Windows location permissions and organization policies can limit SSID access. Several simultaneous wireless interfaces, DHCP still in progress or a missing IPv4 gateway can prevent a unique current rule. Unknown facts preserve current settings rather than reusing an old gateway.

On a disposable runner without a wireless adapter, real WinINet and Setup lifecycle tests are still useful, but actual hardware SSID transitions, sleep/reconnect and WLAN driver behavior remain distinct device checks. The acceptance report labels that boundary explicitly.

## Rules or settings do not persist

Save and apply distinguishes the atomic file write from watcher application. The latter requires a fresh compatible heartbeat, matching saved/applied revision and stable evaluation. Paused or direct intent does not force a proxy write. Cancel discards only unsaved edits.

Duplicate complete SSIDs are rejected case-insensitively. Names preserve spaces and must be 1–32 UTF-8 bytes without control characters. If another program edited the configuration, reload it before saving; concurrent changes are protected. Before activation, the setup draft persists separately in `%LOCALAPPDATA%\WiFiProxySwitcher-Control\draft-config.json`.

## Language is unexpected

Choose Settings → Language → Follow Windows, 简体中文 or English. Follow Windows uses the current user's display language. An English display with Chinese date/region settings still uses English. Traditional Chinese Windows deliberately falls back to Simplified Chinese; unsupported languages fall back to English. The override persists in `preferences.json` before watcher activation and in saved settings.

Page labels, tray menu and subsequent dialogs refresh at runtime. Raw watcher log lines retain their original engine language and are explicitly described as technical logs; the surrounding UI and error-code explanations use the selected language. Eleven README translations do not mean eleven application UI languages.

## Setup or upgrade fails

Use the Setup asset and compare SHA256; the application EXE is not an installer. Install as the actual interactive user, with a dedicated local program directory. The program directory must not be the existing watcher data root. Paths containing spaces or Chinese are included in the disposable Windows acceptance scenarios.

Review the checked lifecycle result and the Inno Setup log. A failed migration preserves the first proxy backup and records a pending receipt for safe retry. Unrecognized ownership or modified legacy executables are refused instead of being silently replaced. Do not delete ownership receipts or old backup files to bypass the failure.

Check `%LOCALAPPDATA%\WiFiProxySwitcher-Control\installer-PrepareInstall-result.json` and `installer-CommitInstall-result.json`, along with the lifecycle log. Windows Installed Apps must contain one Inno-owned WiFi Proxy Pilot record. Duplicate old entries or tasks are a failed migration condition, not a normal upgrade result.

## Uninstall reports a restoration conflict

The current manual proxy differs from both the original backup and the last settings written by Pilot. The wizard offers:

- **Restore original** — deliberately replace the later manual change with the first saved proxy configuration;
- **Keep current** — remove the software while retaining the present proxy configuration;
- **Cancel** — preserve the installation and running state without performing removal.

Choose data retention separately. Known user data can be copied to `%LOCALAPPDATA%\WiFiProxyPilot-Retained` or deliberately deleted. Unknown files and upgrade backups remain protected. The final native uninstall confirmation precedes mutations. If a checked step fails, review `installer-Uninstall-result.json` and retry from the preserved uninstall entry; do not recursively delete the data directory to conceal unfinished cleanup.

## Icons or tray appear wrong

Use the v3.3 Setup to replace the verified legacy shortcut and registration; editing an ICO by hand does not update every shell location. Explorer may cache shortcut or EXE icons. Reopening Start or signing out and back in can refresh that cache. A TaskbarCreated notification restores the application's NotifyIcon after Explorer recreation; simulated-message coverage and an actual Explorer restart are reported separately.

The four tray markers distinguish automatic monitoring, direct connection, paused management and attention. Their common brand silhouette is retained. Do not infer proxy connectivity from icon color alone; read actual manual-proxy and diagnostic states.

## Collect useful evidence

Provide the candidate version and Setup SHA256, selected UI language, expected/actual operation, visible error code and a redacted diagnostic record. Include the relevant workflow/run URL when reporting a CI failure. Keep configurations, original backups, private SSIDs and proxy addresses out of public issues unless deliberately redacted.

## 中文排查要点

先确认是否显示“演示模式”；预览中的真实代理操作禁用。自动切换关闭表示暂停，手动代理保留；要关闭手动代理请用“恢复直连”。Processing 期间不能重复点击，失败后应根据实际管理意图及后台状态回读排查，不能只看开关颜色。

安装或卸载失败时查看 `%LOCALAPPDATA%\WiFiProxySwitcher-Control` 中的结果及日志，保留原始备份、归属记录和重试入口。恢复冲突必须明确选择恢复原配置、保留当前配置或取消。不要手工递归删除应用数据目录。完整结果及设备限制以[验收记录](TEST_RESULTS_V3_3.md)为准。
