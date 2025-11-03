#!/usr/bin/env bash

# NVIDIA GPU setup for LXC containers
# NOTE: NVIDIA kernel modules must be loaded on the HOST, not in the container
# This script only installs the user-space libraries needed for CUDA/container runtime

echo ">>> Installing NVIDIA Container Toolkit and libraries for LXC"
echo ""
echo "IMPORTANT: Make sure NVIDIA drivers are installed on the Proxmox HOST first!"
echo "Run '004 - install-nvidia-drivers.sh' on the host if not already done."
echo ""

# Update package list
apt update && apt upgrade -y

# Install basic dependencies
apt install -y ca-certificates curl gnupg lsb-release pciutils

# Verify GPU is visible
echo ">>> Checking if GPU devices are accessible..."
if [ ! -e /dev/nvidia0 ]; then
    echo "ERROR: /dev/nvidia0 not found!"
    echo "Make sure the LXC container has GPU passthrough configured correctly."
    exit 1
fi

echo "✓ GPU devices found:"
ls -la /dev/nvidia* /dev/dri/ 2>/dev/null || true
echo ""

# Add NVIDIA CUDA repository
echo ">>> Adding NVIDIA CUDA repository..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb
apt update

# Install NVIDIA libraries (user-space only, NO kernel modules)
echo ">>> Installing NVIDIA user-space libraries..."
apt install -y \
    libnvidia-compute-560 \
    libnvidia-encode-560 \
    libnvidia-decode-560 \
    libnvidia-fbc1-560 \
    nvidia-utils-560 \
    nvidia-settings

# DO NOT install kernel modules in LXC - they come from the host
echo ">>> Skipping kernel module installation (handled by host)"

# Verify nvidia-smi works
echo ""
echo ">>> Testing nvidia-smi..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
    echo ""
    echo "✓ nvidia-smi working correctly!"
else
    echo "WARNING: nvidia-smi not available yet. Will be available after Docker toolkit is installed."
fi

echo ""
echo ">>> NVIDIA libraries installation complete!"
echo ">>> Next: Run 'install-docker-and-container-runtime.sh' to enable GPU in Docker"