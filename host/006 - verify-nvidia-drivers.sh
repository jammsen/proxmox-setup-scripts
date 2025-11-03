#!/usr/bin/env bash
# SCRIPT_DESC: Verify NVIDIA driver installation
# SCRIPT_DETECT: command -v nvidia-smi &>/dev/null

# VerifyNVIDIA driver installation
# This script checks if NVIDIA drivers and tools are properly installed and accessible

echo ">>> Verifying NVIDIA driver installation by checking for installed tools"
which nvidia-smi
nvidia-smi
echo ">>> NVIDIA driver installation and setup completed."