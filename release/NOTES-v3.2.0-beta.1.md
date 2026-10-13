# WiFi Proxy Pilot v3.2.0-beta.1

Public WPF beta for Windows 11 x64: automatically manage the current user's Windows manual proxy using user-owned Wi-Fi rules and the current Wi-Fi interface's IPv4 gateway.

## Included

- WPF Overview, editable Wi-Fi Rules, Settings, diagnostics and light/dark themes.
- System tray with an independent watcher; closing/exiting the interface leaves the watcher running.
- Empty default direct-connection rules, configurable proxy port and exact case-insensitive SSID matching.
- Separate Pause, Direct and original Restore operations; atomic configuration, conflict checks, original-proxy backup and protected upgrades/uninstall.
- Short upgrade temporary filenames, bounded Windows sharing-lock retries and verified rollback protections.
- Eleven full README languages; the application UI is currently Simplified Chinese.

## Download

`WiFiProxySwitcher.exe` is the self-contained Windows x64 executable; `WiFiProxySwitcher.zip` includes the executable, multilingual documentation, screenshots and licenses. The compatible executable/install identities remain unchanged. Compare the downloaded file's SHA256 with `SHA256.txt`.

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

## Verification and limitations

Windows CI passes 119 engine checks, 10 isolated upgrade/rollback/file-lock checks, 45 launcher/configuration/cache checks, 9 production-status-reader checks, README/image validation and the self-contained build. These are isolated checks, not proof of real network or installed lifecycle acceptance.

**This is a Prerelease, not a fully validated stable release.** Real installed upgrade, Wi-Fi switching, login/sleep and uninstall acceptance remains pending. Builds are unsigned. Keep Windows security protections enabled. This tool provides no VPN or proxy server: the chosen gateway/port must already run a reachable proxy service. An enabled manual proxy and a TCP-open diagnosis do not guarantee internet access.

For an existing installation, use Settings → Advanced operations → Repair installation / Upgrade. Keep your configuration and original proxy backup; do not uninstall first or replace your rules with repository defaults. Pause retains the current proxy; Direct pauses management and disables the manual proxy; original Restore respects later external changes.
