#!/usr/bin/env bash
echo ">>> Verifying NVIDIA driver installation by checking for installed tools"
which nvidia-smi
nvidia-smi
echo ">>> NVIDIA driver installation and setup completed."