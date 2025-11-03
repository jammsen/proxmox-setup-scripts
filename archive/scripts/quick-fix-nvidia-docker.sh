#!/usr/bin/env bash

# Quick fix for NVIDIA Docker in LXC containers
# Run this if Docker GPU test fails but nvidia-smi works on host

echo "=========================================="
echo "NVIDIA Docker Quick Fix for LXC"
echo "=========================================="
echo ""

# Fix 1: Ensure no-cgroups is set correctly
echo "1. Fixing no-cgroups setting..."
if [ -f /etc/nvidia-container-runtime/config.toml ]; then
    # Remove all existing no-cgroups lines
    sed -i '/no-cgroups/d' /etc/nvidia-container-runtime/config.toml
    
    # Add it uncommented at the top of the file
    sed -i '1i no-cgroups = true' /etc/nvidia-container-runtime/config.toml
    
    echo "✓ Set no-cgroups = true"
    echo ""
    echo "Current config:"
    head -5 /etc/nvidia-container-runtime/config.toml
else
    echo "✗ Config file not found!"
    exit 1
fi

echo ""
echo "2. Verifying Docker daemon configuration..."
cat /etc/docker/daemon.json

echo ""
echo "3. Restarting Docker..."
systemctl daemon-reload
systemctl restart docker
sleep 2

echo ""
echo "4. Testing GPU in Docker..."
docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi

if [ $? -eq 0 ]; then
    echo ""
    echo "✓✓✓ SUCCESS! GPU is now working in Docker! ✓✓✓"
else
    echo ""
    echo "✗ Still failing. Additional troubleshooting needed."
    echo ""
    echo "Checking library paths..."
    ldconfig -p | grep nvidia
    echo ""
    echo "Checking device permissions..."
    ls -la /dev/nvidia* /dev/dri/
fi
