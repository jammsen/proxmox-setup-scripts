#!/usr/bin/env bash
# SCRIPT_DESC: Create GPU-enabled LXC container (AMD or NVIDIA or BOTH)
# SCRIPT_DETECT: 

# Enhanced LXC GPU container creation script with automatic GPU detection
# This script ensures correct GPU mapping using persistent PCI paths

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

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
    
    echo "Available NVIDIA GPU PCI paths:"
    for card in /dev/dri/by-path/pci-*-card; do
        if [ -e "$card" ]; then
            pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
            gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -i "VGA\|3D\|Display" || echo "")
            if echo "$gpu_info" | grep -qi nvidia; then
                echo "  $pci_addr -> $(ls -l "$card" | awk '{print $NF}') (NVIDIA)"
                echo "    $gpu_info"
                # Set default to first NVIDIA GPU found
                if [ -z "$TEMPLATE_FIRST_PCI_PATH" ]; then
                    TEMPLATE_FIRST_PCI_PATH="$pci_addr"
                fi
            fi
        fi
    done
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

if [ ! -e "$CARD_PATH" ]; then
    echo -e "${RED}Error: $CARD_PATH does not exist${NC}"
    exit 1
fi
if [ ! -e "$RENDER_PATH" ]; then
    echo -e "${RED}Error: $RENDER_PATH does not exist${NC}"
    exit 1
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
HOSTNAME_TEMPLATE="ollama-docker-${GPU_NAME,,}"
read -r -p "Enter hostname [$HOSTNAME_TEMPLATE]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$HOSTNAME_TEMPLATE}

IP_TEMPLATE="10.0.0.206"
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

echo -e "${GREEN}>>> Downloading Ubuntu 24.04 LXC template to local storage${NC}"
pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst 2>/dev/null || echo "Template already exists"

echo -e "${GREEN}>>> Creating LXC container with GPU passthrough support${NC}"
pct create "$CONTAINER_ID" local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
    --arch amd64 \
    --cores 8 \
    --features nesting=1 \
    --hostname "$HOSTNAME" \
    --memory 8192 \
    --net0 "name=eth0,bridge=vmbr0,firewall=1,gw=$GATEWAY,hwaddr=$MAC_ADDRESS,ip=$IP_ADDRESS/24,type=veth" \
    --ostype ubuntu \
    --password testing \
    --rootfs local-zfs:160 \
    --swap 4096 \
    --tags "docker;ollama;${ADDITIONAL_TAGS}" \
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
echo "Container ID: $CONTAINER_ID"
echo "GPU Type: $([ "$GPU_TYPE" == "1" ] && echo "AMD" || echo "NVIDIA")"
echo "GPU PCI Address: $PCI_ADDRESS"
echo "SSH Access: ssh root@$IP_ADDRESS"
echo "Default Password: testing"
echo "Scripts mounted at: /root/proxmox-setup-scripts"
echo ""
echo -e "${YELLOW}IMPORTANT: Change the default password after first login!${NC}"
echo ""
echo "To verify GPU inside container:"
if [ "$GPU_TYPE" == "1" ]; then
    # AMD GPU Configuration
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/dri/"
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/kfd"
    echo ""
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
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/nvidia*"
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/dri/"
    echo ""
    read -r -p "Install Docker, NVIDIA libraries, and NVIDIA Container Toolkit now? [Y/n]: " RUN_INSTALL
    RUN_INSTALL=${RUN_INSTALL:-Y}
    
    if [[ "$RUN_INSTALL" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}>>> Running NVIDIA GPU installation script...${NC}"
        pct exec "$CONTAINER_ID" -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-container-runtime-in-lxc-guest.sh
    else
        echo ""
        echo -e "${YELLOW}Installation skipped. You can run it manually later:${NC}"
        echo "  # From Proxmox host:"
        echo "  pct exec $CONTAINER_ID -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-container-runtime-in-lxc-guest.sh"
        echo ""
        echo "  # Or SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-container-runtime-in-lxc-guest.sh"
    fi
fi
echo ""
