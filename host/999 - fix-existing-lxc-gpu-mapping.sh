#!/usr/bin/env bash

# Script to fix GPU mapping in existing LXC containers
# Converts from card0/card1/renderD128/renderD129 to persistent PCI path-based mapping

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}>>> LXC GPU Mapping Fix Tool${NC}"
echo "This script will update an existing LXC container to use persistent PCI paths"
echo "for GPU device mapping instead of variable card0/card1/renderD128/renderD129 names"
echo ""

# List existing containers
echo "=== Existing LXC Containers ==="
pct list
echo ""

read -r -p "Enter container ID to fix: " CONTAINER_ID

if [ -z "$CONTAINER_ID" ]; then
    echo -e "${RED}Error: Container ID is required${NC}"
    exit 1
fi

CONF_FILE="/etc/pve/lxc/${CONTAINER_ID}.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo -e "${RED}Error: Configuration file $CONF_FILE not found${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}>>> Current GPU configuration in $CONF_FILE:${NC}"
grep -E "lxc\.(mount\.entry|cgroup)" "$CONF_FILE" | grep -E "(dri|kfd|nvidia)" || echo "No GPU configuration found"
echo ""

# Detect GPU type from config
GPU_TYPE="unknown"
if grep -q "kfd" "$CONF_FILE"; then
    GPU_TYPE="amd"
elif grep -q "nvidia" "$CONF_FILE"; then
    GPU_TYPE="nvidia"
fi

echo "Detected GPU type: $GPU_TYPE"
echo ""

# Show available GPUs
echo -e "${YELLOW}>>> Available GPUs and their PCI paths:${NC}"
echo ""

# Show all GPUs with vendor info
echo "=== All GPUs Detected ==="
lspci -nn -D | grep -i "VGA\|3D\|Display"
echo ""

echo "=== GPU PCI Path Mappings ==="
for card in /dev/dri/by-path/pci-*-card; do
    if [ -e "$card" ]; then
        pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
        card_link=$(ls -l "$card" | awk '{print $NF}')
        render_file="${card%-card}-render"
        render_link=$(ls -l "$render_file" 2>/dev/null | awk '{print $NF}' || echo "N/A")
        gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -i "VGA\|3D\|Display" | cut -d: -f3- || echo "Unknown")
        
        vendor="Unknown"
        if echo "$gpu_info" | grep -qi amd; then
            vendor="AMD"
        elif echo "$gpu_info" | grep -qi nvidia; then
            vendor="NVIDIA"
        elif echo "$gpu_info" | grep -qi intel; then
            vendor="Intel"
        fi
        
        echo "  PCI: $pci_addr [$vendor]"
        echo "    Card: $card_link, Render: $render_link"
        echo "    $gpu_info"
        echo ""
    fi
done

read -r -p "Enter GPU PCI address for this container (e.g., 0000:c7:00.0): " PCI_ADDRESS

if [ -z "$PCI_ADDRESS" ]; then
    echo -e "${RED}Error: PCI address is required${NC}"
    exit 1
fi

# Validate paths exist
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

echo -e "${GREEN}✓ Found GPU at $PCI_ADDRESS${NC}"
echo ""

# Confirm
read -r -p "Stop container and update configuration? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Stop container if running
echo -e "${YELLOW}>>> Stopping container $CONTAINER_ID${NC}"
pct stop "$CONTAINER_ID" 2>/dev/null || echo "Container already stopped"
sleep 2

# Backup configuration
BACKUP_FILE="${CONF_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
echo -e "${GREEN}>>> Backing up configuration to $BACKUP_FILE${NC}"
cp "$CONF_FILE" "$BACKUP_FILE"

# Remove old GPU mount entries
echo -e "${GREEN}>>> Removing old GPU mount entries${NC}"
sed -i '/lxc\.mount\.entry:.*\/dev\/dri\/card[0-9]/d' "$CONF_FILE"
sed -i '/lxc\.mount\.entry:.*\/dev\/dri\/renderD[0-9]/d' "$CONF_FILE"

# Check if new entries already exist
if grep -q "by-path/pci-${PCI_ADDRESS}" "$CONF_FILE"; then
    echo -e "${YELLOW}>>> PCI path entries already exist, updating them${NC}"
    sed -i "/lxc\.mount\.entry:.*by-path\/pci-${PCI_ADDRESS}-card/d" "$CONF_FILE"
    sed -i "/lxc\.mount\.entry:.*by-path\/pci-${PCI_ADDRESS}-render/d" "$CONF_FILE"
fi

# Find where to insert new entries (after cgroup entries or before apparmor)
if grep -q "lxc.cgroup2.devices.allow" "$CONF_FILE"; then
    # Insert after last cgroup entry
    LAST_CGROUP_LINE=$(grep -n "lxc.cgroup2.devices.allow" "$CONF_FILE" | tail -1 | cut -d: -f1)
    sed -i "${LAST_CGROUP_LINE}a\\# Mount DRI devices using persistent PCI paths (PCI: ${PCI_ADDRESS})\\nlxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-card dev/dri/card0 none bind,optional,create=file\\nlxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-render dev/dri/renderD128 none bind,optional,create=file" "$CONF_FILE"
else
    # Append to end
    cat >> "$CONF_FILE" << EOF
# Mount DRI devices using persistent PCI paths (PCI: ${PCI_ADDRESS})
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-render dev/dri/renderD128 none bind,optional,create=file
EOF
fi

# Ensure cgroup permissions are set correctly
if ! grep -q "lxc.cgroup2.devices.allow: c 226:\* rwm" "$CONF_FILE"; then
    echo -e "${YELLOW}>>> Adding missing cgroup permissions for DRI devices${NC}"
    sed -i "/lxc.cgroup2.devices.allow/a lxc.cgroup2.devices.allow: c 226:* rwm" "$CONF_FILE"
fi

echo ""
echo -e "${GREEN}>>> Updated GPU configuration in $CONF_FILE:${NC}"
grep -E "lxc\.(mount\.entry|cgroup)" "$CONF_FILE" | grep -E "(dri|kfd|nvidia|by-path)" || echo "No GPU configuration found"
echo ""

# Start container
read -r -p "Start container now? [Y/n]: " START
START=${START:-Y}

if [[ "$START" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}>>> Starting container $CONTAINER_ID${NC}"
    pct start "$CONTAINER_ID"
    sleep 3
    
    echo ""
    echo -e "${GREEN}>>> Verifying GPU devices inside container:${NC}"
    pct exec "$CONTAINER_ID" -- ls -la /dev/dri/
    
    if [ "$GPU_TYPE" == "amd" ]; then
        echo ""
        echo -e "${GREEN}>>> Verifying KFD device:${NC}"
        pct exec "$CONTAINER_ID" -- ls -la /dev/kfd 2>/dev/null || echo "KFD not found"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}>>> GPU Mapping Fix Complete! <<<${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Container: $CONTAINER_ID"
echo "GPU PCI Address: $PCI_ADDRESS"
echo "Backup: $BACKUP_FILE"
echo ""
echo "The container now uses persistent PCI path-based GPU mapping."
echo "The GPU will always map consistently, regardless of boot order."
