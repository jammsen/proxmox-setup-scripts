# GPU Mapping Solution for Proxmox LXC Containers

## The Problem

When you have multiple GPUs in a Proxmox system, the kernel may assign device names inconsistently between boots:
- Sometimes GPU1 gets `card0` + `renderD128`
- Sometimes GPU1 gets `card1` + `renderD128` (mismatched!)
- Sometimes GPU1 gets `card1` + `renderD129` (correct pair)

This happens because device enumeration order can vary, leading to broken GPU passthrough in LXC containers.

## The Solution: Persistent PCI Path-Based Mapping

Instead of using variable device names like `/dev/dri/card0` or `/dev/dri/renderD128`, use **persistent PCI path-based device names** from `/dev/dri/by-path/`.

These paths are based on the GPU's physical PCI slot and **never change**.

### Example

Instead of:
```bash
lxc.mount.entry: /dev/dri/card1 dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
```

Use:
```bash
lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-render dev/dri/renderD128 none bind,optional,create=file
```

## Implementation Steps

### 1. Identify Your GPU PCI Addresses

On the Proxmox host, run the GPU listing script:
```bash
bash "000 - list-gpus.sh"
```

Or manually with:
```bash
ls -la /dev/dri/by-path/
lspci -nn -D | grep -E "VGA|3D|Display"
```

Example output from the list-gpus script:
```
=== All GPUs Detected (from lspci) ===
[AMD] 0000:c8:00.0 - Advanced Micro Devices, Inc. [AMD/ATI] Navi 32 [Radeon RX 7700 XT]
[NVIDIA] 0000:c7:00.0 - NVIDIA Corporation AD107GL [RTX 2000 Ada Generation]

=== DRI Device Mappings (Persistent Paths) ===
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PCI Address: 0000:c7:00.0 [NVIDIA]
Description: NVIDIA Corporation AD107GL [RTX 2000 Ada Generation]
Current Mapping:
  Card:   card0
  Render: renderD128

Use in LXC config:
  lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-card dev/dri/card0 none bind,optional,create=file
  lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-render dev/dri/renderD128 none bind,optional,create=file

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PCI Address: 0000:c8:00.0 [AMD]
Description: Advanced Micro Devices, Inc. [AMD/ATI] Navi 32 [Radeon RX 7700 XT]
Current Mapping:
  Card:   card1
  Render: renderD129

Use in LXC config:
  lxc.mount.entry: /dev/dri/by-path/pci-0000:c8:00.0-card dev/dri/card0 none bind,optional,create=file
  lxc.mount.entry: /dev/dri/by-path/pci-0000:c8:00.0-render dev/dri/renderD128 none bind,optional,create=file
```

This shows:
- **NVIDIA GPU** at PCI address `0000:c7:00.0` (currently card0 + renderD128)
- **AMD GPU** at PCI address `0000:c8:00.0` (currently card1 + renderD129)

### 2. Use the Scripts Provided

#### For New Containers
Use `008 - create-gpu-lxc.sh`:
```bash
bash "008 - create-gpu-lxc.sh"
```
This interactive script will:
- Detect available GPUs
- Ask for the PCI address
- Create the container with proper persistent mapping

#### For Existing Containers
Use `999 - fix-existing-lxc-gpu-mapping.sh`:
```bash
bash "999 - fix-existing-lxc-gpu-mapping.sh"
```
This will:
- Backup your current configuration
- Remove old card0/card1/renderD* mappings
- Add new persistent PCI path-based mappings
- Restart the container

### 3. Verify the Configuration

After setup, check your `/etc/pve/lxc/XXX.conf`:

#### AMD GPU Example
```conf
# Allow DRI and KFD devices
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 235:* rwm

# Mount using persistent PCI paths
lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-0000:c7:00.0-render dev/dri/renderD128 none bind,optional,create=file
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file

# Permissions
lxc.apparmor.profile: unconfined
lxc.cap.drop:
```

#### NVIDIA GPU Example
```conf
# Allow NVIDIA and DRI devices
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.cgroup2.devices.allow: c 508:* rwm

# Mount NVIDIA devices
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file

# Mount DRI devices using persistent PCI paths
lxc.mount.entry: /dev/dri/by-path/pci-0000:01:00.0-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-0000:01:00.0-render dev/dri/renderD128 none bind,optional,create=file

# Permissions
lxc.apparmor.profile: unconfined
lxc.cap.drop:
```

### 4. Test Inside Container

After starting the container:
```bash
pct exec CONTAINER_ID -- ls -la /dev/dri/
```

You should see:
```
crw-rw---- 1 root video 226, X Nov  2 10:00 card0
crw-rw---- 1 root video 226, Y Nov  2 10:00 renderD128
```

For AMD GPUs, also check:
```bash
pct exec CONTAINER_ID -- ls -la /dev/kfd
```

## Why This Works

1. **PCI addresses are hardware-based** - They correspond to physical PCIe slots
2. **Kernel creates by-path symlinks** - These point to the actual device nodes
3. **Symlinks resolve at mount time** - The correct card/render pair is always matched
4. **Inside the container** - Devices appear as card0/renderD128 consistently

## Benefits

✅ **Consistent mapping** - Same GPU always maps to same devices  
✅ **Survives reboots** - PCI addresses don't change  
✅ **Multiple GPUs** - Each GPU gets correct card+render pair  
✅ **Easy maintenance** - Clear which physical GPU is which  
✅ **No manual intervention** - Set once, works forever  

## Troubleshooting

### Issue: "by-path does not exist"
Check if GPU drivers are loaded:
```bash
lsmod | grep -E "amdgpu|nvidia"
ls -la /dev/dri/
```

### Issue: "Permission denied inside container"
Check cgroup permissions in LXC config:
```bash
grep cgroup /etc/pve/lxc/XXX.conf
```
Should have: `lxc.cgroup2.devices.allow: c 226:* rwm`

### Issue: "Container won't start"
Check the logs:
```bash
journalctl -u pve-container@XXX -f
```

Review the configuration:
```bash
cat /etc/pve/lxc/XXX.conf
```

## Additional Resources

- **Script 000**: List all GPUs and their PCI addresses (run this first!)
- **Script 006**: Setup udev rules for GPU permissions
- **Script 008**: Create new GPU-enabled LXC containers (improved with vendor detection)
- **Script 999**: Fix existing containers to use persistent paths

## Quick Reference Commands

```bash
# List all GPUs with clear vendor identification
bash "000 - list-gpus.sh"

# Find GPU PCI addresses
ls -la /dev/dri/by-path/

# List PCI devices with full addresses
lspci -nn -D | grep -E "VGA|3D|Display"

# Check container config
cat /etc/pve/lxc/XXX.conf

# Verify GPU inside container
pct exec XXX -- ls -la /dev/dri/
pct exec XXX -- ls -la /dev/kfd  # AMD only

# Test GPU in container (AMD)
pct exec XXX -- rocm-smi  # After installing ROCm

# Test GPU in container (NVIDIA)
pct exec XXX -- nvidia-smi  # After installing drivers
```
