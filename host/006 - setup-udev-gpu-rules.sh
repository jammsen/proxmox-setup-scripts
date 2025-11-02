#!/usr/bin/env bash
echo ">>> Setting up UDEV rules for persistent GPU device naming"

cat > /etc/udev/rules.d/99-gpu-passthrough.rules << 'EOF'
# Allow access to DRI devices for unprivileged LXC containers
# This rule applies to all card and render devices
KERNEL=="card[0-9]*", SUBSYSTEM=="drm", MODE="0660", GROUP="video"
KERNEL=="renderD[0-9]*", SUBSYSTEM=="drm", MODE="0660", GROUP="video"
KERNEL=="kfd", SUBSYSTEM=="kfd", MODE="0666"

# NVIDIA devices
KERNEL=="nvidia*", MODE="0666"
KERNEL=="nvidia-uvm*", MODE="0666"
KERNEL=="nvidia-modeset", MODE="0666"
KERNEL=="nvidiactl", MODE="0666"
EOF

echo ">>> Reloading UDEV rules and triggering changes"
udevadm control --reload-rules
udevadm trigger

echo ">>> Verifying UDEV rules for GPU devices"
ls -la /dev/dri/ /dev/kfd
echo ">>> Listing should show crw-rw---- root video"

echo ""
echo ">>> Verifying GPU devices and their PCI paths"
echo "=== /dev/dri/ devices ==="
ls -la /dev/dri/
echo ""
echo "=== Persistent PCI paths (USE THESE FOR LXC MAPPING) ==="
ls -la /dev/dri/by-path/
echo ""
echo "=== KFD device (for AMD ROCm) ==="
ls -la /dev/kfd 2>/dev/null || echo "KFD not found (normal if no AMD GPU or driver not loaded)"
echo ""
echo "=== NVIDIA devices ==="
ls -la /dev/nvidia* 2>/dev/null || echo "NVIDIA devices not found (normal if no NVIDIA GPU)"
echo ""
echo ">>> IMPORTANT: Use the paths from /dev/dri/by-path/ in your LXC configurations"
echo ">>> These paths are stable and won't change between reboots"
