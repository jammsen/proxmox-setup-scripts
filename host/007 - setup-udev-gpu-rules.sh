#!/usr/bin/env bash
# SCRIPT_DESC: (Retired) udev rules for GPU device permissions - no longer needed by 031/032
# SCRIPT_DETECT: 
# SCRIPT_RETIRED: 1

# This number is kept on purpose so nobody runs into "script not found" and existing notes stay valid.
# The original script wrote /etc/udev/rules.d/99-gpu-passthrough.rules to loosen host permissions on
# /dev/dri, /dev/kfd and /dev/nvidia*. That was only needed for the old way of bind-mounting host device
# nodes into unprivileged containers. Script 031 (privileged) never needed it and script 032 uses
# Proxmox device passthrough (dev0, dev1, ...), which creates its own device nodes with the right
# permissions inside the container. History: git log -- "host/007 - setup-udev-gpu-rules.sh"

echo "Script 007 has been retired."
echo ""
echo "It used to install udev rules that loosen the GPU device permissions on the Proxmox host."
echo "The container scripts 031 and 032 no longer need this: 032 uses Proxmox's built-in device"
echo "passthrough, which sets the permissions inside the container by itself."
echo ""
if [ -f /etc/udev/rules.d/99-gpu-passthrough.rules ]; then
    echo "The rules file from an earlier run is still present on this host:"
    echo "  /etc/udev/rules.d/99-gpu-passthrough.rules"
    echo "It does no harm, but you can remove it and restore the default permissions with:"
    echo "  rm /etc/udev/rules.d/99-gpu-passthrough.rules && udevadm control --reload-rules && udevadm trigger"
    echo ""
    read -r -p "Remove the old rules file now? [y/N]: " REMOVE_RULES
    if [[ "${REMOVE_RULES:-N}" =~ ^[Yy]$ ]]; then
        rm -f /etc/udev/rules.d/99-gpu-passthrough.rules
        udevadm control --reload-rules
        udevadm trigger
        echo "Removed. Default device permissions are back in effect."
    else
        echo "Left in place."
    fi
else
    echo "No rules file from an earlier run was found on this host - nothing to clean up."
fi
exit 0
