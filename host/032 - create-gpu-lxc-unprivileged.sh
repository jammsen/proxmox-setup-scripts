#!/usr/bin/env bash
# SCRIPT_DESC: Create GPU-enabled LXC container (unprivileged, AMD or NVIDIA)
# SCRIPT_DETECT: 

# Unprivileged variant of 031: same wizard, but the container runs with UID mapping,
# keyctl=1,nesting=1 (needed for Docker) and Proxmox dev[n] device passthrough instead
# of raw cgroup/mount lines and an unconfined AppArmor profile.
# dev[n] creates its own device nodes with the given gid/mode inside the container
# (PVE >= 8.1), so host-side udev rules (script 007) are not needed.

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-verify.sh"


echo -e "${YELLOW}Note: This creates an unprivileged LXC container.${NC}"
echo "Unprivileged containers are better isolated and secured from the Proxmox host"
echo "than privileged ones (scripts 030/031). GPU devices are passed through with"
echo "Proxmox's built-in device passthrough (dev0, dev1, ...)."
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
    --cores 8 \
    --features keyctl=1,nesting=1 \
    --hostname "$HOSTNAME" \
    --memory 8192 \
    --net0 "name=eth0,bridge=vmbr0,firewall=1,gw=$GATEWAY,hwaddr=$MAC_ADDRESS,ip=$IP_ADDRESS/24,type=veth" \
    --ostype ubuntu \
    --password testing \
    --rootfs local-zfs:160 \
    --swap 4096 \
    --tags "docker;gpu;${ADDITIONAL_TAGS}" \
    --unprivileged 1

echo -e "${GREEN}>>> Added LXC container with ID $CONTAINER_ID${NC}"

# Configure GPU passthrough via Proxmox device passthrough (dev[n]).
# Unlike 030/031 no cgroup allow lines, bind mounts or unconfined AppArmor are needed;
# pct handles the UID/GID mapping for the device nodes.
DEV_INDEX=0
add_dev() {
    # $1 = host device path, $2 = extra options (e.g. gid=44,mode=0660), skips missing devices
    if [ -e "$1" ]; then
        pct set "$CONTAINER_ID" "--dev${DEV_INDEX}" "$1${2:+,$2}"
        echo "  dev${DEV_INDEX}: $1${2:+ ($2)}"
        DEV_INDEX=$((DEV_INDEX+1))
    fi
}

if [ "$GPU_TYPE" == "1" ]; then
    # AMD: DRI card/render + KFD, owned by the container's video/render groups so the
    # in-container install script's 'usermod -aG render,video root' gives access.
    echo -e "${GREEN}>>> Starting container once to read video/render group IDs${NC}"
    pct start "$CONTAINER_ID"
    sleep 5
    VIDEO_GID=$(pct exec "$CONTAINER_ID" -- getent group video | cut -d: -f3)
    RENDER_GID=$(pct exec "$CONTAINER_ID" -- getent group render | cut -d: -f3 || true)
    if [ -z "$RENDER_GID" ]; then
        pct exec "$CONTAINER_ID" -- groupadd -r render
        RENDER_GID=$(pct exec "$CONTAINER_ID" -- getent group render | cut -d: -f3)
    fi
    pct stop "$CONTAINER_ID"
    echo "  video group: $VIDEO_GID, render group: $RENDER_GID"

    echo -e "${GREEN}>>> Configuring AMD GPU passthrough${NC}"
    # dev[n] recreates the node at the same path inside the container, so pass the real
    # /dev/dri/cardN + renderDN nodes (resolved from the persistent by-path link) - ROCm/libdrm
    # look for those names, not for the by-path name.
    add_dev "$(readlink -f "$CARD_PATH")"   "gid=${VIDEO_GID},mode=0660"
    add_dev "$(readlink -f "$RENDER_PATH")" "gid=${RENDER_GID},mode=0660"
    add_dev /dev/kfd                        "gid=${RENDER_GID},mode=0660"
else
    # NVIDIA: CUDA devices world-RW like the driver creates them on the host; DRI/modeset/caps only if present
    echo -e "${GREEN}>>> Configuring NVIDIA GPU passthrough${NC}"
    add_dev /dev/nvidia0            "mode=0666"
    add_dev /dev/nvidiactl          "mode=0666"
    add_dev /dev/nvidia-uvm         "mode=0666"
    add_dev /dev/nvidia-uvm-tools   "mode=0666"
    add_dev /dev/nvidia-modeset     "mode=0666"
    add_dev /dev/nvidia-caps/nvidia-cap1 "mode=0444"
    add_dev /dev/nvidia-caps/nvidia-cap2 "mode=0444"
    [ -e "$CARD_PATH" ]   && add_dev "$(readlink -f "$CARD_PATH")"   "mode=0666"
    [ -e "$RENDER_PATH" ] && add_dev "$(readlink -f "$RENDER_PATH")" "mode=0666"
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
echo "Container ID: $CONTAINER_ID"
echo "GPU Type: $([ "$GPU_TYPE" == "1" ] && echo "AMD" || echo "NVIDIA")"
echo "GPU PCI Address: $PCI_ADDRESS"
echo "SSH Access: ssh root@$IP_ADDRESS"
echo "Default Password: testing"
echo "Scripts mounted at: /root/proxmox-setup-scripts"
echo ""
echo -e "${YELLOW}IMPORTANT: Change the default password after first login!${NC}"
echo ""
read -r -p "Verify GPU devices inside the container now? [Y/n]: " RUN_VERIFY
RUN_VERIFY=${RUN_VERIFY:-Y}
if [[ "$RUN_VERIFY" =~ ^[Yy]$ ]]; then
    verify_gpu_in_container "$CONTAINER_ID" "$GPU_TYPE"
    echo "If required devices are missing, check the host devices (ls -la /dev/dri /dev/kfd /dev/nvidia*)"
    echo "and the dev0..devN entries in /etc/pve/lxc/${CONTAINER_ID}.conf"
    echo ""
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
        echo ""
        echo "  # You can SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-amd-drivers-in-lxc.sh"

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
        echo ""
        echo "  # You can SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-nvidia-drivers-in-lxc.sh"
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
echo "SSH Access: ssh root@$IP_ADDRESS"
echo "Default Password: testing"
echo "Scripts mounted at: /root/proxmox-setup-scripts"
echo ""
echo -e "${YELLOW}IMPORTANT: Change the default password after first login!${NC}"
echo ""

