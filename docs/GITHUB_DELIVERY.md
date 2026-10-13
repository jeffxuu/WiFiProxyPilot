# WiFi Proxy Pilot v3.2 delivery

Repository: [jeffxuu/WiFiProxyPilot](https://github.com/jeffxuu/WiFiProxyPilot), **Public**, confirmed by the owner on 2026-10-14 (Asia/Shanghai).

## Product source and download

The default main branch contains the complete PowerShell engine, .NET 8/WPF desktop, system tray, configuration/migration safeguards and eleven README languages. Product presentation consistently uses WiFi Proxy Pilot; executable and internal installation identities remain WiFiProxySwitcher for compatibility.

Download the **[v3.2.0-beta.1 Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)**. Its EXE, documentation ZIP and SHA256 file are built from the tagged product source. Beta status is explicit; real installation/network lifecycle acceptance is not claimed.

The owner requested removal of obsolete Release/tag records, display documentation and merged feature branches. The remote branch list is consolidated to main after the release merge. Actual commit history and meaningful upgrade/network/ownership regression tests remain. A verified complete Git bundle was saved locally before cleanup; no force push or history rewrite is used.

## Build and verification

The [Windows build workflow](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml) validates eleven READMEs and relative images/documents, runs 119 isolated engine checks, ten upgrade/rollback/Windows file-lock checks, 45 launcher/cache/configuration checks and nine production-status-reader checks, then creates a self-contained win-x64 EXE, ZIP and SHA256. Evidence is available in Actions artifacts. The obsolete draft-release workflow has been removed.

Committed [verification evidence](evidence/) and [test boundaries](TEST_RESULTS_V3_2.md) distinguish isolated regression from real Windows acceptance. Original proxy backups, configuration ownership, atomic revisions and task/mutex identities remain protected. Long-path/shared-lock upgrade handling preserves valid destination and rollback safeguards.

The README shows actual Overview, Rules, Settings, Tray and Dark Theme captures from an isolated simulated network. Both [light](https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date) and [dark](https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark) Star History SVGs return HTTP 200. GitHub reports zero stars as of 2026-10-14; an empty history is expected and no growth is fabricated.

## Remaining beta work

Real installed upgrades, Wi-Fi switching, login/sleep/uninstall acceptance, remaining accessibility/window interactions, startup performance and signing are tracked in [the release checklist](RELEASE_CHECKLIST.md). See [performance samples](PERFORMANCE_V3_2.md), [migration](CONFIG_MIGRATION.md) and [privacy audit](PUBLIC_REPOSITORY_AUDIT.md). These limits remain visible even though the repository and Beta are public.
