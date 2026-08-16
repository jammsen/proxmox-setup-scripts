#!/usr/bin/env bash

# Combined Docker + NVIDIA Container Runtime installation for LXC containers
# This script installs Docker, NVIDIA libraries, and NVIDIA Container Toolkit

set -e

# The Proxmox template sets LANG=en_US.UTF-8 but does not generate that locale, which makes
# perl/apt print locale warnings on every step. Use C.UTF-8 for this run and generate en_US.UTF-8
# further below so later logins are clean too.
export LC_ALL=C.UTF-8

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
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
# Non-interactive: keep locally modified configs (e.g. sshd_config with root login enabled)
apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::=--force-confold
# Generate the locale the template refers to (LANG=en_US.UTF-8) so the warnings go away permanently
if command -v locale-gen >/dev/null 2>&1 && ! locale -a 2>/dev/null | grep -qi "en_US.utf8"; then
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || true
    locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
fi

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
# Pick the CUDA repo matching the container's Ubuntu release (2404 for noble, 2604 for resolute)
UBUNTU_REL=$(. /etc/os-release && echo "${VERSION_ID//./}")
# Download to a temp dir: the current directory may be the read-only scripts mount
KEYRING_TMP=$(mktemp -d)
wget -O "${KEYRING_TMP}/cuda-keyring_1.1-1_all.deb" "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_REL:-2604}/x86_64/cuda-keyring_1.1-1_all.deb"
dpkg -i "${KEYRING_TMP}/cuda-keyring_1.1-1_all.deb"
rm -rf "${KEYRING_TMP}"
apt update

# Install NVIDIA user-space libraries (NO kernel modules - those come from the host).
# The versions MUST match the host driver exactly, otherwise libcuda/libnvidia-ml refuse to
# work ("Driver/library version mismatch"). We only need libcuda, libnvidia-ml and nvidia-smi.
echo -e "${GREEN}>>> Installing NVIDIA user-space libraries...${NC}"

HOST_DRIVER_VERSION=$(grep "Kernel Module" /proc/driver/nvidia/version 2>/dev/null | awk '{print $8}' || true)
if [ -z "$HOST_DRIVER_VERSION" ]; then
    echo -e "${RED}Could not detect the host NVIDIA driver version (/proc/driver/nvidia/version).${NC}"
    echo -e "${RED}Make sure the NVIDIA driver is installed on the Proxmox host (script 004) and the GPU is passed through.${NC}"
    exit 1
fi
DRIVER_MAJOR=$(echo "$HOST_DRIVER_VERSION" | cut -d'.' -f1)
echo -e "${GREEN}Host NVIDIA driver version: ${YELLOW}$HOST_DRIVER_VERSION${NC}"

# The CUDA apt repo uses two naming schemes:
#  - Ubuntu 26.04 repo: unversioned packages (libnvidia-compute, nvidia-driver, ...)
#  - Ubuntu 24.04 repo: versioned packages   (libnvidia-compute-580, nvidia-utils-580, ...)
# nvidia-smi lives in libnvidia-compute (26.04) resp. nvidia-utils-<major> (24.04).
if apt-cache show libnvidia-compute >/dev/null 2>&1; then
    NV_PKGS=(libnvidia-compute)
    NV_OPT_PKGS=(libnvidia-encode libnvidia-decode)
else
    NV_PKGS=("libnvidia-compute-${DRIVER_MAJOR}" "nvidia-utils-${DRIVER_MAJOR}")
    NV_OPT_PKGS=("libnvidia-encode-${DRIVER_MAJOR}" "libnvidia-decode-${DRIVER_MAJOR}")
fi

# Find the exact package version matching the host driver (e.g. 610.57.04-1ubuntu1),
# taken from NVIDIA's CUDA repository only (not Ubuntu's own multiverse/restricted builds)
NV_VERSION=$(apt-cache madison "${NV_PKGS[0]}" | awk -v v="$HOST_DRIVER_VERSION" '$3 ~ "^"v && /developer\.download\.nvidia\.com/ {print $3; exit}')
if [ -z "$NV_VERSION" ]; then
    echo -e "${RED}No package ${NV_PKGS[0]} with version ${HOST_DRIVER_VERSION} found in NVIDIA's CUDA repository.${NC}"
    echo -e "${RED}Versions available there:${NC}"
    apt-cache madison "${NV_PKGS[0]}" | awk '/developer\.download\.nvidia\.com/ {print "  "$3}' | head -10
    echo -e "${YELLOW}The container libraries must match the host driver exactly. Either update the host driver${NC}"
    echo -e "${YELLOW}(script 004 / apt upgrade on the host) or wait until the CUDA repo ships this version.${NC}"
    exit 1
fi
echo -e "${GREEN}Installing ${NV_PKGS[*]} version ${YELLOW}$NV_VERSION${NC}"

# Remove previously installed NVIDIA packages of a different version (e.g. from a failed earlier run)
# (the NVIDIA container toolkit packages have their own versioning and are left alone)
if dpkg -l 2>/dev/null | awk '/^ii/ && ($2 ~ /^(lib)?nvidia-/) && ($2 !~ /container/) {print $3}' | grep -qv "^${HOST_DRIVER_VERSION}"; then
    echo -e "${YELLOW}Removing NVIDIA packages that do not match the host driver version...${NC}"
    apt purge -y 'nvidia-driver*' 'nvidia-dkms*' 'nvidia-kernel*' 'nvidia-utils*' 'nvidia-compute-utils*' \
        'nvidia-firmware*' 'nvidia-settings' 'nvidia-prime' 'nvidia-persistenced' 'nvidia-modprobe' 'xserver-xorg-video-nvidia*' \
        'libnvidia-compute*' 'libnvidia-cfg1*' 'libnvidia-gl*' 'libnvidia-decode*' 'libnvidia-encode*' 'libnvidia-extra*' \
        'libnvidia-fbc1*' 'libnvidia-common*' 'libnvidia-gpucomp*' 'libnvidia-egl*' 2>/dev/null || true
    apt autoremove -y --purge
fi

NV_INSTALL=()
for pkg in "${NV_PKGS[@]}"; do NV_INSTALL+=("${pkg}=${NV_VERSION}"); done
for pkg in "${NV_OPT_PKGS[@]}"; do
    apt-cache madison "$pkg" | awk '{print $3}' | grep -qx "$NV_VERSION" && NV_INSTALL+=("${pkg}=${NV_VERSION}")
done
apt install -y --no-install-recommends "${NV_INSTALL[@]}"

# Hold the packages so a later 'apt upgrade' inside the container cannot drift away from the host driver
apt-mark hold "${NV_PKGS[@]}" "${NV_OPT_PKGS[@]}" 2>/dev/null || true
echo -e "${GREEN}NVIDIA user-space libraries installed and pinned to ${NV_VERSION}.${NC}"
echo -e "${YELLOW}Note: when you update the NVIDIA driver on the host, re-run this script in the container.${NC}"

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

# Verify nvidia-smi works inside the container
echo -e "${GREEN}>>> Testing nvidia-smi in the container...${NC}"
if command -v nvidia-smi &> /dev/null; then
    if nvidia-smi 2>&1 | grep -q "version mismatch"; then
        echo -e "${RED}✗ nvidia-smi reports a driver/library version mismatch.${NC}"
        echo -e "${RED}  Host driver: ${HOST_DRIVER_VERSION}, container libraries: ${NV_VERSION}${NC}"
        echo -e "${RED}  CUDA will not work until they match. Re-run this script after fixing the host driver.${NC}"
        exit 1
    elif nvidia-smi >/dev/null 2>&1; then
        nvidia-smi
        echo ""
        echo -e "${GREEN}✓ nvidia-smi working correctly!${NC}"
    else
        echo -e "${YELLOW}⚠ nvidia-smi failed:${NC}"
        nvidia-smi 2>&1 || true
    fi
else
    echo -e "${RED}✗ nvidia-smi not found after installation.${NC}"
    exit 1
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
# sed -i 's/^#no-cgroups = false/no-cgroups = true/' /etc/nvidia-container-runtime/config.toml
# sed -i 's/^no-cgroups = false/no-cgroups = true/' /etc/nvidia-container-runtime/config.toml
# Remove all existing no-cgroups lines
sed -i '/no-cgroups/d' /etc/nvidia-container-runtime/config.toml
# Add it uncommented at the top of the file
sed -i '1i no-cgroups = true' /etc/nvidia-container-runtime/config.toml


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
sleep 2
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
echo -e "${YELLOW}Image: nvidia/cuda:13.0.1-base-ubuntu24.04 (~250MB)${NC}"
echo -e "${YELLOW}Command: docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi${NC}"
echo ""
read -r -p "Run Test 1? This will download ~250MB. [Y/n]: " RUN_TEST1
RUN_TEST1=${RUN_TEST1:-Y}

if [[ "$RUN_TEST1" =~ ^[Yy]$ ]]; then
    docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Test 1 passed!${NC}"
        echo ""
        echo -e "${YELLOW}Test 2: FFmpeg NVENC hardware encoding test${NC}"
        echo -e "${YELLOW}Image: linuxserver/ffmpeg (~250MB)${NC}"
        echo -e "${YELLOW}Command: docker run --rm -it --gpus all linuxserver/ffmpeg -hwaccel cuda -f lavfi -i testsrc2=duration=300:size=1280x720:rate=90 -c:v hevc_nvenc -qp 18 nvidia-hevc_nvec-90fps-300s.mp4${NC}"
        echo ""
        read -r -p "Run Test 2? This will download ~250MB. [Y/n]: " RUN_TEST2
        RUN_TEST2=${RUN_TEST2:-Y}
        
        if [[ "$RUN_TEST2" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${GREEN}Downloading FFmpeg image (this may take several minutes)...${NC}"
            docker pull linuxserver/ffmpeg
            
            if [ $? -eq 0 ]; then
                echo ""
                echo -e "${GREEN}Running FFmpeg test...${NC}"
                docker run --rm -it --gpus all linuxserver/ffmpeg -hwaccel cuda -f lavfi -i testsrc2=duration=300:size=1280x720:rate=90 -c:v hevc_nvenc -qp 18 nvidia-hevc_nvec-90fps-300s.mp4

                if [ $? -eq 0 ]; then
                    echo ""
                    echo -e "${GREEN}✓ Test 2 passed!${NC}"
                    echo ""
                    echo -e "${GREEN}✓ SUCCESS! NVIDIA Container Toolkit is working correctly! ✓${NC}"
                    echo ""
                    echo -e "${GREEN}==========================================${NC}"
                    echo -e "${GREEN}Installation Complete!${NC}"
                    echo -e "${GREEN}==========================================${NC}"
                    echo ""
                    echo -e "${GREEN}Your LXC container is now ready to use NVIDIA GPUs in Docker containers.${NC}"
                    echo ""
                    echo -e "${GREEN}Both tests passed:${NC}"
                    echo -e "${GREEN}  ✓ nvidia-smi in CUDA container${NC}"
                    echo -e "${GREEN}  ✓ FFmpeg NVENC hardware encoding${NC}"
                    echo ""
                else
                    echo ""
                    echo -e "${YELLOW}⚠ Test 2 failed - FFmpeg could not detect CUDA${NC}"
                    echo -e "${YELLOW}nvidia-smi works but the FFmpeg NVENC encoding test failed.${NC}"
                    echo -e "${YELLOW}This might be a FFmpeg-specific issue.${NC}"
                fi
            else
                echo -e "${RED}Failed to download FFmpeg image. Check your internet connection.${NC}"
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
        echo "  docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi"
        echo "  docker run --rm --gpus all linuxserver/ffmpeg -hwaccel cuda -f lavfi -i testsrc2=duration=300:size=1280x720:rate=90 -c:v hevc_nvenc -qp 18 nvidia-hevc_nvec-90fps-300s.mp4"
        echo ""
    else
        echo ""
        echo -e "${RED}✗ NVIDIA Container Toolkit test failed! ✗${NC}"
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
    echo "  docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi"
    echo ""
fi