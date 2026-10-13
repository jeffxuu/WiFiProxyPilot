# WiFi Proxy Pilot

[简体中文](README.zh-CN.md)

A Windows 11 Wi-Fi proxy manager that switches the Windows **manual proxy** according to your own Wi-Fi rules. Use a phone hotspot's IPv4 gateway as the proxy address, keep selected networks direct, and manage everything from the system tray.

**It does not include a VPN or a proxy server.** A proxy must already be running at the chosen gateway and port. Enabling the Windows proxy does not prove that the proxy or internet connection works.

v3.2.0-beta.1 is in development. The first real WPF interface is being prepared for visual review; release preparation is still a draft. Real Wi-Fi, proxy writes, installation upgrades, logon, sleep/resume and uninstall acceptance require authorized Windows testing. See [test results](docs/TEST_RESULTS_V3_2.md) and [release checklist](docs/RELEASE_CHECKLIST.md).

![Dashboard running in an isolated test environment](docs/images/dashboard.png)

*Actual application screenshot with simulated network data. It is not evidence of a real network test.*

## Features

- Uses the current physical Wi-Fi interface's IPv4 default gateway and your proxy port, with fresh confirmation after a network change.
- Lets you add, edit and remove **every** direct-network rule. New users start with an empty list; matching uses the complete name, ignoring case.
- Separates automatic monitoring, pause, direct mode, current Windows proxy and TCP/HTTP diagnosis.
- Uses a WPF interface with a restrained macOS-inspired hierarchy adapted to Windows, tray access, single-instance activation and an independent background watcher.
- Saves configuration atomically, detects editing conflicts and confirms background application separately from saving.
- Preserves the original manual-proxy backup and protects changes made later by you or another application.

The interface currently uses Simplified Chinese. English documentation is provided here; a full English interface is not advertised as implemented. Detailed implementation and verification status are maintained in the linked documents.

## Download and requirements

Candidate builds and draft releases are prepared in the existing [WiFi-test repository](https://github.com/jeffxuu/WiFi-test/releases) and [Windows build workflows](https://github.com/jeffxuu/WiFi-test/actions). The repository is currently private; these links require repository access. A v3.1 draft is an older build, **not** the v3.2 candidate. Use the build and SHA256 identified in the eventual candidate release notes; no v3.2 public download is claimed yet.

The Windows x64 self-contained EXE retains the compatibility filename `WiFiProxySwitcher.exe`. No separate .NET, Python, Node.js or WebView2 installation is required. Windows 11, Windows PowerShell 5.1, WLAN service and Windows Script Host are required. Organization policies may restrict proxy or scheduled-task changes. Builds without Authenticode signing are clearly identified; do not bypass Windows security features.

Download the EXE or ZIP plus its `SHA256.txt`, then verify the executable:

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

## First setup

1. Open the EXE. Opening the interface alone does not change your proxy.
2. Read the explanation: the tool controls Windows manual proxy settings; it supplies no proxy service.
3. Choose the gateway port, normally `7890`. The gateway may have no proxy service at all.
4. Add Wi-Fi names that should use direct connections, or leave the list empty. Add the current network when its name is reliably available.
5. Review the Windows settings that will change and explicitly enable automatic switching.

Installation is for the current interactive user. Do not use a different administrator account to install for your usual account. Existing users should open the candidate and use Settings → advanced operations → repair/upgrade; keep the installed configuration and original backup. See [configuration migration](docs/CONFIG_MIGRATION.md).

## Wi-Fi rules

![Wi-Fi rules editor running with simulated data](docs/images/rules.png)

*Actual rules editor screenshot in an isolated test environment.*

Use **Wi-Fi 规则** to add a network, edit its name, delete it or add the current connection. Legal spaces are preserved. Names must be 1–32 UTF-8 bytes and contain no control characters; a similar name or suffix does not match.

**保存并应用** saves the draft with conflict protection. “Saved” means the file was written; “rules applied” appears only after a compatible watcher acknowledges the same revision and confirms a stable current network. Otherwise the interface shows “saved, waiting for background application”. Cancel discards unsaved edits. An empty list is valid and no hidden network rules are reinserted.

## Tray and recovery actions

| Action | Result |
| --- | --- |
| 开启自动切换 / Enable automatic switching | The watcher follows your rules after confirming the current network. |
| 暂停自动切换 / Pause | Stops automatic proxy writes and retains the current proxy; it may remain active. |
| 恢复直连 / Direct mode | Pauses automatic management and turns off only Windows manual proxy. |
| 立即检测 / Check now | Requests fresh network collection and stable confirmation. |
| Close X | Hides the window by default; the tray and watcher continue. |
| 退出界面 / Exit interface | Exits GUI/tray; the independent watcher continues. |
| 恢复安装前配置 / Restore original | Stops automatic management and safely restores the original manual settings. |

Pause/direct choices persist across interface restarts, logon and reboot. Watcher and tray logon settings are independent. PAC and automatic detection settings are preserved; they can still influence an application's actual route.

## Proxy policy and diagnosis

**Strict** applies the configured rule after you enable it. Failed proxy diagnosis is displayed but does not silently turn the proxy off. **Safe** uses the configured diagnosis and consecutive-failure threshold to fall back to direct mode; some traffic may then bypass the proxy. Unknown results are not treated as successful recovery.

TCP reachability means only that the port accepts a connection. HTTP validation requires an actual request through the proxy and an explicit HTTP diagnostic URL. Neither is a general guarantee of internet access. Missing Wi-Fi, uncertain SSID, unavailable IPv4 gateway or ambiguous interfaces retain the existing protective behavior and surface a reason.

## Backup, restore and uninstall

The original manual-proxy snapshot is stored in the installed `state/proxy-before-install.json`; upgrades retain it. Editing configuration keeps an atomic previous copy. Do not replace these files with a repository default or share them without removing private information.

Direct mode keeps the original backup. Original restore and uninstall compare the current manual settings with the original/last settings written by this tool. If another application or you changed them later, automatic restore is refused and the conflict is explained. Force restore is an explicit user choice; uninstall can instead keep the current proxy.

Use Settings → advanced operations → uninstall, or the Windows installed-apps entry. Only owned tasks, startup records and hash-verified product files are removed. Unrelated files and user-modified files are protected. See [migration and restore details](docs/CONFIG_MIGRATION.md).

## Frequently asked questions

**Why is my network unavailable even when the proxy is enabled?** The service may be stopped, the port may be wrong or the gateway may not run a proxy. Check the separate diagnosis, pause management or choose direct mode.

**Does closing the window stop the proxy?** X hides the interface by default. Exiting the tray does not stop the independent watcher or restore proxy settings.

**Can I delete every network rule?** Yes. Every rule belongs to you and an empty list is supported.

**Why is the status unavailable?** WLAN/location permissions, policies, a stopped watcher or an old heartbeat may prevent reliable reads. The interface shows the reason and last successful observation instead of claiming current data.

**Does it affect every application?** It manages the current user's Windows manual proxy. Applications using their own proxy, ignoring Windows proxy, or using PAC may behave differently.

**What is verified?** [Test results](docs/TEST_RESULTS_V3_2.md) separate simulated/isolated checks from real Windows acceptance. [Performance](docs/PERFORMANCE_V3_2.md) records actual samples and limits; target times are not invented measurements.

## Architecture and development

WPF/MVVM presentation calls application services. Existing PowerShell control/lifecycle code, native WLAN/WinINet support, atomic configuration store, payload SHA256 cache, task ownership checks and restore safeguards remain the engine. UI and engine versions are reported separately. Installation identities intentionally retain `WiFiProxySwitcher` compatibility.

Build with the pinned .NET 8 SDK and Windows PowerShell:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

`release/Build.ps1` packages the verified payload, runs C# checks and publishes the Windows executable. It does not install or alter the host proxy. See [contributing](CONTRIBUTING.md), [product requirements](docs/PRODUCT_REQUIREMENTS.md) and [state model](docs/INTERACTION_STATE_MACHINE.md).

## Security, privacy and license

The application has no analytics service. Network names, proxy state, configuration and logs are local. Optional diagnosis connects to the chosen proxy and, in HTTP mode, the configured test URL. Logs and diagnostics can contain network identifiers; review them before sharing.

Older history contains legacy network examples and requires a separate privacy decision before becoming public. See [public audit](docs/PUBLIC_REPOSITORY_AUDIT.md) and [security reporting](SECURITY.md). Repository renaming/publication does not happen automatically.

Project source is licensed under [MIT](LICENSE). Third-party materials keep their own notices and applicable font restrictions; see [third-party notices](docs/THIRD_PARTY_NOTICES.md).
