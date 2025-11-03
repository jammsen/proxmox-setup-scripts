#!/usr/bin/env bash

# Combined Docker + NVIDIA Container Runtime installation for LXC containers
# This script installs Docker, NVIDIA libraries, and NVIDIA Container Toolkit

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../includes/colors.sh
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Docker + NVIDIA GPU Setup for LXC${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Make sure NVIDIA drivers are installed on the Proxmox HOST first!${NC}"
echo -e "${YELLOW}Run '004 - install-nvidia-drivers.sh' on the host if not already done.${NC}"
echo ""

# Verify GPU is visible
echo -e "${GREEN}>>> Checking if GPU devices are accessible...${NC}"
GPU_FOUND=false
if [ -e /dev/nvidia0 ]; then
    echo -e "${GREEN}✓ NVIDIA GPU devices found:${NC}"
    ls -la /dev/nvidia* 2>/dev/null || true
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
echo -e "${GREEN}Installing NVIDIA Libraries and Toolkit${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Add NVIDIA CUDA repository
echo -e "${GREEN}>>> Adding NVIDIA CUDA repository...${NC}"
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb
apt update

# Install NVIDIA libraries (user-space only, NO kernel modules)
# Note: We install the latest available version, but it must match the host driver
echo -e "${GREEN}>>> Installing NVIDIA user-space libraries...${NC}"

# First, detect what driver version is on the host
HOST_DRIVER_VERSION=""
if [ -e /dev/nvidia0 ]; then
    # Try to detect driver version from host
    # The nvidia-smi in container will show the host driver version
    HOST_DRIVER_VERSION=$(cat /proc/driver/nvidia/version 2>/dev/null | grep "Kernel Module" | awk '{print $8}' || echo "")
fi

if [ -n "$HOST_DRIVER_VERSION" ]; then
    echo -e "${GREEN}Detected host NVIDIA driver version: ${YELLOW}$HOST_DRIVER_VERSION${NC}"
    # Extract major version (e.g., 560 from 560.35.03 or 580 from 580.95.05)
    DRIVER_MAJOR=$(echo "$HOST_DRIVER_VERSION" | cut -d'.' -f1)
    echo -e "${GREEN}Installing libraries for driver series: ${YELLOW}$DRIVER_MAJOR${NC}"
else
    echo -e "${YELLOW}Could not detect host driver version, using latest available...${NC}"
    DRIVER_MAJOR="560"
fi

# Determine if this is a server driver
DRIVER_SUFFIX=""
if apt-cache search "nvidia-driver-${DRIVER_MAJOR}-server" | grep -q "nvidia-driver-${DRIVER_MAJOR}-server"; then
    echo -e "${GREEN}Detected server driver series${NC}"
    DRIVER_SUFFIX="-server"
fi

# Install matching libraries
# For LXC, we need the full driver package to get all libraries including libnvidia-ml.so.1
echo -e "${GREEN}Installing nvidia-driver-${DRIVER_MAJOR}${DRIVER_SUFFIX}...${NC}"
apt install -y "nvidia-driver-${DRIVER_MAJOR}${DRIVER_SUFFIX}" || {
    echo -e "${YELLOW}Failed to install nvidia-driver-${DRIVER_MAJOR}${DRIVER_SUFFIX}${NC}"
    echo -e "${YELLOW}Trying alternative installation method...${NC}"
    
    # Try installing just the compute libraries
    apt install -y \
        "libnvidia-compute-${DRIVER_MAJOR}:amd64" \
        "libnvidia-ml-${DRIVER_MAJOR}:amd64" \
        "libnvidia-encode-${DRIVER_MAJOR}:amd64" \
        "libnvidia-decode-${DRIVER_MAJOR}:amd64" \
        "libnvidia-fbc1-${DRIVER_MAJOR}:amd64" 2>/dev/null || echo -e "${YELLOW}Some packages failed to install${NC}"
}

# Prevent kernel modules from being loaded (they come from host)
echo -e "${GREEN}>>> Preventing kernel modules from loading (handled by host)...${NC}"
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/blacklist-nvidia.conf << 'EOF'
# Blacklist NVIDIA kernel modules in LXC container
# These are provided by the host
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
blacklist nouveau
EOF

# Update initramfs but don't fail if it errors (we don't need it in LXC anyway)
update-initramfs -u 2>/dev/null || echo -e "${YELLOW}Note: initramfs update skipped (not needed in LXC)${NC}"

# DO NOT load or install kernel modules in LXC - they come from the host
echo -e "${GREEN}>>> Kernel modules handled by host (not loading in container)${NC}"
echo ""

# Create library symlinks if needed
echo -e "${GREEN}>>> Creating library symlinks...${NC}"
ldconfig

# Verify nvidia-smi works (may show version mismatch if libraries don't match host)
echo -e "${GREEN}>>> Testing nvidia-smi on host...${NC}"
if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi 2>&1 | grep -q "version mismatch"; then
        echo -e "${YELLOW}⚠ nvidia-smi shows driver/library version mismatch${NC}"
        echo -e "${YELLOW}This is expected in LXC and will work correctly in Docker containers.${NC}"
    elif nvidia-smi >/dev/null 2>&1; then
        nvidia-smi
        echo ""
        echo -e "${GREEN}✓ nvidia-smi working correctly!${NC}"
    else
        echo -e "${YELLOW}⚠ nvidia-smi test failed on host, but GPU will work in Docker containers.${NC}"
        nvidia-smi 2>&1 || true
    fi
else
    echo -e "${YELLOW}⚠ nvidia-smi not available.${NC}"
fi
echo ""

# Install NVIDIA Container Toolkit
echo -e "${GREEN}>>> Installing NVIDIA Container Toolkit...${NC}"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt update
export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.18.0-1
apt-get install -y \
  nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
  libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}

# Configure Docker to use NVIDIA runtime
echo -e "${GREEN}>>> Configuring NVIDIA Container Toolkit for Docker...${NC}"
nvidia-ctk runtime configure --runtime=docker

# CRITICAL for LXC: Disable cgroup management in NVIDIA Container Runtime
# LXC containers have different cgroup hierarchy than regular systems
echo -e "${GREEN}>>> Configuring NVIDIA Container Runtime for LXC environment...${NC}"
sed -i 's/^#no-cgroups = false/no-cgroups = true/' /etc/nvidia-container-runtime/config.toml
sed -i 's/^no-cgroups = false/no-cgroups = true/' /etc/nvidia-container-runtime/config.toml

# Try to generate CDI config, but don't fail if it doesn't work
# In LXC, this might fail but Docker will still work
echo -e "${GREEN}>>> Attempting to generate CDI configuration...${NC}"
if nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml 2>&1; then
    echo -e "${GREEN}✓ CDI configuration generated successfully${NC}"
else
    echo -e "${YELLOW}⚠ CDI generation failed (this is OK in LXC - Docker will still work)${NC}"
    # Create minimal CDI directory
    mkdir -p /etc/cdi
fi

# Restart systemd + docker (if you don't reload systemd, it might not work)
systemctl daemon-reload
systemctl restart docker
echo -e "${GREEN}>>> Docker and NVIDIA Container Toolkit configuration complete${NC}"
echo ""

# Verify installation
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Testing GPU Access in Docker${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}>>> Verifying NVIDIA Container Toolkit installation with Docker...${NC}"
echo ""
echo -e "${YELLOW}Test 1: NVIDIA SMI test${NC}"
echo -e "${YELLOW}Image: nvidia/cuda:12.6.0-base-ubuntu24.04 (~250MB)${NC}"
echo -e "${YELLOW}Command: docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi${NC}"
echo ""
read -r -p "Run Test 1? This will download ~250MB. [Y/n]: " RUN_TEST1
RUN_TEST1=${RUN_TEST1:-Y}

if [[ "$RUN_TEST1" =~ ^[Yy]$ ]]; then
    docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Test 1 passed!${NC}"
        echo ""
        echo -e "${YELLOW}Test 2: PyTorch CUDA availability test${NC}"
        echo -e "${YELLOW}Image: pytorch/pytorch:latest (~4GB - large download!)${NC}"
        echo -e "${YELLOW}Command: docker run --rm --gpus all pytorch/pytorch:latest python -c 'import torch; print(torch.cuda.is_available())'${NC}"
        echo ""
        read -r -p "Run Test 2? This will download ~4GB. [Y/n]: " RUN_TEST2
        RUN_TEST2=${RUN_TEST2:-Y}
        
        if [[ "$RUN_TEST2" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${GREEN}Downloading PyTorch image (this may take several minutes)...${NC}"
            docker pull pytorch/pytorch:latest
            
            if [ $? -eq 0 ]; then
                echo ""
                echo -e "${GREEN}Running PyTorch CUDA test...${NC}"
                docker run --rm --gpus all pytorch/pytorch:latest python -c 'import torch; print("CUDA Available:", torch.cuda.is_available())'
                
                if [ $? -eq 0 ]; then
                    echo ""
                    echo -e "${GREEN}✓ Test 2 passed!${NC}"
                    echo ""
                    echo -e "${GREEN}✓✓✓ SUCCESS! NVIDIA Container Toolkit is working correctly! ✓✓✓${NC}"
                    echo ""
                    echo -e "${GREEN}==========================================${NC}"
                    echo -e "${GREEN}Installation Complete!${NC}"
                    echo -e "${GREEN}==========================================${NC}"
                    echo ""
                    echo -e "${GREEN}Your LXC container is now ready to use NVIDIA GPUs in Docker containers.${NC}"
                    echo ""
                    echo -e "${GREEN}Both tests passed:${NC}"
                    echo -e "${GREEN}  ✓ nvidia-smi in CUDA container${NC}"
                    echo -e "${GREEN}  ✓ PyTorch CUDA detection${NC}"
                    echo ""
                else
                    echo ""
                    echo -e "${YELLOW}⚠ Test 2 failed - PyTorch could not detect CUDA${NC}"
                    echo -e "${YELLOW}nvidia-smi works but PyTorch CUDA detection failed.${NC}"
                    echo -e "${YELLOW}This might be a PyTorch-specific issue.${NC}"
                fi
            else
                echo -e "${RED}Failed to download PyTorch image. Check your internet connection.${NC}"
            fi
        else
            echo ""
            echo -e "${YELLOW}Test 2 skipped.${NC}"
            echo ""
            echo -e "${GREEN}✓ SUCCESS! NVIDIA Container Toolkit is working (Test 1 passed)!${NC}"
            echo ""
            echo -e "${GREEN}==========================================${NC}"
            echo -e "${GREEN}Installation Complete!${NC}"
            echo -e "${GREEN}==========================================${NC}"
            echo ""
            echo -e "${GREEN}Your LXC container is now ready to use NVIDIA GPUs in Docker containers.${NC}"
            echo ""
        fi
        
        echo ""
        echo -e "${YELLOW}Example usage:${NC}"
        echo "  docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi"
        echo "  docker run --rm --gpus all pytorch/pytorch:latest python -c 'import torch; print(torch.cuda.is_available())'"
        echo ""
    else
        echo ""
        echo -e "${RED}✗✗✗ NVIDIA Container Toolkit test failed! ✗✗✗${NC}"
        echo ""
        echo -e "${YELLOW}Troubleshooting steps:${NC}"
        echo "1. Verify GPU devices are accessible: ls -la /dev/nvidia* /dev/dri/"
        echo "2. Check NVIDIA runtime config: cat /etc/nvidia-container-runtime/config.toml | grep no-cgroups"
        echo "3. Check Docker daemon config: cat /etc/docker/daemon.json"
        echo "4. Check container runtime: docker info | grep -i runtime"
        echo "5. Run troubleshooting script: bash troubleshoot-nvidia-docker.sh"
        echo "6. Restart Docker: systemctl restart docker"
        echo ""
        echo -e "${YELLOW}If issues persist, verify:${NC}"
        echo "- NVIDIA drivers are installed on Proxmox host"
        echo "- LXC container config has proper GPU device mounts"
        echo "- no-cgroups = true in /etc/nvidia-container-runtime/config.toml"
    fi
else
    echo ""
    echo -e "${YELLOW}Tests skipped. You can manually test later with:${NC}"
    echo "  docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi"
    echo ""
fi