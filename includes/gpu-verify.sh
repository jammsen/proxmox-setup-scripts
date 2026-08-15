#!/usr/bin/env bash
# Shared helper: verify GPU devices inside an LXC container (used by 031 and 032)
# Requires colors.sh to be sourced first.

# Verify GPU devices inside the container and evaluate the result for the user.
# Handles DRI (Intel/AMD/NVIDIA), /dev/kfd (AMD ROCm) and /dev/nvidia* (NVIDIA CUDA).
verify_gpu_in_container() {
    local ctid="$1" gpu_type="$2"
    local ok=0 fail=0 warn=0

    check_dev() {
        # $1 = path in container, $2 = required (yes/no), $3 = description
        local out
        # run through sh so globs like /dev/dri/card* expand inside the container
        if out=$(pct exec "$ctid" -- sh -c "ls -la $1 2>/dev/null") && [ -n "$out" ]; then
            echo -e "  ${GREEN}✓${NC} $1 - $3"
            echo "$out" | sed 's/^/      /'
            ok=$((ok+1))
        elif [ "$2" == "yes" ]; then
            echo -e "  ${RED}✗${NC} $1 missing - $3 (required)"
            fail=$((fail+1))
        else
            echo -e "  ${YELLOW}-${NC} $1 missing - $3 (optional)"
            warn=$((warn+1))
        fi
    }

    echo ""
    echo -e "${YELLOW}>>> Verifying GPU devices inside container $ctid...${NC}"
    echo ""
    if [ "$gpu_type" == "1" ]; then
        # AMD: ROCm needs DRI card+render and KFD
        check_dev "/dev/dri/card*"     yes "DRI card node (display/modesetting)"
        check_dev "/dev/dri/renderD*"  yes "DRI render node (ROCm/OpenCL/VAAPI compute)"
        check_dev /dev/kfd            yes "AMD Kernel Fusion Driver (ROCm compute)"
    else
        # NVIDIA: CUDA needs nvidia0/nvidiactl/uvm; DRI only if nvidia_drm is loaded on host
        check_dev /dev/nvidia0        yes "NVIDIA GPU device (CUDA)"
        check_dev /dev/nvidiactl      yes "NVIDIA control device (CUDA)"
        check_dev /dev/nvidia-uvm     yes "NVIDIA unified memory (CUDA)"
        check_dev /dev/nvidia-uvm-tools no  "NVIDIA UVM tools"
        check_dev /dev/nvidia-modeset no  "NVIDIA modesetting (needs nvidia_modeset on host, not needed for CUDA)"
        check_dev "/dev/nvidia-caps/*" no  "NVIDIA capability devices (MIG/monitoring)"
        check_dev "/dev/dri/card*"     no  "DRI card node (needs nvidia_drm on host, not needed for CUDA)"
        check_dev "/dev/dri/renderD*"  no  "DRI render node (needs nvidia_drm on host, not needed for CUDA)"
    fi

    echo ""
    if [ "$fail" -eq 0 ]; then
        echo -e "${GREEN}Result: All required GPU devices are present ($ok found, $warn optional missing).${NC}"
        [ "$warn" -gt 0 ] && echo -e "${YELLOW}Optional devices missing are fine for compute (CUDA/ROCm) workloads.${NC}"
    else
        echo -e "${RED}Result: $fail required GPU device(s) missing - GPU passthrough is NOT working.${NC}"
        echo -e "${RED}Check host devices (ls -la /dev/dri /dev/kfd /dev/nvidia*) and /etc/pve/lxc/${ctid}.conf${NC}"
    fi
    echo ""
}
