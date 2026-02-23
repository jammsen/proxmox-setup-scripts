# Proxmox Setup Scripts

**Automated setup scripts for Proxmox VE with an interactive guided installer.**

This project provides a collection of scripts to automate common Proxmox VE setup tasks, with a current focus on GPU-enabled LXC containers. The modular design makes it easy to add new automation scripts for any Proxmox setup scenario.

---

## 🎯 Current Features

This collection of scripts currently focuses on GPU-enabled LXC containers, with plans to expand to other Proxmox automation tasks:

### **GPU Support (Current Focus)**

**Host Setup (Proxmox)**
- Installs and configures AMD ROCm or NVIDIA CUDA drivers
- Sets up persistent GPU device mapping using PCI paths
- Configures udev rules for proper device permissions
- Verifies driver installation and GPU accessibility

**Container Setup (LXC)**
- Creates unprivileged LXC containers with GPU passthrough
- Installs Docker with GPU runtime support
- Configures AMD ROCm or NVIDIA Container Toolkit
- Tests GPU accessibility with validation containers

### **Core Features**
- ✅ **Interactive Guided Installer**: Menu-driven setup with progress tracking
- ✅ **Modular Scripts**: Easy to add new automation tasks
- ✅ **Progress Tracking**: Resume setup where you left off
- ✅ **Auto-Detection**: Identifies completed steps and available hardware
- ✅ **Persistent GPU Mapping**: Uses PCI paths to ensure consistent GPU assignment across reboots
- ✅ **Unprivileged Containers**: Full GPU access without sacrificing container security
- ✅ **Docker Integration**: GPU-enabled Docker containers with proper runtime configuration

---

## 🚀 Quick Start

### Option 1: Guided Installation (Recommended)

The guided installer provides an interactive menu with progress tracking and auto-detection:

```bash
apt install -y curl git gpg htop iperf3 lshw mc s-tui unzip wget
cd /root
git clone https://github.com/jammsen/proxmox-setup-scripts.git
cd proxmox-setup-scripts
./guided-install.sh
```

**What you get:**
- 📋 Interactive menu showing all available scripts
- ✅ Green checkmarks for completed steps  
- 🎯 Smart defaults (just press Enter to continue)
- 🔄 Progress persistence (resume anytime)
- 📝 Detailed descriptions for each script

### Option 2: Manual Installation

### Option 2: Manual Installation

#### Step 1: Clone Repository on Proxmox Host

```bash
cd /root
git clone https://github.com/jammsen/proxmox-setup-scripts.git
cd proxmox-setup-scripts/host
```

#### Step 2: Install Essential Tools (Optional but Recommended)

```bash
./001 - install-tools.sh
```

Installs: `curl`, `git`, `gpg`, `htop`, `iperf3`, `lshw`, `mc`, `s-tui`, `unzip`, `wget`, plus power management tools.

#### Step 3: Install GPU Drivers on Host

**For AMD GPUs:**
```bash
./003 - install-amd-drivers.sh  # Install AMD ROCm 7.1.X drivers
./005 - verify-amd-drivers.sh   # Verify installation
```

**For NVIDIA GPUs:**
```bash
./004 - install-nvidia-drivers.sh  # Install NVIDIA CUDA and kernel drivers
./006 - verify-nvidia-drivers.sh   # Verify installation
```

**For AMD Ryzen AI 300 Series iGPU (Optional):**
```bash
./002 - setup-igpu-vram.sh  # Allocate 96GB VRAM for integrated GPU
```

#### Step 4: Setup Device Permissions

```bash
./007 - setup-udev-gpu-rules.sh
```

Creates udev rules for consistent GPU device permissions and persistent PCI-based paths.

#### Step 5: Create GPU-Enabled LXC Container

```bash
./031 - create-gpu-lxc.sh
```

This interactive script will:
1. Prompt you to select GPU type (AMD or NVIDIA)
2. Auto-detect available GPUs with their PCI addresses
3. Create an Ubuntu 24.04 LXC container with GPU passthrough
4. Configure persistent PCI-based device mapping
5. Mount the scripts directory at `/root/proxmox-setup-scripts` inside the container
6. Enable SSH access (default password: `testing`)
7. **Ask if you want to automatically install Docker and GPU drivers**

**Default answer is "Y"** - just press Enter to run the installation automatically!

#### Step 6: Install Docker + GPU Support (If Not Auto-Installed)

If you skipped the automatic installation, you can run it manually:

**Option A: Run from Proxmox Host**
```bash
# For NVIDIA:
pct exec <CONTAINER_ID> -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-nvidia-drivers-in-lxc.sh

# For AMD:
pct exec <CONTAINER_ID> -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-amd-drivers-in-lxc.sh
```

**Option B: SSH into Container**
```bash
ssh root@<CONTAINER_IP>  # Default password: testing
cd /root/proxmox-setup-scripts/lxc

# For NVIDIA:
./install-docker-and-nvidia-drivers-in-lxc.sh

# For AMD:
./install-docker-and-amd-drivers-in-lxc.sh
```

#### Step 7: Verify GPU Access

**NVIDIA:**
```bash
docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi
```

**AMD:**
```bash
docker run --rm --name rcom-smi --device /dev/kfd --device /dev/dri -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 --group-add video --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/rocm-terminal bash -c "rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname && rocminfo | grep -i -A5 'Agent [0-9]'"
```

---

## 📂 Repository Structure

```
proxmox-setup-scripts/
├── guided-install.sh          # Interactive guided installer (START HERE!)
│
├── host/                      # Scripts to run on Proxmox host
│   ├── 000 - list-gpus.sh                # List all GPUs and PCI paths
│   ├── 001 - install-tools.sh            # Install essential utilities
│   ├── 002 - setup-igpu-vram.sh          # Configure AMD Ryzen AI iGPU VRAM
│   ├── 003 - install-amd-drivers.sh      # Install AMD ROCm 7.1.X drivers
│   ├── 004 - install-nvidia-drivers.sh   # Install NVIDIA CUDA drivers
│   ├── 005 - verify-amd-drivers.sh       # Verify AMD driver installation
│   ├── 006 - verify-nvidia-drivers.sh    # Verify NVIDIA driver installation
│   ├── 007 - setup-udev-gpu-rules.sh     # Setup GPU device permissions
│   ├── 030 - create-amd-lxc.sh           # (Legacy) AMD-only LXC creation
│   ├── 031 - create-gpu-lxc.sh           # Create GPU-enabled LXC (AMD/NVIDIA)
│   └── 999 - upgrade-proxmox.sh          # Upgrade Proxmox to latest version
│
├── lxc/                       # Scripts to run inside LXC containers
│   ├── install-docker-and-nvidia-drivers-in-lxc.sh  # Docker + NVIDIA setup
│   └── install-docker-and-amd-drivers-in-lxc.sh     # Docker + AMD setup
│
├── includes/                  # Shared libraries
│   └── colors.sh             # Color definitions for terminal output
│
└── README.md                 # This file
```

---

## 🎮 Guided Installer Usage

The `guided-install.sh` script provides an interactive, menu-driven experience:

### Features

- **Progress Tracking**: Automatically saves your progress and shows ✅ for completed steps
- **Auto-Detection**: Identifies completed steps by checking installed packages and loaded kernel modules
- **Smart Defaults**: Press Enter to accept defaults, or type custom values
- **Flexible Execution**: Run individual scripts, ranges, or all steps at once
- **Always Ask Mode**: When running "all", you're prompted before each script (never auto-skipped)

### Menu Options

```
all          - Run all Host Setup scripts (000-029) with confirmations [DEFAULT]
<number>     - Run specific script by number (e.g., 004, 031)
<start-end>  - Run range of scripts (not implemented yet)
r/reset      - Clear progress tracking to start fresh
q/quit       - Exit installer
```

### Example: Running All Host Setup Scripts

```bash
./guided-install.sh
# Press Enter to accept default "all"
# You'll be prompted before each script:
#   - See script description and completion status
#   - Press Y to run, n to skip, q to return to menu
```

### Example: Running Specific Script

```bash
./guided-install.sh
# Type: 004
# Runs NVIDIA driver installation directly
```

### Example Session Output

```
========================================
Proxmox Setup Scripts - Guided Installer
========================================

Progress: 3 steps completed

=== Host Setup Scripts (000-029) ===

  [000]: (Optional) List all available GPUs and their PCI paths
✓ [001]: Install essential tools (curl, git, gpg, htop, iperf3, lshw, mc, s-tui, unzip, wget)
  [002]: Setup AMD Ryzen AI 300 / AI PRO 300 Processors iGPU 96GB VRAM allocation
  [003]: Install AMD ROCm 7.1.X drivers
✓ [004]: Install NVIDIA Cuda and Kernel drivers
✓ [005]: Verify AMD driver installation
  [006]: Verify NVIDIA driver installation
  [007]: Setup udev rules for GPU device permissions

=== LXC Container Scripts (030-099) ===

  [030]: Create AMD GPU-enabled LXC container (old-only-amd-version)
  [031]: Create GPU-enabled LXC container (AMD or NVIDIA or BOTH)

=== System Maintenance (999) ===

  [999]: Upgrade Proxmox to latest version (15 packages, 3 PVE-related)

Options:
  all          - Run all Host Setup scripts (000-029) with confirmations [DEFAULT]
  <number>     - Run specific script by number (e.g., 004, 031)
  r/reset      - Clear progress tracking
  q/quit       - Exit installer

Enter your choice [all]:
```

---

## 🔧 Script Details

### Host Scripts (Run on Proxmox)

| Script | Description | When to Use |
|--------|-------------|-------------|
| **000** | List all GPUs and PCI paths | Optional - useful for identifying GPU addresses before setup |
| **001** | Install essential tools | Recommended - installs utilities and power management |
| **002** | Setup AMD Ryzen AI iGPU VRAM | Only for AMD Ryzen AI 300/AI PRO 300 series with integrated GPU |
| **003** | Install AMD ROCm 7.1.X drivers | Required for AMD GPU support |
| **004** | Install NVIDIA CUDA drivers | Required for NVIDIA GPU support |
| **005** | Verify AMD driver installation | After installing AMD drivers |
| **006** | Verify NVIDIA driver installation | After installing NVIDIA drivers |
| **007** | Setup udev GPU rules | Required - ensures persistent device permissions |
| **030** | Create AMD-only LXC container | Legacy - use script 031 instead |
| **031** | Create GPU-enabled LXC container | **Main script** - supports AMD and NVIDIA |
| **999** | Upgrade Proxmox to latest version | Maintenance - keeps system up to date |

### LXC Scripts (Run Inside Containers)

| Script | Description | GPU Type |
|--------|-------------|----------|
| `install-docker-and-nvidia-drivers-in-lxc.sh` | Installs Docker, NVIDIA libraries, and NVIDIA Container Toolkit | NVIDIA |
| `install-docker-and-amd-drivers-in-lxc.sh` | Installs Docker and AMD ROCm libraries | AMD |

**Note:** These scripts are automatically available at `/root/proxmox-setup-scripts/lxc/` inside containers created with script 031.

---

## 🎯 Use Cases

### AI/ML Workloads
Run inference containers (Ollama, Stable Diffusion, etc.) with GPU acceleration in isolated LXC environments.

### Media Transcoding
Use hardware-accelerated transcoding in Plex, Jellyfin, or FFmpeg containers.

### Development Environments  
Create isolated GPU-enabled development containers for CUDA/ROCm programming.

### Multi-Tenant GPU Sharing
Assign different GPUs to different LXC containers for isolation and resource management.

---

## 💡 Key Concepts

### Persistent PCI-Based Mapping

Traditional GPU passthrough uses `/dev/dri/card0`, `/dev/dri/card1`, etc. These names can change between reboots depending on driver load order.

**This project uses PCI paths** like `/dev/dri/by-path/pci-0000:c7:00.0-card` which:
- ✅ Always point to the same physical GPU
- ✅ Survive reboots and driver updates
- ✅ Prevent GPU assignment conflicts
- ✅ Enable predictable multi-GPU setups

### Unprivileged Containers

All containers created by these scripts are **unprivileged** (safer than privileged containers) but still have full GPU access through:
- Proper cgroup device permissions
- Bind-mounted GPU devices
- AppArmor profile adjustments

### Docker GPU Integration

**NVIDIA:**  
Uses NVIDIA Container Toolkit with `--gpus all` flag. Requires special runtime configuration for LXC environments (cgroup management disabled).

**AMD:**  
Uses standard Docker device passthrough with `--device=/dev/kfd --device=/dev/dri`. No special toolkit required.

---

## 🐛 Troubleshooting

### GPU Not Detected in Container

```bash
# Check devices from host:
pct exec <CONTAINER_ID> -- ls -la /dev/nvidia*  # NVIDIA
pct exec <CONTAINER_ID> -- ls -la /dev/dri/     # Both
pct exec <CONTAINER_ID> -- ls -la /dev/kfd      # AMD
```

### Docker GPU Test Fails

**NVIDIA:**
```bash
# Check NVIDIA runtime config:
pct exec <CONTAINER_ID> -- cat /etc/nvidia-container-runtime/config.toml | grep no-cgroups
# Should show: no-cgroups = true

# Check Docker daemon:
pct exec <CONTAINER_ID> -- cat /etc/docker/daemon.json

# Restart Docker:
pct exec <CONTAINER_ID> -- systemctl restart docker
```

**AMD:**
```bash
# Verify group membership:
pct exec <CONTAINER_ID> -- groups root
# Should include: video render

# Check ROCm installation:
pct exec <CONTAINER_ID> -- rocminfo
# May fail in LXC (this is normal), but Docker should still work
```

### Driver Issues on Host

**Re-verify drivers:**
```bash
cd /root/proxmox-setup-scripts/host

# NVIDIA:
./006 - verify-nvidia-drivers.sh

# AMD:
./005 - verify-amd-drivers.sh
```

**Check kernel modules:**
```bash
lsmod | grep nvidia  # NVIDIA
lsmod | grep amdgpu  # AMD
```

---

## 🔄 Updating Scripts

All containers have the scripts directory mounted from the host at `/root/proxmox-setup-scripts`.

To update scripts in **all containers at once**:

```bash
cd /root/proxmox-setup-scripts
git pull
# All containers immediately see the updated scripts!
```

---

## 🙏 Credits & Resources

This project builds upon knowledge from the community:

- [Jocke's Blog: Plex GPU Transcoding in Docker on LXC on Proxmox](https://jocke.no/2025/04/20/plex-gpu-transcoding-in-docker-on-lxc-on-proxmox-v2/#comment-130670)
- Proxmox VE documentation
- NVIDIA Container Toolkit documentation  
- AMD ROCm documentation

---

## 📝 License

This project is provided as-is for educational and automation purposes. Use at your own risk.

---

## 🤝 Contributing

Found a bug or have a suggestion? Please open an issue or submit a pull request on GitHub!

**Repository:** [https://github.com/jammsen/proxmox-setup-scripts](https://github.com/jammsen/proxmox-setup-scripts)
