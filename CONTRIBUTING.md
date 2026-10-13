# Contributing

Build on the complete WiFi Proxy Pilot source in main, preserve user configuration and meaningful regression checks, and focus changes on a concrete user problem. The repository is Public. Beta download assets are attached to the versioned Release; source, documentation and download versions must agree.

## Development

Use Windows 11 x64, the repository's pinned .NET 8 SDK and Windows PowerShell 5.1. Run focused checks for the changed risks; the main/PR Windows workflow runs engine, upgrade-transaction, launcher and status-reader regression with the self-contained build. `release/Build.ps1` builds the EXE and runs launcher checks. Desktop self-tests and performance measurements use isolated fixture directories and must not touch the host proxy or tasks.

Keep UI work in WPF view models/application services. Reuse the existing WLAN/WinINet engine, atomic configuration and revision checks, payload integrity cache, task ownership and safe restore logic. Preserve installation identity compatibility. New dependencies need a fixed version and applicable license notices.

## Test expectations

Test the risks introduced by the change: rule removal/empty lists, stable gateway selection, persisted management intent, last-write races, restoration conflicts, migration and lifecycle. Avoid repetitive test loops or tests that merely repeat the implementation. Keep existing useful safety assertions.

Real proxy writes, installation/uninstall, Task Scheduler changes, Explorer restart or changing the developer's network require explicit authorization. Label simulation, isolated desktop checks and real Windows acceptance separately. Record failures and unverified items honestly; performance reports include raw samples, device/runtime, EXE SHA256 and measurement limits.

## Pull requests

Explain the user-visible problem and resulting behavior, then include relevant checks and remaining limits. Provide real screenshots for UI changes using simulated/redacted network data. Never commit personal SSIDs, actual private network addresses, installed configurations, proxy backups, logs, secrets, signing keys or debug dumps.

Security reports follow [SECURITY.md](SECURITY.md). Contributions to project source are under [MIT](LICENSE); third-party materials retain their own licensing.
