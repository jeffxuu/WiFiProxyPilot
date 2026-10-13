# Security and privacy

WiFi Proxy Pilot changes the current user's Windows manual proxy after explicit setup. It does not provide a VPN, proxy server, encryption or a guarantee that traffic uses a proxy. Safe mode can allow direct traffic after diagnostic failures. PAC and applications with independent settings may choose their own route.

## Reporting

If the repository Security tab offers private vulnerability reporting, use that channel. Otherwise contact the repository owner through an established private channel before posting sensitive details. Do not put credentials, real network names, proxy backups or exploit details in a public issue. Routine bugs can use a sanitized issue with version, expected/actual behavior and limited reproduction steps.

The repository is currently private. Private vulnerability reporting availability and response-time commitments are not claimed as configured.

## Scope and safeguards

- Operates under the current interactive user; rejects SYSTEM/service-session HKCU management and incorrect installation owners.
- Verifies payload SHA256, installation paths, owned tasks and files; protects against reparse paths and unknown ownership.
- Keeps the original manual-proxy snapshot; automatic restoration refuses to overwrite later external changes.
- Persists pause/direct intent and confirms it again before automatic writes.
- Does not collect analytics. Optional TCP/HTTP diagnosis contacts the configured endpoint/test URL.

Local configuration, status, logs and diagnostic output can contain SSIDs, gateways, user paths and proxy information. Sanitize before sharing. Keep original backups local. Check release SHA256 and signature status; do not disable Windows security to run an unsigned build.

Only the current v3.2 beta candidate is the active development target. It is not claimed to have passed all real Windows/network acceptance. Older history and release assets require the separate review described in [PUBLIC_REPOSITORY_AUDIT.md](docs/PUBLIC_REPOSITORY_AUDIT.md).
