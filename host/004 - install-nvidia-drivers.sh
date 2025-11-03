#!/usr/bin/env bash
# SCRIPT_DESC: Install NVIDIA GPU drivers
# SCRIPT_DETECT: command -v nvidia-smi &>/dev/null

apt update
echo ">>> Installing Proxmox headers for current kernel"
apt install -y proxmox-headers-"$(uname -r)"
echo ">>> Downloading and installing NVIDIA CUDA keyring"
wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb
apt update
echo ">>> Installing NVIDIA driver packages"
apt install -y nvidia-driver-cuda nvidia-kernel-dkms
echo ">>> Please reboot the system now"