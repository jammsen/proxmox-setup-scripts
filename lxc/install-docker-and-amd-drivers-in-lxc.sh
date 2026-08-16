#!/usr/bin/env bash

# Combined Docker + AMD ROCm runtime installation for LXC containers (Ubuntu 26.04+)
# Installs Docker, the AMD ROCm runtime from repo.amd.com (ROCm 7.14+, per-GPU packages) and
# verifies GPU access inside the LXC container. Only user-space - the kernel driver is the host's.

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
echo -e "${GREEN}Installing AMD ROCm Libraries${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# ------------------------------------------------------------------------------------------
# ROCm 7.14+ built with TheRock, from repo.amd.com. Packages are per GPU family and small; only
# the runtime is installed by default (Docker images like Ollama bring their own ROCm libraries,
# the container just needs KFD access and the tools). The full library set for the detected GPU
# is optional. Only user-space is installed - the kernel driver comes from the Proxmox host.
# Needs Ubuntu 26.04 or newer in the container (that is what scripts 031/032 create).
# ------------------------------------------------------------------------------------------
UBUNTU_VERSION_ID=$(. /etc/os-release && echo "${VERSION_ID}")
if [ "${UBUNTU_VERSION_ID%%.*}" -lt 26 ]; then
    echo -e "${RED}This container runs Ubuntu ${UBUNTU_VERSION_ID}. The AMD ROCm packages used here need Ubuntu 26.04 or newer.${NC}"
    echo "Please create the container with script 031 or 032 (they use the Ubuntu 26.04 template)."
    exit 1
fi
mkdir --parents --mode=0755 /etc/apt/keyrings

# Detect the GPU family (gfx target) from the kernel's KFD topology, e.g. 110500 -> gfx1150
GFX_TARGET=""
for props in /sys/class/kfd/kfd/topology/nodes/*/properties; do
    [ -r "$props" ] || continue
    ver=$(awk '$1=="gfx_target_version" {print $2}' "$props" 2>/dev/null)
    if [ -n "$ver" ] && [ "$ver" != "0" ]; then
        GFX_TARGET=$(printf 'gfx%d%x%x' $((ver/10000)) $(((ver/100)%100)) $((ver%100)))
        break
    fi
done
if [ -n "$GFX_TARGET" ]; then
    echo -e "${GREEN}Detected AMD GPU family: ${YELLOW}${GFX_TARGET}${NC}"
else
    echo -e "${YELLOW}Could not detect the GPU family from /sys/class/kfd - continuing without it.${NC}"
fi

echo -e "${GREEN}>>> Adding AMD ROCm repository (repo.amd.com)...${NC}"
wget -qO- https://repo.amd.com/rocm/packages-multi-arch/gpg/rocm.gpg | gpg --dearmor > /etc/apt/keyrings/amdrocm.gpg
UBUNTU_REPO_TAG="ubuntu${UBUNTU_VERSION_ID//./}"
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/amdrocm.gpg] https://repo.amd.com/rocm/packages-multi-arch/${UBUNTU_REPO_TAG} stable main" \
    > /etc/apt/sources.list.d/amdrocm.list
apt update

# Newest ROCm release in the repo (package names carry the version, e.g. amdrocm-runtime7.14)
ROCM_VER=$(apt-cache search --names-only '^amdrocm-runtime[0-9]+\.[0-9]+$' | awk '{print $1}' | sed 's/^amdrocm-runtime//' | sort -V | tail -1)
if [ -z "$ROCM_VER" ]; then
    echo -e "${RED}No amdrocm-runtime package found in the repository for ${UBUNTU_REPO_TAG}.${NC}"
    echo "Check https://repo.amd.com/rocm/packages-multi-arch/ for your Ubuntu release."
    exit 1
fi
ROCM_HOME="/opt/rocm/core-${ROCM_VER}"
echo -e "${GREEN}Using ROCm ${YELLOW}${ROCM_VER}${NC}"

echo -e "${GREEN}>>> Installing ROCm runtime and tools...${NC}"
echo "Packages: amdrocm-runtime${ROCM_VER} (HIP/HSA runtime), amdrocm-base${ROCM_VER} (rocminfo, rocm-smi), amdrocm-amdsmi${ROCM_VER} (amd-smi)"
# --no-install-recommends: the LLVM package "recommends" gcc/g++/multilib, which are only needed for
# compiling HIP code in the container - not for running Docker images or the tools.
apt install -y --no-install-recommends "amdrocm-runtime${ROCM_VER}" "amdrocm-base${ROCM_VER}" "amdrocm-amdsmi${ROCM_VER}"

# Optional: the full ROCm library set for this GPU (BLAS, DNN, FFT, ... - for building/running
# HIP applications directly in the container instead of in Docker images)
if [ -n "$GFX_TARGET" ] && apt-cache show "amdrocm${ROCM_VER}-${GFX_TARGET}" >/dev/null 2>&1; then
    echo ""
    echo "Docker images (Ollama, llama.cpp, ...) bring their own ROCm libraries, so the runtime above is"
    echo "usually enough. If you want to run or build HIP/ROCm software directly in this container,"
    echo "the full library set for ${GFX_TARGET} is available (about 650 MB download, 5 GB on disk)."
    read -r -p "Install the full ROCm libraries for ${GFX_TARGET} as well? [y/N]: " FULL_ROCM
    if [[ "${FULL_ROCM:-N}" =~ ^[Yy]$ ]]; then
        apt install -y "amdrocm${ROCM_VER}-${GFX_TARGET}"
    fi
elif [ -n "$GFX_TARGET" ]; then
    echo -e "${YELLOW}Note: ROCm ${ROCM_VER} has no library package for ${GFX_TARGET}; the runtime alone is installed.${NC}"
fi

# Monitoring tools
apt install -y nvtop radeontop

# Root must be in the groups that own /dev/kfd and /dev/dri/renderD*
usermod -a -G render,video root

# Environment: the packages install into /opt/rocm/core-<version> and set no PATH themselves.
# Libraries carry their own rpath, so no LD_LIBRARY_PATH is needed. The GPU family is a native
# build target, so no HSA_OVERRIDE_GFX_VERSION is needed either.
cat > /etc/profile.d/rocm.sh << EOF
export ROCM_PATH="${ROCM_HOME}"
export PATH="${ROCM_HOME}/bin:\${PATH}"
EOF
chmod +x /etc/profile.d/rocm.sh
export ROCM_PATH="${ROCM_HOME}"
export PATH="${ROCM_HOME}/bin:${PATH}"

# Verify ROCm installation
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Verifying ROCm LXC installation...${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
which rocm-smi rocminfo nvtop radeontop
rocminfo | grep -i -A5 'Agent [0-9]'
# rocm-smi without arguments = the nvidia-smi style overview (temperature, power, clocks, fan, perf level, memory, load)
rocm-smi
rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname
# amd-smi is the newer AMD management tool (successor of rocm-smi) - a second, independent view on the GPU
if command -v amd-smi >/dev/null 2>&1; then
    echo ""
    echo -e "${GREEN}>>> amd-smi (newer management tool, successor of rocm-smi):${NC}"
    amd-smi list 2>&1 || true
    amd-smi metric --mem-usage --power --clock --temperature 2>&1 || true
fi
echo ""
echo -e "${GREEN}Monitoring (the AMD equivalents of nvidia-smi):${NC}"
echo "  rocm-smi                                 one-shot overview: temperature, power, clocks, fan, perf level, memory, load"
echo "  amd-smi monitor -p -t -g -m -w 1         live view refreshed every second (power, temperature, gfx clock/util, memory)"
echo "  amd-smi metric --power --clock           detailed power and clock (DPM) state"
echo "  nvtop                                    interactive graphs"
echo "  Note: on APUs like the Radeon 890M some power values can be N/A - the GPU shares the SoC power rail with the CPU."

# Verify installation
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Testing GPU Access in Docker${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}>>> Verifying AMD ROCm installation with Docker...${NC}"
echo ""
# The Docker image brings its own ROCm user-space; the only thing it needs from this container is
# /dev/kfd and /dev/dri. Processes in the image must be members of the groups that own those nodes
# here (render and video; numeric gids because the image may not know the group names) - required
# in unprivileged containers (script 032). Test: rocm-smi + rocminfo, and amd-smi if the image has it.
RENDER_GID=$(getent group render | cut -d: -f3)
VIDEO_GID=$(getent group video | cut -d: -f3)
ROCM_TEST_IMAGE="rocm/dev-ubuntu-24.04:7.2.4"
ROCM_TEST_CMD="docker run --rm --name rocm-smi-test --device /dev/kfd --device /dev/dri --group-add ${VIDEO_GID:-44} --group-add ${RENDER_GID:-993} --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host ${ROCM_TEST_IMAGE} bash -c \"rocm-smi && rocm-smi --showmemuse --showmeminfo all --showproductname && rocminfo | grep -i -A5 'Agent [0-9]' && { command -v amd-smi >/dev/null && amd-smi list && amd-smi metric --mem-usage --power --clock --temperature || echo 'amd-smi not in this image - skipped'; }\""

echo -e "${YELLOW}Test 1: ROCm Info and SMI test${NC}"
echo -e "${YELLOW}Image: ${ROCM_TEST_IMAGE} (~1.2GB)${NC}"
echo -e "${YELLOW}Command: ${ROCM_TEST_CMD}${NC}"
echo ""
read -r -p "Run Test 1? This will download ~1.2GB. [Y/n]: " RUN_TEST1
RUN_TEST1=${RUN_TEST1:-Y}

if [[ "$RUN_TEST1" =~ ^[Yy]$ ]]; then
    if eval "$ROCM_TEST_CMD"; then
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
        echo -e "${RED}✗ AMD ROCm test failed! ✗${NC}"
        echo "Check that /dev/kfd and /dev/dri/renderD* are accessible (ls -la /dev/kfd /dev/dri) and"
        echo "that the container user is in the owning groups (this test adds gids ${VIDEO_GID:-44} and ${RENDER_GID:-993})."
        echo ""
    fi
else
    echo ""
    echo -e "${YELLOW}Tests skipped. You can manually test later with:${NC}"
    echo "  ${ROCM_TEST_CMD}"
    echo ""
fi