# v3.2 visual checkpoint verification

2026-10-14 · Windows 11 10.0.26200, SDK 8.0.425, Windows PowerShell 5.1. This is a reviewable UI checkpoint, not completed release acceptance.

## Evidence and results

| Scope | Actual result | Evidence |
| --- | --- | --- |
| Original C# baseline | 37/37 passed before changes | artifacts/baseline-launcher-v32.json |
| Corrected isolated v3.1 engine baseline | 112/113 initially; original stop-time assertion then passed separately | artifacts/test-results-v31-isolated-baseline.json; test-results-v31-baseline-corrected-stop.json |
| Configuration, identity, safe cache and new state contracts | 45/45 passed | artifacts/test-results-core-preview-final.json |
| Actual C# status reader with forbidden Windows boundaries | 9/9 passed | artifacts/test-results-status-preview-final.json |
| Stage-one engine semantics/hot reload | 15/15 targeted checks passed | artifacts/test-results-engine-stage1-v3.2.json |
| Upgrade rollback | 6/7 first run; one test BOM correction, failed case alone then passed | artifacts/upgrade-transaction-results.json; upgrade-transaction-recovery-result.json |
| Active engine protocol | One focused cross-process simulated mutex test passed | artifacts/engine-protocol-test.json |
| Initial actual WPF interaction/render verification | 15/15 passed after actual rendering repairs | artifacts/macos-visual-preview/smoke.json |
| Refined light homepage only | 4/4 passed | artifacts/home-refinement/review.json |
| Complete engine regression at checkpoint | 115/119 initially; syntax and two outdated test assumptions corrected and separately passed; **one upgrade test remains failed** | artifacts/core-regression-preview.json; core-regression-preview-syntax-corrected.json; core-regression-targeted-repairs.json |

The remaining failure is the existing V31 isolated upgrade preservation case: File.Replace reports a sharing lock and installation safely rolls back. It reproduced in the targeted retry. Its safety assertion was not weakened or deleted. It blocks release readiness; precise path diagnostics and bounded replacement retry need further installation work. The user's current round is homepage refinement, so no PowerShell engine change was made to conceal this failure.

The first non-isolated concurrent baseline attempt was unsuitable: later test files observed in-progress product changes. Its 110/113 report remains in artifacts/baseline-v32.json rather than being presented as a pristine baseline. The isolated baseline retained all security assertions with representative transitions instead of thousands of loops. Its single timing failure was a sampling-script substitution mistake, corrected using the original 2000ms assertion and recorded separately. No reports were merged into a fictional all-green run.

WPF captures come from the actual running visual tree at 125% DPI. The initial render iteration exposed a global-resource scope error, native-handle initialization error, opaque navigation tiles and a failed dark resource switch; these were repaired before the successful captures. The homepage refinement checks only the changed flow. They do not rerun hundreds of launches or synthetic DPI screenshots.

## Behaviors verified in isolation

- No rule is protected; original legacy names can be removed, empty lists persist, and reload does not inject names.
- UTF-8 32-byte bounds, control-character rejection, legal spaces, OrdinalIgnoreCase deduplication and atomic revision conflict checks remain.
- Saving differs from application: compatible fresh stable heartbeat revisions must agree before application is shown. Negative rule-reason text cannot be mistaken for a rule hit.
- Pause, Direct and Restore have separate persisted intents; startup does not set Monitoring. Updated disk scripts cannot authorize an old resident engine.
- Fast network changes cannot use a mixed/old gateway; unknown diagnosis cannot pretend recovery; original IPv4/WLAN/WinINet/ownership protections remain tested.
- Status read failure clears diagnostic success and current address; actual server deviation invalidates old diagnosis/healthy state.
- X hides WPF, tray reopen reuses the window, simulated TaskbarCreated recovers the icon, and GUI exit does not call watcher stop/proxy restore.
- The refined switch is OneWay state plus an async command, so initial binding does not write proxy. An isolated failed action cannot show fake success.
- Native WPF maximize/restore and keyboard focus worked in the targeted check. Real dragging/Snap and monitor transitions are separate manual checks.

## Windows manual acceptance record

| Operation | Expected | Actual | Result / reason |
| --- | --- | --- | --- |
| Launch review EXE | Actual window and current fixture data | Rendered, screenshot saved | Passed with synthetic network |
| Maximize / restore / keyboard focus | Native window state and focus respond | Targeted commands and focus succeeded | Passed; physical mouse interaction still manual |
| Close / tray reopen / GUI exit | Watcher and proxy unaffected | Fixture unchanged, tray/window lifetime verified | Simulated; real before/after network not tested |
| Drag / Snap hover / multi-monitor DPI / reduced motion / high contrast | Native interactions and accessible rendering | Not performed | Manual UI acceptance pending |
| Real hotspot A → B / DHCP / WLAN permissions | Stable current interface/gateway with clear failures | Not performed | Needs authorized network changes |
| Real Pause / Direct / original Restore | Distinct intended effects, conflict protection | Not performed | Current real proxy is in use; authorization required |
| Existing-version install upgrade | Rules/original backup survive, rollback works | Simulations only; one sharing-lock test failed | Not accepted |
| Login / lock / sleep / reboot | Persisted intent and fresh resampling | Static/isolated coverage only | Real lifecycle acceptance pending |
| Real uninstall / Explorer restart | Own-file cleanup and conflict protection; icon returns | Not performed | Authorization required |

Current installed GUI/Watcher, HKCU proxy settings, task ownership, original backup and repository visibility were audited read-only. No genuine proxy write, task install/uninstall, Explorer restart or network change was performed by these checks.

Performance is not passed; see PERFORMANCE_V3_2.md. The current EXE/ZIP SHA256 file identifies a visual preview, not a publicly released beta.
