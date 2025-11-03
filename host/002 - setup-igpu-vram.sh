#!/usr/bin/env bash
# SCRIPT_DESC: Setup AMD APUs iGPU VRAM allocation
# SCRIPT_DETECT: grep -q "amdgpu.gttsize=98304" /proc/cmdline 2>/dev/null

echo ">>> Setting iGPU VRAM and related parameters in kernel cmdline"

# Define the parameters to add
amdgpu_vram_string="amdgpu.gttsize=98304 ttm.pages_limit=25165824 ttm.page_pool_size=25165824"

# Check if the system is using ZFS (has /etc/kernel/cmdline)
if [ -f /etc/kernel/cmdline ]; then
    echo ">>> Detected ZFS system - using /etc/kernel/cmdline"
    
    # Check if the string is already in the first line
    if ! grep -q "$amdgpu_vram_string" /etc/kernel/cmdline; then
        echo ">>> Adding missing parameters to kernel cmdline"
        sed -i "1s/$/ $amdgpu_vram_string/" /etc/kernel/cmdline
        echo ">>> Refreshing Proxmox boot tool to apply changes"
        proxmox-boot-tool refresh
        echo ">>> Please now reboot the system"
    else
        echo ">>> Parameters already present in kernel cmdline, no changes needed"
    fi
else
    echo ">>> Detected non-ZFS system - using /etc/default/grub"
    
    # Check if the parameters are already present in grub
    if ! grep -q "amdgpu.gttsize=98304" /etc/default/grub; then
        echo ">>> Adding missing parameters to GRUB configuration"
        # Get the current GRUB_CMDLINE_LINUX_DEFAULT value
        current_cmdline=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/\1/')
        
        # Append the new parameters to the existing value
        new_cmdline="$current_cmdline $amdgpu_vram_string"
        
        # Update the grub configuration
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" /etc/default/grub
        
        echo ">>> Updating GRUB"
        update-grub
        echo ">>> Please now reboot the system"
    else
        echo ">>> Parameters already present in GRUB configuration, no changes needed"
    fi
fi
