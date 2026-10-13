# GitHub product delivery

Date: 2026-10-14 (Asia/Shanghai). Repository: [jeffxuu/WiFiProxyPilot](https://github.com/jeffxuu/WiFiProxyPilot), Private. Renaming reused repository ID `1414803349`; no new empty repository or history rewrite was used.

## Preserved history and integration

The full local history is restored (`is-shallow-repository=false`). The initial main commit `38799dcad92646ad11b6c2f3f1fc6afc2808bd95` is an ancestor of every product generation. v3.0 points to commit `85bfbd0` through its annotated tag; v3.1 ends at `2244a02`; v3.2 UI checkpoint is `08c224c59018fbda197c91c4ffbbe45d4e0b44f2`.

The checkpoint was pushed first to the old repository and independently verified using `git ls-remote` and the GitHub commit API. Renaming preserved the same repository ID and all branches/PRs/releases. Origin fetch/push now use the new URL and were exercised successfully. [Checkpoint commit](https://github.com/jeffxuu/WiFiProxyPilot/commit/08c224c59018fbda197c91c4ffbbe45d4e0b44f2).

The older [PR #1](https://github.com/jeffxuu/WiFiProxyPilot/pull/1) has been retargeted from the v3.0 feature branch to main. [PR #2](https://github.com/jeffxuu/WiFiProxyPilot/pull/2) integrates the complete v3.0/v3.1/v3.2 history and delivery updates into main using a normal merge commit after checks. It supersedes the smaller v3.1 proposal; preserved feature branches remain available. No force push, hard reset or destructive cleanup is used.

## Build and regression

The [Windows build and core regression workflow](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml) runs on v3.2 pushes, main pushes and PRs targeting main. It validates all eleven README files, their local image/document links, PowerShell engine regression, isolated transaction/rollback regression, launcher/status-reader contracts and the actual self-contained `win-x64` publish. It uploads versioned EXE/ZIP/SHA256 and test evidence for 30 days. It does not install the application, write the host proxy or run repeated UI smoke tests. The older v3.1 workflow remains clearly labeled as legacy.

Focused local results are committed under [docs/evidence](evidence/): upgrade 10/10, engine 8/8, launcher 45/45 and status 9/9. The actual lock tests reproduce transient/permanent Windows file handles and preserve destination contents on failure. See [test details](TEST_RESULTS_V3_2.md).

The temporary-path/sharing-lock blocker was repaired without changing WPF layouts, installation identity, original proxy backup or rollback protections. Real installed upgrades, network switching, login/sleep/uninstall acceptance and performance targets remain distinct release gates.

## Documentation, screenshots and Star History

English plus Simplified/Traditional Chinese, Japanese, Korean, Spanish, French, German, Brazilian Portuguese, Russian and Vietnamese are documentation translations. The shipped UI is currently Simplified Chinese. All README versions describe the same direct-rule/gateway behavior and distinguish Pause, Direct and original restore.

The Overview/Rules/Settings/Dark screenshots are real WPF captures with simulated network data. The dark capture uses an earlier layout. The new tray capture comes from the actual application's context menu in an isolated fixture; the targeted capture helper passed 5/5 checks and reports no real proxy/task writes. No screenshot claims real proxy connectivity.

The official `/svg` route is present in [Star History's current server implementation](https://github.com/star-history/star-history/blob/main/backend/main.ts). Both [light](https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date) and [dark](https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark) returned HTTP 200 and `image/svg+xml`, naming this repository. GitHub reports **0 stars and an empty stargazer list**. An empty chart is expected, not evidence of growth. Private repository history remains unavailable to anonymous GitHub clients; recheck the embed and external badges after publication. No new token, fabricated series or scheduled job was introduced.

## Releases and publication gates

v3.0.0 is the preserved published legacy release. v3.1.0 is a Draft Prerelease. v3.2.0-beta.1 is development source with build artifacts, not a published stable release. Download links identify these distinctions; existing release attachments are not replaced.

About and ten relevant topics were updated. Repository visibility remains Private. Historical enterprise-network examples and machine paths remain in commits and old release/test evidence; only safe present-day documentation path redactions were made, preserving measured performance samples. The owner must decide whether those historical values may be published or authorize a separate backed-up history cleanup. See [privacy audit](PUBLIC_REPOSITORY_AUDIT.md).

Making the repository Public, accepting publication of retained historical data, and promoting a beta release are separate owner decisions. No public-visibility change is included in this delivery.
