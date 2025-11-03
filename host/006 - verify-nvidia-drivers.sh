#!/usr/bin/env bash

# VerifyNVIDIA driver installation
# This script checks if NVIDIA drivers and tools are properly installed and accessible

echo ">>> Verifying NVIDIA driver installation by checking for installed tools"
which nvidia-smi
nvidia-smi
echo ">>> NVIDIA driver installation and setup completed."