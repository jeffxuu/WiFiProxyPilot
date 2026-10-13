<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Smart Wi-Fi Proxy Switching for Windows</h3>
  <p>A lightweight, modern Windows utility that automatically switches your system proxy based on Wi-Fi SSIDs, gateway addresses and user-defined rules.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.3.0-beta.1)
  [![MIT License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Your Wi-Fi changes. Your proxy follows.** Use a gateway-hosted proxy on ordinary Wi-Fi networks and connect directly on networks you choose. Manage it from a modern WPF desktop or the system tray.

> **v3.3.0-beta.1 is a prerelease candidate.** This revision adds native Windows window controls, a real per-user Setup EXE and complete English/Simplified Chinese UI resources. Read the [acceptance record](docs/TEST_RESULTS_V3_3.md) for actual results and pending checks. Compilation, previews and screenshots alone do not establish installation or proxy-management acceptance. The existing v3.2 Release is retained.

## Screenshots

The gallery below records the **v3.2 layout** with simulated network data. Its old caption buttons are historical and do not depict the new native v3.3 title bar. v3.3 full-window captures will be added only from an unlocked desktop or a verified CI capture; no installation-success image is fabricated. Actual control-operation evidence is linked in the acceptance record.

![Overview — actual WPF app, simulated network](docs/images/dashboard.png)

| Wi-Fi Rules | Settings |
| --- | --- |
| ![Wi-Fi Rules preview](docs/images/rules.png) | ![Settings preview](docs/images/settings.png) |

<details>
<summary>Dark theme preview</summary>

![Dark theme — earlier WPF overview layout](docs/images/dashboard-dark.png)

</details>

![System tray menu — actual application, isolated preview](docs/images/tray.png)

All images are real application captures from an isolated fixture, **not evidence of a live proxy connection**. The dark capture uses an earlier overview layout. The tray menu is captured from the same application in an isolated fixture.

## What it does

- Recognizes the connected Wi-Fi and matches your complete SSID rules, ignoring case.
- Resolves the current physical Wi-Fi interface's **IPv4 default gateway**, then applies your configured proxy port (default `7890`).
- Uses direct-connection rules for selected networks. New installations start with **no built-in Wi-Fi rules**; every rule can be edited or deleted.
- Keeps the simple WPF content design with native Windows caption controls, light/dark themes and a system tray with an independent watcher.
- Uses English or Simplified Chinese based on Windows display language, with a persistent Language setting.
- Installs through a current-user Inno Setup wizard with a Start menu entry and checked uninstall lifecycle.
- Separates automatic management, Windows manual-proxy state and optional TCP/HTTP diagnostics. An enabled proxy is not proof of internet access.
- Saves configuration atomically and distinguishes “saved” from “applied by the watcher.”
- Retains the original manual-proxy backup and protects later changes made by you or another application.
- Provides source code under MIT for inspection and contribution.

## Download and installation

**[Download Windows x64 Setup — v3.3.0-beta.1](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe)**

[Candidate release and notes](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.3.0-beta.1) · [SHA256 checksums](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/SHA256.txt) · [Windows build and acceptance](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)

The Setup download is the installer. It creates the Start menu entry and Windows Installed Apps entry, and offers an optional desktop shortcut. The installed application is **WiFiProxyPilot.exe**. Candidate asset links become available when the v3.3 candidate is published; build and acceptance status are recorded separately.

The intended platform is **Windows 11 x64**, with Windows PowerShell 5.1, WLAN service and Windows Script Host. The self-contained EXE does not require separately installing .NET, Python, Node.js or WebView2. No broader Windows compatibility is claimed. Organization policies may restrict WLAN information, proxy settings or scheduled tasks. Current builds are unsigned; keep Windows security protections enabled.

Verify Setup against the accompanying `SHA256.txt`:

```powershell
Get-FileHash .\WiFiProxyPilot-Setup-x64.exe -Algorithm SHA256
```

Run Setup as your normal interactive Windows user. The default location is `%LOCALAPPDATA%\Programs\WiFiProxyPilot`; unnecessary administrator elevation is not requested. Installing or opening the application **does not enable proxy management**. First activation requires reviewing the port and Wi-Fi rules and confirming automatic switching. Do not install for your everyday account using a different administrator's account.

[Portable archive](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Portable-x64.zip) is a secondary option for extracted application use. It is not a Setup EXE and does not register Installed Apps or shortcuts when extracted. Enabling its watcher uses the legacy current-user engine installation; use Setup for installer-managed upgrades and removal. See [installation, upgrade and uninstall](docs/INSTALLATION_V3_3.md).

## Quick Start

1. **Download and install Setup**, verify its hash, then open WiFi Proxy Pilot from Start.
2. **Configure** the port of an existing proxy on your Wi-Fi gateway, and add the Wi-Fi names that should use a direct connection.
3. **Enable Auto Switching** after reviewing the settings the app will manage.

**The gateway must actually run a proxy service. WiFi Proxy Pilot supplies neither a proxy server nor VPN nodes.** When using an Android hotspot, obtain its current IPv4 gateway automatically, set the proxy app's listening port and ensure that app accepts connections from the tethered Windows device. A hotspot by itself is not a proxy.

## How it works

```text
Wi-Fi connected → Read a stable SSID/interface snapshot → Match user rules
  ├─ Direct rule matches → Disable Windows manual proxy
  └─ No direct rule     → Resolve current Wi-Fi IPv4 gateway
                          → Apply gateway + configured port
```

The watcher verifies the current network before applying a change so an old gateway is not reused after switching Wi-Fi. Unknown SSID, missing routes or ambiguous interfaces retain the existing settings with an explanation and retry. A confirmed disconnection disables the manual proxy. PAC and automatic detection retain their existing values and can still affect application routing.

## Wi-Fi rule management

Open **Wi-Fi Rules** to add, rename, delete or add the current reliably detected network. Empty lists are supported. Matching uses the whole name with `OrdinalIgnoreCase`, not a prefix or substring. Legal spaces are preserved; names must be 1–32 UTF-8 bytes and contain no control characters.

**Save and Apply** checks concurrent edits and writes atomically. “Saved” confirms the file write; “Applied” requires a fresh, compatible watcher heartbeat with the same revision and a stable network. Otherwise the app shows that background application is pending. Cancel discards unsaved edits. Deleted rules are not silently restored.

## System tray and proxy modes

| Action | Effect |
| --- | --- |
| Enable automatic switching | Re-sample the network and manage the manual proxy using your rules |
| Pause | Stop automatic proxy writes; the current proxy setting stays in place |
| Direct connection | Pause management and disable only the Windows manual proxy |
| Check now | Request a fresh network observation and stable evaluation |
| Close the window | Hide to tray by default; the watcher continues |
| Exit the interface | Close the GUI/tray; the independent watcher continues |
| Restore original configuration | Stop management and safely restore the original backup, with conflict checks |

Pause and direct intent persist across GUI restarts and logins. Watcher login startup and tray startup are separate settings.

**Strict** applies the selected rule and reports probe failures without silently disabling the proxy. **Safe** can fall back to direct after the configured consecutive diagnostic failures, so some traffic may bypass the proxy. Unknown diagnostics do not count as recovery. TCP diagnosis proves only that a port can be connected to; HTTP diagnosis makes an actual proxy request to your configured HTTP test URL. Neither guarantees that every site or application works.

## Recovery and uninstall

The original manual-proxy backup is `state/proxy-before-install.json` under the watcher data directory. Program files and watcher data have separate ownership. Setup retains an existing engine root, SSID rules, management intent, task ownership and the first backup; it retires the verified legacy desktop/uninstall entries so they do not compete with Inno Setup. Keep these local files private.

Upgrade by running the new **Setup EXE** over the existing installation. Do not uninstall first or overwrite your configuration with repository defaults. A fresh installation does not install or start its watcher; existing activated installations retain their prior management intent. See [installation and migration](docs/INSTALLATION_V3_3.md) and [configuration migration](docs/CONFIG_MIGRATION.md).

Uninstall from **Windows Settings → Apps → Installed apps → WiFi Proxy Pilot**, or **Settings → Advanced operations → Uninstall**. The wizard offers restoration of the original manual proxy or retention of the current proxy. Later external changes trigger a conflict with **Restore original / Keep current / Cancel** choices. Cancel preserves the running application, watcher and installation.

The wizard also offers keeping or deleting known user data. Retained configuration, rules, original proxy backup and logs are copied to `%LOCALAPPDATA%\WiFiProxyPilot-Retained`. Unknown files, user-modified program files and upgrade backups remain protected. Cleanup verifies owned tasks, startup records and known files; it does not recursively erase an application data tree. See [troubleshooting](docs/TROUBLESHOOTING_V3_3.md) if a checked lifecycle result fails.

## Application languages

The application UI supports **English (en-US)** and **Simplified Chinese (zh-CN)**. **Settings → Language → Follow Windows** is the default and uses Windows display language through `CurrentUICulture`. Unsupported languages fall back to English. Traditional Chinese Windows uses a deliberate Simplified Chinese fallback in this release.

Selecting English or 简体中文 refreshes cached pages, tray menus and subsequent dialogs immediately and saves the preference for restart. Language preferences and unconfirmed setup drafts can persist before watcher activation. README translations in eleven languages are separate documentation and do not imply eleven UI languages.

When `/preview` or an isolated fixture is active, a visible **Demo mode** banner identifies simulated network data. Proxy, automatic-switch, watcher and installation controls are disabled; a demo cannot report a real proxy change.

## Security & Privacy

- SSIDs, proxy configuration, state and logs are handled locally; no cloud account or analytics service is required.
- The app does not collect Wi-Fi passwords. Optional diagnostics connect to the selected proxy and, in HTTP mode, the URL you configure.
- The original proxy backup is retained. Installation/task operations honor the current user's identity and permission checks.
- The app manages the current user's Windows **manual proxy**; it does not change DNS, routes or firewall rules.
- Logs and diagnostics can include network identifiers. Review and redact them before sharing.

Report security issues through [SECURITY.md](SECURITY.md).

## FAQ

**How can I automatically switch proxy by Wi-Fi on Windows 11?** Configure the gateway proxy port, add direct-connection SSIDs and enable automatic switching. The watcher evaluates stable Wi-Fi changes and applies Windows manual-proxy settings for the current user.

**How do I use an Android hotspot gateway as a Windows proxy?** Run a separate proxy service on the phone, allow tethered devices to reach it and set its listening port in Pilot. The gateway is discovered from the current Wi-Fi interface. Check the service and firewall on the phone if it is unreachable.

**Does WiFi Proxy Pilot include a VPN?** No. It manages Windows manual-proxy configuration; you supply the service. Applications using their own proxy or ignoring Windows settings may behave differently.

**Why is the proxy enabled but the internet unavailable?** The gateway may not host a proxy, the port/service may be wrong or stopped, or the destination may fail. Check TCP/HTTP diagnosis separately. Pause retains the setting; Direct disables the manual proxy. PAC may still influence traffic.

**How do I bypass proxy on specific Wi-Fi networks?** Add their complete SSIDs to Wi-Fi Rules and save/apply. Every rule is editable and deletable; an empty list is valid.

**How do I restore Windows proxy settings?** Choose Restore original configuration and review any external-change conflict. Direct only disables the manual proxy; it does not restore the original server and bypass list.

**Does the app keep running after closing the window?** Yes. X hides to tray by default. Exiting the GUI also leaves the independent watcher running; use Pause or Restore to change background management.

**Why can't the current network be read?** WLAN/location permissions, organization policies, missing routes, a stopped watcher or an old heartbeat may prevent reliable status. The UI shows the reason and last valid observation instead of treating old data as current.

**What has been tested?** See [v3.3 acceptance results](docs/TEST_RESULTS_V3_3.md), the [v3.2 performance baseline](docs/PERFORMANCE_V3_2.md) and [release checklist](docs/RELEASE_CHECKLIST.md). Results identify actual UI operations, disposable Windows Setup/WinINet tests, device limits and measured timings separately. No unexecuted item is reported as passed.

## Star History

If WiFi Proxy Pilot makes your workflow easier, consider giving the project a star.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

The official live SVG uses this Public repository's actual GitHub data. An empty history is valid when no star activity is available. No stars or growth are fabricated, and an empty history is not replaced with invented data. See the [official embedding guide](https://www.star-history.com/blog/how-to-use-github-star-history/).

## Contributing and roadmap

Issues and pull requests are welcome from users with repository access. Describe the build, expected/actual behavior and redacted evidence. See [CONTRIBUTING.md](CONTRIBUTING.md) for the Windows build and review process. Do not include personal configurations, proxy backups, credentials or unredacted logs.

This candidate adds installer ownership, bilingual resources and actual-control automation. Remaining acceptance limits are tracked in the test record, including hardware-specific Wi-Fi and DPI/Snap checks. Automatic updating is not implemented.

Build with the SDK in `global.json` and Windows PowerShell:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

The build produces `WiFiProxyPilot-Setup-x64.exe`, `WiFiProxyPilot-Portable-x64.zip` and `SHA256.txt` without installing them or modifying the build host proxy. Installed files use an unbundled self-contained runtime to avoid single-file unpacking at startup. Inno Setup 7.1.0 is pinned by checksum and verified upstream signatures. Internal `WiFiProxySwitcher` data, registry, mutex and task identifiers remain for upgrade compatibility. See the [build guide](docs/INSTALLATION_V3_3.md#build-and-verify).

## License

Project source is licensed under [MIT](LICENSE). Third-party materials retain their own terms; see [third-party notices](docs/THIRD_PARTY_NOTICES.md). System fonts are used from Windows and are not redistributed.
