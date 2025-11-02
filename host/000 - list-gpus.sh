#!/usr/bin/env bash

# Simple script to list all GPUs and their PCI paths
# Useful for identifying which GPU to assign to which LXC container

echo "=========================================="
echo "GPU Detection and PCI Path Listing"
echo "=========================================="
echo ""

echo "=== All GPUs Detected (from lspci) ==="
lspci -nn -D | grep -E "VGA|3D|Display" | while read -r line; do
    pci=$(echo "$line" | cut -d' ' -f1)
    desc=$(echo "$line" | cut -d: -f3-)
    
    vendor="Unknown"
    if echo "$desc" | grep -qi amd; then
        vendor="AMD"
    elif echo "$desc" | grep -qi nvidia; then
        vendor="NVIDIA"
    elif echo "$desc" | grep -qi intel; then
        vendor="Intel"
    fi
    
    echo "[$vendor] $pci -$desc"
done

echo ""
echo "=== DRI Device Mappings (Persistent Paths) ==="
echo "Use these PCI addresses in your LXC configurations:"
echo ""

if [ ! -d /dev/dri/by-path ]; then
    echo "ERROR: /dev/dri/by-path not found. GPU drivers may not be loaded."
    exit 1
fi

for card in /dev/dri/by-path/pci-*-card; do
    if [ -e "$card" ]; then
        # Extract PCI address
        pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
        
        # Get current card and render device links
        card_dev=$(readlink -f "$card" 2>/dev/null | xargs basename)
        render_path="${card%-card}-render"
        render_dev=$(readlink -f "$render_path" 2>/dev/null | xargs basename || echo "N/A")
        
        # Get GPU info
        gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -E "VGA|3D|Display" | cut -d: -f3- || echo "Unknown GPU")
        
        # Determine vendor
        vendor="Unknown"
        if echo "$gpu_info" | grep -qi amd; then
            vendor="AMD"
        elif echo "$gpu_info" | grep -qi nvidia; then
            vendor="NVIDIA"
        elif echo "$gpu_info" | grep -qi intel; then
            vendor="Intel"
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "PCI Address: $pci_addr [$vendor]"
        echo "Description:$gpu_info"
        echo "Current Mapping:"
        echo "  Card:   $card_dev"
        echo "  Render: $render_dev"
        echo ""
        echo "Use in LXC config:"
        echo "  lxc.mount.entry: /dev/dri/by-path/pci-${pci_addr}-card dev/dri/card0 none bind,optional,create=file"
        echo "  lxc.mount.entry: /dev/dri/by-path/pci-${pci_addr}-render dev/dri/renderD128 none bind,optional,create=file"
        echo ""
    fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "=== Additional Devices ==="

# Check for KFD (AMD ROCm)
if [ -e /dev/kfd ]; then
    echo "✓ /dev/kfd found (AMD ROCm support available)"
else
    echo "✗ /dev/kfd not found (AMD ROCm not available)"
fi

# Check for NVIDIA devices
if ls /dev/nvidia* >/dev/null 2>&1; then
    echo "✓ NVIDIA devices found:"
    ls -1 /dev/nvidia* | head -5
else
    echo "✗ No NVIDIA devices found"
fi

echo ""
echo "=========================================="
echo "Use the PCI addresses above when creating"
echo "LXC containers with GPU passthrough"
echo "=========================================="
