#!/usr/bin/env bash
# SCRIPT_DESC: (Retired) Old AMD-only container script - use 031 (privileged) or 032 (unprivileged) instead
# SCRIPT_DETECT: 
# SCRIPT_RETIRED: 1

# This number is kept on purpose so nobody runs into "script not found" and existing notes stay valid.
# The original script (privileged, AMD only, hardcoded IP/MAC/PCI address) has been retired; both
# successors ask for everything interactively and support AMD and NVIDIA. History: git log -- "host/030 - create-amd-lxc.sh"

echo "Script 030 has been retired."
echo ""
echo "It was the first, AMD-only version with fixed values for IP, MAC and PCI address."
echo "Its successors do the same job for AMD and NVIDIA and ask for all values:"
echo ""
echo "  031 - GPU container, privileged   (simple, less isolated from the host)"
echo "  032 - GPU container, unprivileged (recommended, better isolated from the host)"
echo ""
echo "Please run 031 or 032 from the menu."
exit 0
