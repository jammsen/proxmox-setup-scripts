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
apt install -y git
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

#### Step 4: Device Permissions (retired)

Script 007 used to install udev rules for the GPU device nodes on the host. This is no longer
needed: 032 uses Proxmox's built-in device passthrough and 031 runs privileged. Running 007 now
only prints a notice and offers to remove the old rules file if it is still present.

#### Step 5: Create GPU-Enabled LXC Container

```bash
./031 - create-gpu-lxc.sh
```

> **Note:** 031 creates a *privileged* container. That makes GPU access simple and is fine
> for a trusted home lab, but the container is less isolated or secured from the Proxmox host. If you want
> better isolation, use script 032 instead, which creates an *unprivileged* container with the same
> wizard.

This interactive script will:
1. Prompt you to select GPU type (AMD or NVIDIA)
2. Auto-detect available GPUs with their PCI addresses
3. Ask for hostname/IP, container resources (cores, RAM, swap), storage and disk size (shows free space)
4. Optionally mount a shared model directory from the host (default `/opt/llm-models`, created with `1777`
   so several containers can use the same models and the container disk stays small)
5. Create an Ubuntu 26.04 LXC container with GPU passthrough (NVIDIA: CUDA repo; AMD: ROCm 7.14+ from repo.amd.com, per-GPU packages)
6. Mount the scripts directory at `/root/proxmox-setup-scripts` inside the container
7. Enable SSH access (default password: `testing`)
8. **Ask if you want to automatically install Docker and GPU drivers**

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
docker run --rm --device /dev/kfd --device /dev/dri --group-add video --group-add "$(getent group render | cut -d: -f3)" --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/dev-ubuntu-24.04:7.2.4 bash -c "rocm-smi && rocminfo | grep -i -A5 'Agent [0-9]' && amd-smi list && amd-smi metric --mem-usage"
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
│   ├── 007 - setup-udev-gpu-rules.sh     # (Retired) notice + optional cleanup of old udev rules
│   ├── 030 - create-amd-lxc.sh           # (Retired) prints a notice pointing to 031/032
│   ├── 031 - create-gpu-lxc.sh           # Create GPU-enabled privileged LXC (AMD/NVIDIA)
│   ├── 032 - create-gpu-lxc-unprivileged.sh # Create GPU-enabled unprivileged LXC (AMD/NVIDIA)
│   └── 999 - upgrade-proxmox.sh          # Upgrade Proxmox to latest version
│
├── lxc/                       # Scripts to run inside LXC containers
│   ├── install-docker-and-nvidia-drivers-in-lxc.sh  # Docker + NVIDIA setup
│   └── install-docker-and-amd-drivers-in-lxc.sh     # Docker + AMD setup
│
├── includes/                  # Shared libraries
│   ├── colors.sh             # Color definitions for terminal output
│   └── gpu-verify.sh         # Shared in-container GPU device check (031/032)
│
├── docker-compose-testing-examples/   # Ready-to-run compose files for inside the containers
│   ├── amd/
│   │   ├── ollama/           # Ollama on ROCm (several image variants for APUs)
│   │   └── vllm/             # vLLM on ROCm (RDNA / Ryzen AI, OpenAI-compatible API)
│   └── nvidia/
│       ├── ollama/           # Ollama on CUDA
│       └── ollama-multi-gpu/ # Ollama across several NVIDIA GPUs
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
  [007]: (Retired) udev rules for GPU device permissions - no longer needed by 031/032

=== LXC Container Scripts (030-099) ===

  [030]: (Retired) Old AMD-only container script - use 031 (privileged) or 032 (unprivileged) instead
  [031]: Create GPU-enabled LXC container (privileged, AMD or NVIDIA)
  [032]: Create GPU-enabled LXC container (unprivileged, AMD or NVIDIA)

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
| **007** | Retired | Old udev rules for GPU device permissions; not needed by 031/032. Prints a notice, offers to remove the old rules file |
| **030** | Retired | Was the first AMD-only container script; kept as a notice so the number stays known. Use 031 or 032 |
| **031** | Create GPU-enabled LXC container (privileged) | AMD and NVIDIA. Easy setup; container is less isolated or secured from the host |
| **032** | Create GPU-enabled LXC container (unprivileged) | **Recommended** - AMD and NVIDIA, better isolated from the host (Proxmox device passthrough, Needs PVE 8.1+) |
| **999** | Upgrade Proxmox to latest version | Maintenance - keeps system up to date |

### LXC Scripts (Run Inside Containers)

| Script | Description | GPU Type |
|--------|-------------|----------|
| `install-docker-and-nvidia-drivers-in-lxc.sh` | Installs Docker, NVIDIA libraries, and NVIDIA Container Toolkit | NVIDIA |
| `install-docker-and-amd-drivers-in-lxc.sh` | Installs Docker and the AMD ROCm runtime (ROCm 7.14+ from repo.amd.com, per-GPU packages; runtime only by default, full libraries optional) | AMD |

**Note:** These scripts are automatically available at `/root/proxmox-setup-scripts/lxc/` inside containers created with script 031/032.

### Docker Compose Examples (Run Inside Containers)

`docker-compose-testing-examples/` holds ready-to-run compose files. They all use the shared model directory
`/opt/llm-models` that 031/032 can mount from the host, so models are downloaded once.

| Directory | What it runs | GPU Type |
|-----------|--------------|----------|
| `nvidia/ollama/` | Ollama (`ollama/ollama`) on CUDA | NVIDIA |
| `nvidia/ollama-multi-gpu/` | Ollama spread over several NVIDIA GPUs | NVIDIA |
| `amd/ollama/` | Ollama on ROCm, incl. APU-optimised image variants | AMD |
| `amd/vllm/` | vLLM (AMD's `rocm/vllm` RDNA image, OpenAI-compatible API on port 8000). Model and memory settings are plain values at the top of the file - default is Qwen3 4B Thinking (Q4_K_M GGUF, ~2.5 GB) which fits any GPU | AMD |

The scripts directory is mounted read-only inside the containers, so copy an example somewhere writable
before editing it:

```bash
cp -r /root/proxmox-setup-scripts/docker-compose-testing-examples/amd/vllm /opt/vllm && cd /opt/vllm
nano compose.yml              # pick model option 1/2, adjust memory settings if needed
RENDER_GID=$(getent group render | cut -d: -f3) bash -c "docker compose up -d && docker compose logs -f"
                              # first start downloads the image and the model (into /opt/llm-models/huggingface)
curl http://localhost:8000/v1/models
```

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
