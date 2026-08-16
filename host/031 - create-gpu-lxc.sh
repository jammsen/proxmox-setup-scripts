#!/usr/bin/env bash
# SCRIPT_DESC: Create GPU-enabled LXC container (privileged, AMD or NVIDIA)
# SCRIPT_DETECT: 

# Enhanced LXC GPU container creation script with automatic GPU detection
# This script ensures correct GPU mapping using persistent PCI paths

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-verify.sh"


echo -e "${YELLOW}Note: This creates a privileged LXC container.${NC}"
echo "Privileged containers give the GPU direct access, which makes setup easy,"
echo "but the container is less isolated or secured from the Proxmox host than an"
echo "unprivileged one. This is fine for a trusted home lab. If you want the"
echo "more isolated option, use script 032 (unprivileged container) instead."
echo ""
read -r -p "Continue with a privileged container? [Y/n]: " ACK_PRIV
[[ "${ACK_PRIV:-Y}" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
echo ""

# Prompt for container ID
read -r -p "Enter container ID [100]: " CONTAINER_ID
CONTAINER_ID=${CONTAINER_ID:-100}

# Prompt for GPU type
echo ""
echo "Select GPU type:"
echo "1) AMD GPU"
echo "2) NVIDIA GPU"
read -r -p "Enter selection [1]: " GPU_TYPE
GPU_TYPE=${GPU_TYPE:-1}
GPU_NAME=""
ADDITIONAL_TAGS=""

# Prompt for GPU PCI address
echo ""
echo -e "${YELLOW}>>> Detecting available GPUs...${NC}"
echo ""

# Auto-detect first GPU of selected type for default
TEMPLATE_FIRST_PCI_PATH=""

if [ "$GPU_TYPE" == "1" ]; then
    GPU_NAME="AMD"
    ADDITIONAL_TAGS="amd"
    echo "=== Available AMD GPUs ==="
    echo ""
    # Show AMD GPUs from lspci
    lspci -nn -D | grep -i amd | grep -i "VGA\|3D\|Display" && echo "" || echo "No AMD GPUs found via lspci"
    
    # Show AMD GPU DRI paths and capture first one for default
    echo "Available AMD GPU PCI paths:"
    for card in /dev/dri/by-path/pci-*-card; do
        if [ -e "$card" ]; then
            # Extract PCI address from path
            pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
            # Get GPU info from lspci
            gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -i "VGA\|3D\|Display" || echo "")
            if echo "$gpu_info" | grep -qi amd; then
                echo "  $pci_addr -> $(ls -l "$card" | awk '{print $NF}') (AMD)"
                echo "    $gpu_info"
                # Set default to first AMD GPU found
                if [ -z "$TEMPLATE_FIRST_PCI_PATH" ]; then
                    TEMPLATE_FIRST_PCI_PATH="$pci_addr"
                fi
            fi
        fi
    done
    echo ""
else
    GPU_NAME="NVIDIA"
    ADDITIONAL_TAGS="nvidia"
    echo "=== Available NVIDIA GPUs ==="
    echo ""
    # Show NVIDIA GPUs with full domain:bus:device.function format
    lspci -nn -D | grep -i nvidia | grep -i "VGA\|3D\|Display" && echo "" || echo "No NVIDIA GPUs found"
    
    # NVIDIA GPUs usually have no /dev/dri entry (nvidia_drm not loaded), so
    # detect via lspci instead of DRI by-path symlinks. CUDA only needs /dev/nvidia*.
    echo "Available NVIDIA GPU PCI paths:"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        pci_addr=$(echo "$line" | awk '{print $1}')
        card="/dev/dri/by-path/pci-${pci_addr}-card"
        if [ -e "$card" ]; then
            echo "  $pci_addr -> $(ls -l "$card" | awk '{print $NF}') (NVIDIA)"
        else
            echo "  $pci_addr (NVIDIA, no /dev/dri entry - fine for CUDA)"
        fi
        echo "    $line"
        # Set default to first NVIDIA GPU found
        if [ -z "$TEMPLATE_FIRST_PCI_PATH" ]; then
            TEMPLATE_FIRST_PCI_PATH="$pci_addr"
        fi
    done < <(lspci -nn -D | grep -i "VGA\|3D\|Display" | grep -i nvidia)
    echo ""
fi

# Prompt with default value
if [ -n "$TEMPLATE_FIRST_PCI_PATH" ]; then
    read -r -p "Enter GPU PCI address [$TEMPLATE_FIRST_PCI_PATH]: " PCI_ADDRESS
    PCI_ADDRESS=${PCI_ADDRESS:-$TEMPLATE_FIRST_PCI_PATH}
else
    read -r -p "Enter GPU PCI address (e.g., 0000:a1:00.0): " PCI_ADDRESS
fi

if [ -z "$PCI_ADDRESS" ]; then
    echo -e "${RED}Error: PCI address is required${NC}"
    exit 1
fi

# Validate PCI path exists
CARD_PATH="/dev/dri/by-path/pci-${PCI_ADDRESS}-card"
RENDER_PATH="/dev/dri/by-path/pci-${PCI_ADDRESS}-render"

if [ "$GPU_TYPE" == "1" ]; then
    # AMD requires DRI devices (ROCm uses card/render nodes)
    if [ ! -e "$CARD_PATH" ]; then
        echo -e "${RED}Error: $CARD_PATH does not exist${NC}"
        exit 1
    fi
    if [ ! -e "$RENDER_PATH" ]; then
        echo -e "${RED}Error: $RENDER_PATH does not exist${NC}"
        exit 1
    fi
else
    # NVIDIA: validate the PCI address exists, DRI nodes are optional
    if ! lspci -D -s "$PCI_ADDRESS" 2>/dev/null | grep -qi nvidia; then
        echo -e "${RED}Error: No NVIDIA device found at PCI address $PCI_ADDRESS${NC}"
        exit 1
    fi
    if [ ! -e "$CARD_PATH" ] || [ ! -e "$RENDER_PATH" ]; then
        echo -e "${YELLOW}Note: No /dev/dri nodes for $PCI_ADDRESS (nvidia_drm not loaded).${NC}"
        echo -e "${YELLOW}DRI mounts are optional; CUDA/Ollama only need /dev/nvidia* devices.${NC}"
    fi
fi

if [ "$GPU_TYPE" == "1" ]; then
    # AMD GPU - validate KFD device
    if [ ! -e "/dev/kfd" ]; then
        echo -e "${YELLOW}Warning: /dev/kfd does not exist. AMD ROCm may not work.${NC}"
        echo -e "${YELLOW}Make sure AMD GPU drivers are properly installed on the host.${NC}"
    fi
    
    echo -e "${GREEN}✓ Found AMD GPU at $PCI_ADDRESS${NC}"
    echo "  Card device: $CARD_PATH"
    echo "  Render device: $RENDER_PATH"
    echo "  KFD device: $([ -e "/dev/kfd" ] && echo "✓ Available" || echo "✗ Not found")"
else
    # NVIDIA GPU - validate NVIDIA-specific devices
    echo -e "${GREEN}✓ Found NVIDIA GPU at $PCI_ADDRESS${NC}"
    echo "  Card device: $CARD_PATH"
    echo "  Render device: $RENDER_PATH"
    echo ""
    echo "Validating NVIDIA driver devices:"
    
    NVIDIA_DEVICES=("/dev/nvidia0" "/dev/nvidiactl" "/dev/nvidia-modeset" "/dev/nvidia-uvm")
    MISSING_DEVICES=()
    
    for dev in "${NVIDIA_DEVICES[@]}"; do
        if [ -e "$dev" ]; then
            echo "  ✓ $dev"
        else
            echo "  ✗ $dev (missing)"
            MISSING_DEVICES+=("$dev")
        fi
    done
    
    if [ ${#MISSING_DEVICES[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Warning: Some NVIDIA devices are missing:${NC}"
        for dev in "${MISSING_DEVICES[@]}"; do
            echo -e "${YELLOW}  - $dev${NC}"
        done
        echo -e "${YELLOW}Make sure NVIDIA drivers are properly installed on the host.${NC}"
        echo -e "${YELLOW}The container may not function correctly without these devices.${NC}"
        echo ""
        read -r -p "Continue anyway? [y/N]: " CONTINUE
        CONTINUE=${CONTINUE:-N}
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 1
        fi
    fi
fi

echo ""
HOSTNAME_TEMPLATE="docker-gpu-${GPU_NAME,,}-$CONTAINER_ID"
read -r -p "Enter hostname [$HOSTNAME_TEMPLATE]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$HOSTNAME_TEMPLATE}

IP_TEMPLATE="10.0.0.$CONTAINER_ID"
read -r -p "Enter container IP address [$IP_TEMPLATE]: " IP_ADDRESS
IP_ADDRESS=${IP_ADDRESS:-$IP_TEMPLATE}

GW_TEMPLATE="10.0.0.1"
read -r -p "Enter gateway [$GW_TEMPLATE]: " GATEWAY
GATEWAY=${GATEWAY:-$GW_TEMPLATE}

# Container resources (cores/RAM/swap are fixed defaults, disk size and storage are asked below)
CT_CORES=8
CT_MEMORY_MB=8192
CT_SWAP_MB=4096

# Storage for the container disk: default to local-zfs if it exists, otherwise the first
# storage that can hold container root disks
STORAGE_LIST=$(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')
if echo "$STORAGE_LIST" | grep -qx "local-zfs"; then
    STORAGE_TEMPLATE="local-zfs"
else
    STORAGE_TEMPLATE=$(echo "$STORAGE_LIST" | head -1)
fi
echo ""
echo "Storages available for container disks:"
pvesm status --content rootdir 2>/dev/null | awk 'NR==1 || $3=="active"' | awk '{printf "  %-16s %-10s free: %6.1f GB of %6.1f GB\n", $1, $2, $6/1024/1024, $4/1024/1024}' | sed '1s/.*/  (name  type  free \/ total)/'
read -r -p "Enter storage for the container disk [$STORAGE_TEMPLATE]: " CT_STORAGE
CT_STORAGE=${CT_STORAGE:-$STORAGE_TEMPLATE}
if ! echo "$STORAGE_LIST" | grep -qx "$CT_STORAGE"; then
    echo -e "${RED}Error: storage '$CT_STORAGE' not found or cannot hold container disks${NC}"
    exit 1
fi

echo ""
if [ "$GPU_TYPE" == "1" ]; then
    echo "Disk size for the container. The base system with Docker and the AMD ROCm stack needs"
    echo "about 20 GB - the rest is for your models and data."
else
    echo "Disk size for the container. The base system with Docker and the NVIDIA libraries needs"
    echo "about 2 GB - the rest is for your models and data."
fi
read -r -p "Enter container disk size in GB [75]: " CT_DISK_GB
CT_DISK_GB=${CT_DISK_GB:-75}
if ! [[ "$CT_DISK_GB" =~ ^[0-9]+$ ]] || [ "$CT_DISK_GB" -lt 8 ]; then
    echo -e "${RED}Error: disk size must be a whole number of GB (at least 8)${NC}"
    exit 1
fi
STORAGE_FREE_GB=$(pvesm status --storage "$CT_STORAGE" 2>/dev/null | awk 'NR==2 {printf "%d", $6/1024/1024}')
if [ -n "$STORAGE_FREE_GB" ] && [ "$STORAGE_FREE_GB" -lt "$CT_DISK_GB" ]; then
    echo -e "${YELLOW}Note: $CT_STORAGE has only ${STORAGE_FREE_GB} GB free, less than the ${CT_DISK_GB} GB disk.${NC}"
    echo -e "${YELLOW}Thin-provisioned storage (ZFS/LVM-thin) will still work, but the container can run out of space later.${NC}"
fi

# Generate random MAC address
MAC_ADDRESS=$(printf 'BC:24:11:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))

echo ""
echo -e "${GREEN}>>> Configuration Summary${NC}"
echo "Container ID: $CONTAINER_ID"
echo "GPU Type: $([ "$GPU_TYPE" == "1" ] && echo "AMD" || echo "NVIDIA")"
echo "PCI Address: $PCI_ADDRESS"
echo "IP Address: $IP_ADDRESS"
echo "Gateway: $GATEWAY"
echo "Hostname: $HOSTNAME"
echo "MAC Address: $MAC_ADDRESS"
echo "Resources: ${CT_CORES} cores, $((CT_MEMORY_MB/1024)) GB RAM, $((CT_SWAP_MB/1024)) GB swap"
echo "Disk: ${CT_DISK_GB} GB on ${CT_STORAGE}${STORAGE_FREE_GB:+ (${STORAGE_FREE_GB} GB free)}"
echo ""
read -r -p "Proceed with container creation? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}>>> Updating Proxmox VE Appliance list${NC}"
pveam update

# Template selection per GPU type:
#  - NVIDIA: Ubuntu 26.04 LTS (CUDA repo ubuntu2604, Docker, container toolkit and Ollama all support it)
#  - AMD:    Ubuntu 24.04 LTS (ROCm apt repos only exist for jammy/noble, no resolute yet)
if [ "$GPU_TYPE" == "1" ]; then
    LXC_TEMPLATE="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    LXC_TEMPLATE_NAME="Ubuntu 24.04"
else
    LXC_TEMPLATE="ubuntu-26.04-standard_26.04-1_amd64.tar.zst"
    LXC_TEMPLATE_NAME="Ubuntu 26.04"
fi

echo -e "${GREEN}>>> Downloading ${LXC_TEMPLATE_NAME} LXC template to local storage${NC}"
pveam download local "$LXC_TEMPLATE" 2>/dev/null || echo "Template already exists"

echo -e "${GREEN}>>> Creating LXC container with GPU passthrough support${NC}"
pct create "$CONTAINER_ID" "local:vztmpl/${LXC_TEMPLATE}" \
    --arch amd64 \
    --cores "$CT_CORES" \
    --features nesting=1 \
    --hostname "$HOSTNAME" \
    --memory "$CT_MEMORY_MB" \
    --net0 "name=eth0,bridge=vmbr0,firewall=1,gw=$GATEWAY,hwaddr=$MAC_ADDRESS,ip=$IP_ADDRESS/24,type=veth" \
    --ostype ubuntu \
    --password testing \
    --rootfs "${CT_STORAGE}:${CT_DISK_GB}" \
    --swap "$CT_SWAP_MB" \
    --tags "docker;gpu;${ADDITIONAL_TAGS}" \
    --unprivileged 0

echo -e "${GREEN}>>> Added LXC container with ID $CONTAINER_ID${NC}"

# Configure GPU passthrough based on type
if [ "$GPU_TYPE" == "1" ]; then
    # AMD GPU Configuration
    echo -e "${GREEN}>>> Configuring AMD GPU passthrough${NC}"
    
    cat >> "/etc/pve/lxc/${CONTAINER_ID}.conf" << EOF
# ===== AMD GPU Passthrough Configuration =====
# PCI Address: $PCI_ADDRESS
# Using persistent by-path device names to ensure consistent mapping
# Allow access to cgroup devices (DRI and KFD)
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 235:* rwm
# Mount DRI devices using persistent PCI paths
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-render dev/dri/renderD128 none bind,optional,create=file
# Mount KFD device (ROCm compute interface - required for ROCm)
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
# Allow system-level capabilities for GPU drivers
lxc.apparmor.profile: unconfined
lxc.cap.drop:
# ===== End GPU Configuration =====
EOF
else
    # NVIDIA GPU Configuration
    echo -e "${GREEN}>>> Configuring NVIDIA GPU passthrough${NC}"
    
    cat >> "/etc/pve/lxc/${CONTAINER_ID}.conf" << EOF
# ===== NVIDIA GPU Passthrough Configuration =====
# PCI Address: $PCI_ADDRESS
# Allow access to cgroup devices (NVIDIA and DRI)
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.cgroup2.devices.allow: c 237:* rwm
lxc.cgroup2.devices.allow: c 238:* rwm
lxc.cgroup2.devices.allow: c 239:* rwm
lxc.cgroup2.devices.allow: c 240:* rwm
lxc.cgroup2.devices.allow: c 508:* rwm
# Mount NVIDIA devices
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap1 dev/nvidia-caps/nvidia-cap1 none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap2 dev/nvidia-caps/nvidia-cap2 none bind,optional,create=file
# Mount DRI devices using persistent PCI paths
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-render dev/dri/renderD128 none bind,optional,create=file
# Allow system-level capabilities for GPU drivers
lxc.apparmor.profile: unconfined
lxc.cap.drop:
# ===== End GPU Configuration =====
EOF
fi

echo -e "${GREEN}>>> Starting container${NC}"
pct start "$CONTAINER_ID"
sleep 5

echo -e "${GREEN}>>> Mounting scripts directory into container${NC}"
# Get the repository root directory (parent of host/)
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# Add bind mount for scripts directory
pct set "$CONTAINER_ID" -mp0 "$REPO_DIR,mp=/root/proxmox-setup-scripts"

echo -e "${GREEN}>>> Enabling SSH root login${NC}"
pct exec "$CONTAINER_ID" -- bash -c "sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config"
pct exec "$CONTAINER_ID" -- bash -c "sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config"
pct exec "$CONTAINER_ID" -- systemctl restart sshd

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}>>> LXC Container Setup Complete! <<<${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
read -r -p "Verify GPU devices inside the container now? [Y/n]: " RUN_VERIFY
RUN_VERIFY=${RUN_VERIFY:-Y}
if [[ "$RUN_VERIFY" =~ ^[Yy]$ ]]; then
    verify_gpu_in_container "$CONTAINER_ID" "$GPU_TYPE"
else
    echo "You can verify manually later:"
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/dri/ /dev/kfd /dev/nvidia*"
    echo ""
fi

if [ "$GPU_TYPE" == "1" ]; then
    # AMD GPU Configuration
    read -r -p "Install Docker and AMD ROCm libraries now? [Y/n]: " RUN_INSTALL
    RUN_INSTALL=${RUN_INSTALL:-Y}
    
    if [[ "$RUN_INSTALL" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}>>> Running AMD GPU installation script...${NC}"
        pct exec "$CONTAINER_ID" -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-amd-drivers-in-lxc.sh

    else
        echo ""
        echo -e "${YELLOW}Installation skipped. You can run it manually later:${NC}"
        echo "  # From Proxmox host:"
        echo "  pct exec $CONTAINER_ID -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-amd-drivers-in-lxc.sh"
        echo ""
        echo "  # Or SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-amd-drivers-in-lxc.sh"
    fi
else
    # NVIDIA GPU Configuration
    read -r -p "Install Docker, NVIDIA libraries, and NVIDIA Container Toolkit now? [Y/n]: " RUN_INSTALL
    RUN_INSTALL=${RUN_INSTALL:-Y}
    
    if [[ "$RUN_INSTALL" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}>>> Running NVIDIA GPU installation script...${NC}"
        pct exec "$CONTAINER_ID" -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-nvidia-drivers-in-lxc.sh
    else
        echo ""
        echo -e "${YELLOW}Installation skipped. You can run it manually later:${NC}"
        echo "  # From Proxmox host:"
        echo "  pct exec $CONTAINER_ID -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-nvidia-drivers-in-lxc.sh"
        echo ""
        echo "  # Or SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-nvidia-drivers-in-lxc.sh"
    fi
fi
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}>>> LXC Container Setup and Testing Complete! <<<${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Container ID: $CONTAINER_ID"
echo "GPU Type: $([ "$GPU_TYPE" == "1" ] && echo "AMD" || echo "NVIDIA")"
echo "GPU PCI Address: $PCI_ADDRESS"
echo "Resources: ${CT_CORES} cores, $((CT_MEMORY_MB/1024)) GB RAM, $((CT_SWAP_MB/1024)) GB swap"
echo "Disk: ${CT_DISK_GB} GB on ${CT_STORAGE}"
echo "SSH Access: ssh root@$IP_ADDRESS"
echo "Default Password: testing"
echo "Scripts mounted at: /root/proxmox-setup-scripts"
echo ""
echo -e "${YELLOW}IMPORTANT: Change the default password after first login!${NC}"
echo ""

