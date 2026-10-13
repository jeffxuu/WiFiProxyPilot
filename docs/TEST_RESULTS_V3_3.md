# v3.3.0-beta.1 verification evidence

This file records executed tests separately from required acceptance that has not run. It is updated after the final package and Windows Actions run; a source build or fixture screenshot does not certify installation.

## Local regression

On Windows 11 Enterprise 10.0.26200, using .NET SDK 8.0.425 / runtime 8.0.31:

| Verification | Executed result | Scope |
| --- | --- | --- |
| Existing PowerShell engine suite | 119/119 passed | Production engine functions with isolated injected boundaries; includes real TCP/HTTP fixture servers |
| Upgrade transaction suite | 10/10 passed | Actual file staging, rollback and Windows file locks; simulated task services |
| Launcher/cache/configuration | 45/45 passed | Actual cache hashing, config persistence, safe arguments and identity evaluator |
| Production status reader | 9/9 passed | Real reader linked with forbidden Windows boundary stubs |
| Localization | 7/7 passed | ResourceManager satellite resources, all key/placeholder parity, display-language fallback, runtime bindings and preferences |
| Installer regression | 7/7 passed | Ownership, cancellation preflight, package completeness and failure receipt checks |

Actual WPF UI Automation runs operate native caption buttons and real WPF controls. Their assertions read the JSON file after edit/save and the independent Watcher heartbeat after installed management commands. UIA peers invoke the control's `OnClick`; tests do not call ViewModel methods. Early failed runs remain under `artifacts/uia-v33-*` and must not be counted as passed. Final execution evidence will identify the exact executable/package hash.

## Disposable Windows installed acceptance

`tests/Installed.Acceptance.ps1` refuses to run unless both `GITHUB_ACTIONS=true` and `RUNNER_ENVIRONMENT=github-hosted`. It backs up the current user's original manual proxy before testing, and restores it in `finally`. This is a real Setup EXE test, not a direct substitute call to the installer functions.

The workflow tests software installation without activation; repeated setup; a Chinese/space path; one Installed Apps entry; Start menu and desktop shortcut target/icons; actual WPF controls; explicit first activation; pause/resume; real manual proxy on/off, port and bypass readback; upgrade preservation; conflicting uninstall cancellation; restoration; owned-task/startup removal; retained user data; and migration from the actual v3.2 release binary.

Execution is pending the first pushed build. No installed-lifecycle pass is claimed here yet. The Windows hosted image may be Windows Server rather than Windows 11; its exact OS/session is recorded. This provides real WinINet/task/installer verification in a disposable Windows environment, with separate local Windows 11 WPF evidence.

## Physical and shell behavior

No actual Wi-Fi disconnect/reconnect, daily-computer proxy change, live Explorer restart, Windows language setting or display scaling change has been performed. Hosted runners have no physical Wi-Fi adapter. Existing injected monitor tests verify stable network changes and preserve unknown-state safeguards; they do not prove physical WLAN events on the user's hardware.

Native WPF non-client chrome delegates sizing, caption rendering, Snap layouts and work-area behavior to Windows. Actual maximize/restore/minimize/close operations are tested. Multi-monitor DPI transitions, Snap flyout display and Explorer restart remain separate device/shell checks until directly exercised. The explicit PerMonitorV2 manifest and icon-size resources are implementation evidence, not claims those checks ran.

## Evidence locations

- `release/generated/build-record.json`: final build dependency/runtime/package hashes.
- `release/dist/SHA256.txt`: Setup and portable archive hashes.
- `release/generated/installed-acceptance/installed-results.json`: actual lifecycle result, package hash, OS, session and retained failures.
- `release/generated/installed-acceptance/*-uia/`: UIA results, accessible text and actual bounded window captures.
- `docs/PERFORMANCE_V3_3.md`: actual measured startup and resident restoration evidence.

An independent prerelease can be published only with passing installed acceptance and matching package hashes. The existing v3.2 release is preserved. No stable-release claim is made.
