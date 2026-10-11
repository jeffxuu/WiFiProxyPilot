#!/usr/bin/env bash
set -euo pipefail
# Linux validation tool only. Windows runtime uses its built-in PowerShell 5.1.
tool_root=/workspace/tooling
ps_root="$tool_root/powershell"
mkdir -p "$ps_root" "$tool_root/xdg-cache" "$tool_root/xdg-config" "$tool_root/xdg-data"
if ! test -x "$ps_root/pwsh"; then
  download_dir=$(mktemp -d /tmp/wifi-powershell.XXXXXX)
  trap 'rm -rf "$download_dir"' EXIT
  curl --fail --location --retry 2 --output "$download_dir/powershell.tar.gz" https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-linux-x64.tar.gz
  # SHA256 from the official v7.4.6 release hashes.sha256, retrieved and verified during onboarding.
  printf '%s  %s\n' '6f6015203c47806c5cc444c19d8ed019695e610fbd948154264bf9ca8e157561' "$download_dir/powershell.tar.gz" | sha256sum --check --strict
  tar -xzf "$download_dir/powershell.tar.gz" -C "$ps_root"
  chmod +x "$ps_root/pwsh"
fi
export XDG_CACHE_HOME="$tool_root/xdg-cache"
export XDG_CONFIG_HOME="$tool_root/xdg-config"
export XDG_DATA_HOME="$tool_root/xdg-data"
cd /workspace/WiFi-test
"$ps_root/pwsh" -NoLogo -NoProfile -File tests/Run-Tests.ps1 -ResultPath /tmp/wifi-test-results.json
