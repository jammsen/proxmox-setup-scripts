# Proxmox-Setup-Scripts

Automated scripts for setting up GPU-enabled LXC containers on Proxmox with persistent device mapping.

## Quick Start

### 1. Clone Repository on Proxmox Host

```bash
cd /root
git clone https://github.com/jammsen/proxmox-setup-scripts.git
cd proxmox-setup-scripts
```

### 2. Setup GPU on Host (if needed)

```bash
cd host

# For NVIDIA GPUs:
./004 - install-nvidia-drivers.sh

# For AMD GPUs:
./003 - install-amd-drivers.sh

# Setup udev rules for persistent GPU device paths:
./006 - setup-udev-gpu-rules.sh
```

### 3. Create GPU-Enabled LXC Container

```bash
cd /root/proxmox-setup-scripts/host
./008 - create-gpu-lxc.sh
```

This script will:
- Auto-detect available GPUs
- Create LXC container with GPU passthrough
- Configure persistent PCI-based device mapping
- **Automatically mount scripts directory** at `/root/proxmox-setup-scripts` inside container
- Enable SSH access

### 4. Install Docker + NVIDIA Container Toolkit

#### Option A: Run from Host (Recommended)

```bash
# Run installation script directly from host into container
pct exec <CONTAINER_ID> -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-container-runtime-in-lxc-guest.sh
```

#### Option B: SSH into Container

```bash
# SSH into container
ssh root@<CONTAINER_IP>

# Navigate to mounted scripts
cd /root/proxmox-setup-scripts/lxc

# Run installation
./install-docker-and-container-runtime-in-lxc-guest.sh
```

### 5. Verify GPU Access

```bash
# From host:
pct exec <CONTAINER_ID> -- docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi

# From inside container:
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```

## Features

- **Persistent GPU Mapping**: Uses PCI paths (`/dev/dri/by-path/pci-*`) instead of card0/card1
- **Automatic GPU Detection**: Detects AMD and NVIDIA GPUs with vendor filtering
- **Scripts Available Inside Container**: Repository auto-mounted at `/root/proxmox-setup-scripts`
- **Interactive Setup**: User-friendly prompts with sensible defaults
- **Full Testing Suite**: PyTorch CUDA validation included

## Repository Structure

```
proxmox-setup-scripts/
├── host/               # Host-side scripts (run on Proxmox)
│   ├── 000-list-gpus.sh
│   ├── 003-install-amd-drivers.sh
│   ├── 004-install-nvidia-drivers.sh
│   ├── 006-setup-udev-gpu-rules.sh
│   ├── 008-create-gpu-lxc.sh (main script)
│   └── 999-fix-existing-lxc-gpu-mapping.sh
├── lxc/                # Guest-side scripts (run in LXC container)
│   ├── install-docker-and-container-runtime-in-lxc-guest.sh
│   └── troubleshoot-nvidia-docker.sh
├── includes/           # Shared libraries
│   └── colors.sh
└── README.md
```

## Key Benefits of This Approach

1. **No File Copying**: Scripts mounted directly from host
2. **Always Up-to-Date**: Pull changes with `git pull` on host, available immediately in all containers
3. **Easy Execution**: Run scripts from host using `pct exec` or from inside container
4. **Version Control**: All containers use the same script version from git
5. **Easy Updates**: Update scripts once on host, available to all containers

## Troubleshooting

If GPU isn't detected in container:

```bash
# Check devices from host:
pct exec <CONTAINER_ID> -- ls -la /dev/nvidia*
pct exec <CONTAINER_ID> -- ls -la /dev/dri/

# Run troubleshooting script:
pct exec <CONTAINER_ID> -- bash /root/proxmox-setup-scripts/lxc/troubleshoot-nvidia-docker.sh
```

## Helpful Links

- https://jocke.no/2025/04/20/plex-gpu-transcoding-in-docker-on-lxc-on-proxmox-v2/#comment-130670