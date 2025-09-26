#!/usr/bin/env bash
apt update

# Install ROCm packages directly from Debian repositories
apt install -y rocminfo rocm-dev hip-dev rocblas-dev rocfft-dev rocsolver-dev

# Add user to required groups for GPU access
usermod -aG video,render $USER

# Verify ROCm installation
rocminfo

echo "ROCm installation complete. Please log out and back in for group changes to take effect."

pause

# Install AMD Container Toolkit for ROCm support
curl -fsSL https://rocm.docs.amd.com/rocm.gpg.key | apt-key add -
echo "deb [arch=amd64] https://rocm.docs.amd.com/apt/6.2.4 jammy main" | tee -a /etc/apt/sources.list.d/rocm.list
apt update
apt -y install amd-container-toolkit

# Configure Docker for AMD GPU access
amd-ctk runtime configure --runtime=docker
systemctl daemon-reload
systemctl restart docker
