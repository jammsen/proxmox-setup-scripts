#!/usr/bin/env bash

# NVIDIA Docker troubleshooting script for LXC containers

echo "=========================================="
echo "NVIDIA Docker Troubleshooting for LXC"
echo "=========================================="
echo ""

echo "1. Checking GPU device access..."
echo "-----------------------------------"
if ls /dev/nvidia* >/dev/null 2>&1; then
    ls -la /dev/nvidia*
    echo "✓ NVIDIA devices found"
else
    echo "✗ No NVIDIA devices found!"
    echo "  Fix: Check LXC config has proper device mounts"
fi
echo ""

if ls /dev/dri/* >/dev/null 2>&1; then
    ls -la /dev/dri/
    echo "✓ DRI devices found"
else
    echo "✗ No DRI devices found!"
fi
echo ""

echo "2. Checking NVIDIA runtime configuration..."
echo "-------------------------------------------"
if [ -f /etc/nvidia-container-runtime/config.toml ]; then
    echo "no-cgroups setting:"
    grep "no-cgroups" /etc/nvidia-container-runtime/config.toml
    
    if grep -q "no-cgroups = true" /etc/nvidia-container-runtime/config.toml; then
        echo "✓ no-cgroups is set to true (correct for LXC)"
    else
        echo "✗ no-cgroups is NOT set to true!"
        echo "  Fix: Run this command:"
        echo "  sed -i 's/^#no-cgroups = false/no-cgroups = true/' /etc/nvidia-container-runtime/config.toml"
        echo "  Then: systemctl restart docker"
    fi
else
    echo "✗ NVIDIA Container Runtime config not found!"
fi
echo ""

echo "3. Checking Docker daemon configuration..."
echo "------------------------------------------"
if [ -f /etc/docker/daemon.json ]; then
    cat /etc/docker/daemon.json
    echo ""
    if grep -q "nvidia" /etc/docker/daemon.json; then
        echo "✓ NVIDIA runtime configured in Docker"
    else
        echo "✗ NVIDIA runtime NOT configured!"
        echo "  Fix: Run this command:"
        echo "  nvidia-ctk runtime configure --runtime=docker"
        echo "  Then: systemctl daemon-reload && systemctl restart docker"
    fi
else
    echo "✗ Docker daemon.json not found!"
fi
echo ""

echo "4. Checking Docker runtime info..."
echo "----------------------------------"
docker info 2>/dev/null | grep -A 10 "Runtimes:" || echo "✗ Could not get Docker runtime info"
echo ""

echo "5. Testing nvidia-smi on host..."
echo "---------------------------------"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi -L || echo "✗ nvidia-smi failed"
else
    echo "✗ nvidia-smi command not found"
    echo "  Fix: Install NVIDIA libraries first"
fi
echo ""

echo "6. Checking NVIDIA Container Toolkit..."
echo "----------------------------------------"
if command -v nvidia-ctk &> /dev/null; then
    nvidia-ctk --version
    echo "✓ NVIDIA Container Toolkit installed"
else
    echo "✗ NVIDIA Container Toolkit not found!"
fi
echo ""

echo "7. Testing Docker GPU access..."
echo "-------------------------------"
echo "Running: docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi"
echo ""
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi

if [ $? -eq 0 ]; then
    echo ""
    echo "✓✓✓ SUCCESS! GPU is working in Docker containers ✓✓✓"
else
    echo ""
    echo "✗✗✗ FAILED! GPU is not working in Docker containers ✗✗✗"
    echo ""
    echo "Common fixes:"
    echo "1. Ensure no-cgroups = true in /etc/nvidia-container-runtime/config.toml"
    echo "2. Restart Docker: systemctl restart docker"
    echo "3. Check LXC host config has GPU devices mounted"
    echo "4. Verify NVIDIA drivers are loaded on Proxmox host: lsmod | grep nvidia"
fi

echo ""
echo "=========================================="
echo "Troubleshooting complete"
echo "=========================================="
