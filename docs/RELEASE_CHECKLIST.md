# v3.2.0-beta.1 release checklist

WiFi Proxy Pilot is Public with owner confirmation. Main contains the complete product, international README navigation, simulated-network screenshots and actual Star History. Download assets are attached to the [Beta / Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1).

## Delivery checks

- Product/source history integrated into main with normal PR merge; no force push or history rewrite.
- Eleven substantive README languages, current-version downloads and five product screenshots.
- Self-contained Windows build, EXE/ZIP SHA256, MIT/runtime notices and package privacy exclusions.
- 119 engine, 10 upgrade/rollback/file-lock, 45 launcher/configuration/cache and 9 status checks; image/navigation validation.
- Empty user-owned rules; persisted Pause/Direct/Restore; original backup and external-change conflict protection.
- Obsolete display docs, releases/tags and merged feature branches removed with owner authorization; meaningful compatibility tests retained.

## Beta limitations

| Gate | Status |
| --- | --- |
| Real installed upgrade/uninstall with user rules and original backup | Pending |
| Actual hotspot switching, DHCP, permissions and proxy service behavior | Pending |
| Login/lock/sleep/reboot and real tray/Explorer lifecycle | Pending |
| Drag/Snap, monitor DPI, reduced motion/high contrast | Remaining manual checks |
| Startup target and cache-refusal investigation | Not passed; keep actual performance samples |
| Authenticode signing | Not signed |
| UI localization | Simplified Chinese only; README languages do not imply UI translations |
| Fully stable release | Not claimed; this is a Prerelease |

Real host changes require explicit authorization and a before/after record. Preserve current account, ownership guards, rules and original backup; do not overwrite them for branding. See [test evidence](TEST_RESULTS_V3_2.md), [performance](PERFORMANCE_V3_2.md), [migration](CONFIG_MIGRATION.md) and [delivery](GITHUB_DELIVERY.md).
