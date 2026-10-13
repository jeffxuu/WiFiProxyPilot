# v3.2 verification and acceptance boundaries

2026-10-14 · SDK 8.0.425, .NET 8/WPF, Windows PowerShell 5.1. The source is a public Beta; isolated regression is not real installed-network acceptance.

## Core verification

| Scope | Result | Evidence |
| --- | --- | --- |
| Complete Windows engine regression | 119/119 passed | [Windows CI](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml) |
| Upgrade staging, migration, original backup, partial/incomplete rollback, actual transient/permanent Windows locks and long paths | 10/10 passed | [upgrade](evidence/github-delivery-upgrade.json) |
| Focused engine syntax, upgrade and persisted state semantics | 8/8 passed | [focused engine](evidence/github-delivery-engine.json) |
| Launcher/configuration/cache contracts | 45/45 passed | [launcher](evidence/github-delivery-launcher.json) |
| Actual production status reader with forbidden Windows boundaries | 9/9 passed | [status](evidence/github-delivery-status.json) |
| Actual existing homepage and tray-menu capture | 5/5 passed; ProxyWritten=false, TaskWritten=false | [capture](evidence/github-delivery-ui.json) |
| Self-contained win-x64 EXE/ZIP/SHA256, eleven READMEs and image/document links | Passed | [build and package](GITHUB_DELIVERY.md) |

Upgrade temporary names use a short independent basename in the destination directory. Replacement retries are bounded to Windows sharing/lock HResults; permanent failures preserve rollback and path diagnostics. Fault-injection tests require the intended fault to be reached. Hash validation, original backups and incomplete-recovery startup blocks were not weakened.

## Isolated behaviors covered

- Every direct rule can be edited/deleted; an empty list persists. SSID UTF-8 byte limits, legal spaces, exact case-insensitive matching and revision conflicts remain checked.
- Saved and Applied are distinct: fresh compatible watcher revisions and a stable network must agree before application is reported.
- Pause, Direct and Restore retain separate persisted intent. Opening the GUI does not manufacture automatic-management success.
- Stable Wi-Fi/gateway selection avoids mixing network data. Unknown diagnosis is not recovery; TCP-open is not HTTP or general internet success.
- GUI exit and tray/window lifetime are independent of the watcher. Status failure clears stale success/address; external proxy deviation invalidates diagnostics.
- Migration/ownership/rollback protect original backup, rules and configuration edits. Only verified owned files/tasks are eligible for uninstall.

## Real Windows acceptance still pending

Local captures were made on Windows 11 10.0.26200 at actual desktop DPI with simulated network fixtures. CI provides build and isolated regression on its Windows runner, not complete Windows 11 network acceptance.

| Operation | Evidence / remaining work |
| --- | --- |
| WPF render and tray menu | Captured and visually inspected; isolated state |
| Maximize/restore and keyboard focus | Focused native checks passed; physical drag/Snap/multi-monitor interactions remain manual |
| Real hotspot switching, DHCP and WLAN permissions | Not performed |
| Real Pause/Direct/original Restore writes | Not performed; live proxy is protected |
| Installed upgrade | Isolated migration/rollback/lock checks passed; real installed upgrade not accepted |
| Login/lock/sleep/reboot | Isolated/static coverage; real acceptance pending |
| Uninstall/Explorer restart | Not performed |
| Startup performance | Not certified; actual samples/failed rows remain in [performance](PERFORMANCE_V3_2.md) |

No real host proxy/task write, installation/uninstall, network change or Explorer restart is part of isolated checks. Keep Beta and unsigned status explicit. Source/download verification is recorded in [GitHub delivery](GITHUB_DELIVERY.md).
