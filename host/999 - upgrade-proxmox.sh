#!/usr/bin/env bash
# SCRIPT_DESC: Upgrade Proxmox to latest version
# SCRIPT_DETECT: [ "$(apt list --upgradable 2>/dev/null | grep -c upgradable)" -eq 0 ]

echo ">>> Upgrading Proxmox VE to the latest version"
pveupgrade
echo ">>> Proxmox VE upgrade completed."