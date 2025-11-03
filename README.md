# Proxmox-Setup-Scripts

Automated scripts for setting up GPU-enabled LXC containers on Proxmox with persistent device mapping.

## Quick Start

### Option 1: Guided Installation (Recommended)

```bash
cd /root
git clone https://github.com/jammsen/proxmox-setup-scripts.git
cd proxmox-setup-scripts
./guided-install.sh
```

The guided installer provides:
- ✅ **Interactive menu** with progress tracking
- ✅ **Auto-detection** of completed steps (shows green checkmarks)
- ✅ **Smart defaults** - "all" runs Basic Host Setup with confirmations
- ✅ **Flexible execution** - Run individual scripts, ranges, or all steps
- ✅ **Progress persistence** - Resume where you left off

### Option 2: Manual Installation

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
├── guided-install.sh   # Interactive guided installer (START HERE!)
├── host/               # Host-side scripts (run on Proxmox)
│   ├── 000-list-gpus.sh
│   ├── 001-install-tools.sh
│   ├── 002-setup-igpu-vram.sh
│   ├── 003-install-amd-drivers.sh
│   ├── 004-install-nvidia-drivers.sh
│   ├── 005-verify-nvidia-drivers.sh
│   ├── 006-setup-udev-gpu-rules.sh
│   ├── 007-upgrade-proxmox.sh
│   └── 011-create-gpu-lxc.sh (main LXC creation script)
├── lxc/                # Guest-side scripts (run in LXC container)
│   ├── install-docker-and-container-runtime-in-lxc-guest.sh
│   └── troubleshoot-nvidia-docker.sh
├── includes/           # Shared libraries
│   └── colors.sh
└── README.md
```

## Guided Installer Usage

The `guided-install.sh` script provides an interactive menu:

```bash
./guided-install.sh
```

### Menu Options:

- **`all`** - Run all Basic Host Setup scripts (000-009) with confirmations before each step
  - ✅ Automatically skips already completed steps
  - ✅ Never runs LXC Container Setup (010-019) automatically
  
- **`<number>`** - Run specific script by number
  - Example: `004` runs NVIDIA driver installation
  
- **`<start-end>`** - Run range of scripts
  - Example: `001-006` runs tools, drivers, and udev setup
  
- **`reset`** - Clear progress tracking to start fresh

- **`quit`** - Exit the installer

### Progress Tracking:

The installer automatically detects completed steps by checking:
- Installed packages (htop, nvtop, nvidia-smi)
- Loaded kernel modules (amdgpu, nvidia)
- Configuration files (udev rules, kernel parameters)
- Shows **green checkmarks (✓)** for completed steps

Progress is saved to `.install-progress` file.

### Example Session:

```
========================================
Proxmox GPU Setup - Guided Installer
========================================

Progress: 3 steps completed

=== Basic Host Setup (000-009) ===

  [000]: List all available GPUs and their PCI paths
✓ [001]: Install essential tools (htop, nvtop, etc.)
  [002]: Setup Intel iGPU VRAM allocation
  [003]: Install AMD GPU drivers
✓ [004]: Install NVIDIA GPU drivers
✓ [005]: Verify NVIDIA driver installation
  [006]: Setup udev rules for GPU device permissions
  [007]: Upgrade Proxmox to latest version

=== LXC Container Setup (010-019) ===

  [011]: Create GPU-enabled LXC container (AMD or NVIDIA)

Options:
  all          - Run all Basic Host Setup scripts (with confirmations) [DEFAULT]
  <number>     - Run specific script by number (e.g., 001, 004)
  <start-end>  - Run range of scripts (e.g., 001-006)
  reset        - Clear progress tracking
  quit         - Exit installer

Enter your choice [all]:
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