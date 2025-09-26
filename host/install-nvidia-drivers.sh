#!/usr/bin/env bash
apt update
apt install -y proxmox-headers-"$(uname -r)"
wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb
apt update
apt install -y nvidia-driver-cuda nvidia-kernel-dkms
echo "Please now reboot the system"