#!/usr/bin/env bash
# Add ROCm repository
wget -O - https://repo.radeon.com/rocm/rocm.gpg.key | apt-key add -
echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/6.2.4 jammy main" | tee /etc/apt/sources.list.d/rocm.list

apt update
apt install -y rocm-dev rocm-libs rocm-utils --no-install-recommends

# Install AMD Container Toolkit for ROCm support
curl -fsSL https://rocm.docs.amd.com/rocm.gpg.key | apt-key add -
echo "deb [arch=amd64] https://rocm.docs.amd.com/apt/6.2.4 jammy main" | tee -a /etc/apt/sources.list.d/rocm.list
apt update
apt -y install amd-container-toolkit

# Configure Docker for AMD GPU access
amd-ctk runtime configure --runtime=docker
systemctl daemon-reload
systemctl restart docker
