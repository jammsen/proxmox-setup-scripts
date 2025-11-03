#!/usr/bin/env bash

# Combined Docker + AMD ROCm Runtime installation for LXC containers
# This script installs Docker, AMD ROCm libraries, and verifies GPU access inside the LXC container

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Docker + AMD GPU Setup for LXC${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Make sure AMD drivers are installed on the Proxmox HOST first!${NC}"
echo -e "${YELLOW}Run '003 - install-amd-drivers.sh' on the host if not already done.${NC}"
echo ""

# Verify GPU is visible
echo -e "${GREEN}>>> Checking if GPU devices are accessible...${NC}"
GPU_FOUND=false
if [ -e /dev/kfd ]; then
    echo -e "${GREEN}✓ AMD GPU devices found:${NC}"
    ls -la /dev/kfd 2>/dev/null || true
    GPU_FOUND=true
fi

if [ -e /dev/dri/card0 ]; then
    echo -e "${GREEN}✓ DRI devices found:${NC}"
    ls -la /dev/dri/ 2>/dev/null || true
    GPU_FOUND=true
fi

if [ "$GPU_FOUND" = false ]; then
    echo -e "${RED}WARNING: No GPU devices found!${NC}"
    echo -e "${YELLOW}Make sure the LXC container has GPU passthrough configured correctly.${NC}"
    echo ""
    read -r -p "Continue anyway? [y/N]: " CONTINUE
    CONTINUE=${CONTINUE:-N}
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Cancelled.${NC}"
        exit 1
    fi
fi
echo ""

# Remove debian-provided packages
echo -e "${GREEN}>>> Removing old Docker packages...${NC}"
apt remove -y docker-compose docker docker.io containerd runc 2>/dev/null || true

# Update package list and upgrade existing packages
echo -e "${GREEN}>>> Updating system packages...${NC}"
apt update && apt upgrade -y

# Install Docker prerequisites
echo -e "${GREEN}>>> Installing prerequisites...${NC}"
apt install -y ca-certificates curl gnupg lsb-release sudo pciutils

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list
apt update

# Install Docker Engine (latest stable)
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker daemon
systemctl start docker
systemctl enable docker

# Add root user to docker group
usermod -a -G docker root

# Verify Docker installation
echo -e "${GREEN}>>> Docker version installed:${NC}"
docker --version
echo -e "${GREEN}>>> Docker Compose version installed:${NC}"
docker compose version
echo -e "${GREEN}>>> Containerd version installed:${NC}"
containerd --version
echo -e "${GREEN}>>> Docker installation completed.${NC}"

# Install docker-compose bash completion
echo -e "${GREEN}>>> Installing Docker bash completion...${NC}"
curl -L https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker \
    -o /etc/bash_completion.d/docker-compose

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Installing AMD ROCm Libraries${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Add AMD ROCm repository
echo -e "${GREEN}>>> Adding AMD ROCm repository...${NC}"
# Add AMD ROCm GPG key
# Make the directory if it doesn't exist yet.
# This location is recommended by the distribution maintainers.
sudo mkdir --parents --mode=0755 /etc/apt/keyrings

# Download the key, convert the signing-key to a full
# keyring required by apt and store in the keyring directory
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

# Add ROCm 7.1.0 repository (Noble/24.04)
sudo tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.1 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.1/ubuntu noble main
EOF

sudo tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

apt update

# Install AMD libraries (user-space only, NO kernel modules)
# Note: We install the latest available version, but it must match the host driver
echo -e "${GREEN}>>> Installing AMD ROCm libraries...${NC}"

# Install ROCm 7.1.0 (runtime libraries without DKMS)
# This installs runtime libraries without DKMS
apt install -y rocm-libs rocm-smi rocminfo rocm-device-libs rocm-utils

# Install ROCm development packages (needed for Ollama Docker to compile if needed)
apt install -y rocm-core rocm-dev hipcc

# Install monitoring tools
apt install -y nvtop radeontop

# Add root user to render and video groups (critical for GPU access)
usermod -a -G render,video root
usermod -a -G video,render root

# Set up ROCm environment variables
cat >> /root/.bashrc << 'EOF'

# ROCm Environment Variables
export PATH="/opt/rocm/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH}"
export HSA_OVERRIDE_GFX_VERSION=11.5.1  # Required for gfx1150 support
export HSA_ENABLE_SDMA=0  # May be needed for APU stability

EOF

# Create system-wide ROCm profile
cat > /etc/profile.d/rocm.sh << 'EOF'
export PATH="/opt/rocm/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH}"
export HSA_OVERRIDE_GFX_VERSION=11.5.1  # Required for gfx1150 support
export HSA_ENABLE_SDMA=0  # May be needed for APU stability

EOF

chmod +x /etc/profile.d/rocm.sh

# Source the new environment
source /root/.bashrc
source /etc/profile.d/rocm.sh


# Verify ROCm installation
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Verifying ROCm LXC installation...${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
which rocm-smi rocminfo nvtop radeontop
rocminfo | grep -i -A5 'Agent [0-9]'
rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname

# Verify installation
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Testing GPU Access in Docker${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}>>> Verifying AMD ROCm installation with Docker...${NC}"
echo ""
echo -e "${YELLOW}Test 1: ROCM Info and SMI test${NC}"
echo -e "${YELLOW}Image: rocm/rocm:5.4.3-ubuntu22.04 (~1GB)${NC}"
echo -e "${YELLOW}Command: docker run --rm --name rcom-smi --device /dev/kfd --device /dev/dri -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 --group-add video --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/rocm-terminal bash -c \"rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname && rocminfo | grep -i -A5 'Agent [0-9]'\"${NC}"
echo ""
read -r -p "Run Test 1? This will download ~1GB. [Y/n]: " RUN_TEST1
RUN_TEST1=${RUN_TEST1:-Y}

if [[ "$RUN_TEST1" =~ ^[Yy]$ ]]; then
    docker run --rm --name rcom-smi --device /dev/kfd --device /dev/dri -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 --group-add video --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/rocm-terminal bash -c "rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname && rocminfo | grep -i -A5 'Agent [0-9]'"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Test 1 passed!${NC}"
        echo ""
        echo -e "${GREEN}==========================================${NC}"
        echo -e "${GREEN}Installation Complete!${NC}"
        echo -e "${GREEN}==========================================${NC}"
        echo ""
        echo -e "${GREEN}Your LXC container is now ready to use AMD GPUs in Docker containers.${NC}"
        echo ""
    else
        echo ""
        echo -e "${RED}✗✗✗ AMD ROCm test failed! ✗✗✗${NC}"
        echo ""
    fi
else
    echo ""
    echo -e "${YELLOW}Tests skipped. You can manually test later with:${NC}"
    echo "  docker run --rm --name rcom-smi --device /dev/kfd --device /dev/dri -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 --group-add video --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/rocm-terminal bash -c \"rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname && rocminfo | grep -i -A5 'Agent [0-9]'\""
    echo ""
fi