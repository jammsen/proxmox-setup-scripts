#!/usr/bin/env bash
wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb
apt update

# install nvidia drivers
# these are the compute-only (headless) versions of the drivers
# this makes sure we don't install any unnecessary packages (X drivers, etc)
apt install nvidia-driver-cuda

# disable + mask persistence service
systemctl stop nvidia-persistenced.service
systemctl disable nvidia-persistenced.service
systemctl mask nvidia-persistenced.service

# remove kernel config
echo "" > /etc/modprobe.d/nvidia.conf
echo "" > /etc/modprobe.d/nvidia-modeset.conf

# block kernel modules
echo -e "blacklist nvidia\nblacklist nvidia_drm\nblacklist nvidia_modeset\nblacklist nvidia_uvm" > /etc/modprobe.d/blacklist-nvidia.conf