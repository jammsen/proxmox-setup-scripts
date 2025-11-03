#!/usr/bin/env bash
# SCRIPT_DESC: Create AMD GPU-enabled LXC container (deprecated)
# SCRIPT_DETECT: 

# Prompt for container ID with default value of 100
read -r -p "Enter container ID [100]: " CONTAINER_ID
CONTAINER_ID=${CONTAINER_ID:-100}

echo ">>> Using container ID: $CONTAINER_ID"

echo ">>> Updating Proxmox VE Appliance list"
pveam update
echo ">>> Downloading Ubuntu 24.04 LXC template to local storage"
pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst
echo ">>> Creating AMD LXC container template with GPU passthrough support"
#pct create "$CONTAINER_ID" local:160G --arch amd64 --cores 8 --features nesting=1 --hostname ollama-docker-amd --memory 8192 --net0 name=eth0,bridge=vmbr0,firewall=1,gw=10.0.0.1,hwaddr=BC:24:11:F5:74:6A,ip=10.0.0.206/24,type=veth --ostype ubuntu --password testing --rootfs local-zfs:subvol-${CONTAINER_ID}-disk-0,size=160G --swap 4096 --tags docker;ollama;amd --unprivileged 0
pct create "$CONTAINER_ID" local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst --arch amd64 --cores 8 --features nesting=1 --hostname ollama-docker-amd --memory 8192 --net0 name=eth0,bridge=vmbr0,firewall=1,gw=10.0.0.1,hwaddr=BC:24:11:F5:74:6A,ip=10.0.0.206/24,type=veth --ostype ubuntu --password testing --rootfs local-zfs:160,size=160G --swap 4096 --tags "docker;ollama;amd" --unprivileged 0
echo ">>> Added LXC container with ID $CONTAINER_ID and default password 'testing'"
echo ">>> Configuring GPU passthrough for AMD devices"
cat >> "/etc/pve/lxc/${CONTAINER_ID}.conf" << EOF
# ===== GPU Passthrough Configuration =====
# Allow access to cgroup devices (DRI and KFD)
# Device numbers: 226 = DRI major, 235 = KFD major
# Mount DRI devices (GPU devices)
# Adjust /dev/dri/by-path/pci-0000:XX:00.0-TYPE based on which card/render is the APU
# Mount KFD device (ROCm compute interface - required for ROCm)
# Allow system-level capabilities for GPU drivers
# Suppress capability drops to allow GPU driver access
# ===== End GPU Configuration =====
lxc.cgroup2.devices.allow: c 226:1 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.cgroup2.devices.allow: c 235:* rwm
lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-render dev/dri/renderD128 none bind,optional,create=file
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
lxc.apparmor.profile: unconfined
lxc.cap.drop:
EOF
echo ">>> Added necessary device permissions and mount entries for GPU passthrough"
echo ">>> Starting container and enabling SSH root login"
pct start "$CONTAINER_ID"
sleep 5
pct exec "$CONTAINER_ID" -- bash -c "sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config"
pct exec "$CONTAINER_ID" -- bash -c "sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config"
pct exec "$CONTAINER_ID" -- systemctl restart sshd
echo ">>> SSH root login enabled"
echo ">>> LXC container with ID $CONTAINER_ID is set up and running."
echo ">>> You can access it via: ssh root@10.0.0.206"
echo ">>> Default password is 'testing'. Please change it after first login."