<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Smart Wi-Fi Proxy Switching for Windows</h3>
  <p>A lightweight, modern Windows utility that automatically switches your system proxy based on Wi-Fi SSIDs, gateway addresses and user-defined rules.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)
  [![MIT License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Your Wi-Fi changes. Your proxy follows.** Use a gateway-hosted proxy on ordinary Wi-Fi networks and connect directly on networks you choose. Manage it from a modern WPF desktop or the system tray.

> **v3.2.0-beta.1 is a Beta / Prerelease.** Screenshots show the actual WPF app with simulated network data. Real network, login/sleep, installation and uninstall acceptance remains separate from isolated regression tests. The current UI is Simplified Chinese; these README translations do not imply UI localization. The repository is Public.

## Screenshots

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
- Offers a macOS-inspired WPF interface, light/dark themes and a system tray with an independent background watcher.
- Separates automatic management, Windows manual-proxy state and optional TCP/HTTP diagnostics. An enabled proxy is not proof of internet access.
- Saves configuration atomically and distinguishes “saved” from “applied by the watcher.”
- Retains the original manual-proxy backup and protects later changes made by you or another application.
- Provides source code under MIT for inspection and contribution.

## Download and installation

**[Download v3.2.0-beta.1 — Beta / Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)**

[Windows x64 EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe) · [ZIP with documentation](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.zip) · [SHA256 checksums](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/SHA256.txt) · [Build verification](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)

This release contains the WPF interface shown above. It is a public prerelease, **not a fully validated stable release**. Review the release notes and compare SHA256 before installing. CI artifacts are also available to signed-in GitHub users but expire; the versioned Release assets are the recommended download.

The intended platform is **Windows 11 x64**, with Windows PowerShell 5.1, WLAN service and Windows Script Host. The self-contained EXE does not require separately installing .NET, Python, Node.js or WebView2. No broader Windows compatibility is claimed. Organization policies may restrict WLAN information, proxy settings or scheduled tasks. Current builds are unsigned; keep Windows security protections enabled.

Download the EXE or extract the ZIP and compare its hash with the accompanying `SHA256.txt`:

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

The executable remains `WiFiProxySwitcher.exe` for upgrade compatibility. Run it as your normal interactive Windows user. Opening the v3.2 window alone does not enable proxy management. Do not install for your everyday account using a different administrator's account.

## Quick Start

1. **Download** a build and check its version/hash.
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

The original manual-proxy backup is `state/proxy-before-install.json` under the installation directory. Upgrades preserve it and your rules; they do not create a new “original” backup. Configuration changes retain the previous valid file. Keep these local files private.

For an existing installation, open the candidate EXE and use **Settings → Advanced operations → Repair installation / Upgrade**. Do not uninstall first or overwrite your configuration with repository defaults. See [configuration migration](docs/CONFIG_MIGRATION.md).

Use **Restore original configuration**, **Settings → Advanced operations → Uninstall**, or Windows Installed Apps. Restore/uninstall compares current settings with the original and last settings written by this tool. Later external edits cause a conflict instead of being overwritten. Force restore is an explicit choice; uninstall can also keep the current proxy. Removal is limited to owned tasks/startup records and verified product files, protecting unrelated or user-modified files. Direct mode keeps the original backup.

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

**What has been tested?** See [v3.2 test results](docs/TEST_RESULTS_V3_2.md), [performance evidence](docs/PERFORMANCE_V3_2.md) and [release checklist](docs/RELEASE_CHECKLIST.md). Isolated checks are not real network or installation acceptance, and target performance is not a measured result.

## Star History

If WiFi Proxy Pilot makes your workflow easier, consider giving the project a star.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

The official live SVG uses this Public repository's actual GitHub data. On 2026-10-14 GitHub reports **0 stars**, so an empty history is expected. Both light and dark URLs return HTTP 200. No stars or growth are fabricated, and an empty history is not replaced with invented data. See the [official embedding guide](https://www.star-history.com/blog/how-to-use-github-star-history/).

## Contributing and roadmap

Issues and pull requests are welcome from users with repository access. Describe the build, expected/actual behavior and redacted evidence. See [CONTRIBUTING.md](CONTRIBUTING.md) for the Windows build and review process. Do not include personal configurations, proxy backups, credentials or unredacted logs.

Planned work: real upgrade/login/sleep/uninstall acceptance, remaining WPF accessibility and layout checks, startup performance improvements, and UI localization. These are plans, not shipped features; automatic updating is not implemented.

Build with the SDK in `global.json` and Windows PowerShell:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

The build creates a self-contained `win-x64` EXE without installing it or changing the host proxy. The existing `WiFiProxySwitcher` installation, registry, mutex and task identities remain for compatibility.

## License

Project source is licensed under [MIT](LICENSE). Third-party materials retain their own terms; see [third-party notices](docs/THIRD_PARTY_NOTICES.md). System fonts are used from Windows and are not redistributed.
