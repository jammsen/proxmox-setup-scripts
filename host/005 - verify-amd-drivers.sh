#!/usr/bin/env bash

# Verify AMD ROCm driver installation
# This script checks if AMD drivers and tools are properly installed and accessible

echo ">>> Verifying ROCm installation by checking for installed tools"
which rocm-smi rocminfo nvtop radeontop
rocminfo | grep -i -A5 'Agent [0-9]'
rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname
echo ">>> AMD ROCm driver verification completed."
