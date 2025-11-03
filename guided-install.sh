#!/usr/bin/env bash

# Guided installation script for Proxmox GPU setup
# This script provides an interactive menu to run setup scripts in order

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=includes/colors.sh
source "${SCRIPT_DIR}/includes/colors.sh"

# Progress file to track completed steps
PROGRESS_FILE="${SCRIPT_DIR}/.install-progress"

# Create progress file if it doesn't exist
touch "$PROGRESS_FILE"

# Function to check if a script has been completed
is_completed() {
    local script_num="$1"
    grep -q "^${script_num}$" "$PROGRESS_FILE" 2>/dev/null
}

# Function to mark script as completed
mark_completed() {
    local script_num="$1"
    if ! is_completed "$script_num"; then
        echo "$script_num" >> "$PROGRESS_FILE"
    fi
}

# Function to check if a script has indicators it was already run
auto_detect_completion() {
    local script_num="$1"
    
    case "$script_num" in
        "001")
            # Check if common tools are installed
            if command -v htop &> /dev/null && command -v nvtop &> /dev/null; then
                return 0
            fi
            ;;
        "002")
            # Check if AMD APU iGPU VRAM is configured
            if grep -q "amdgpu.gttsize=98304" /proc/cmdline 2>/dev/null; then
                return 0
            fi
            ;;
        "003")
            # Check if AMD drivers are loaded
            if lsmod | grep -q amdgpu; then
                return 0
            fi
            ;;
        "004")
            # Check if NVIDIA drivers are installed
            if command -v nvidia-smi &> /dev/null; then
                return 0
            fi
            ;;
        "005")
            # Check if AMD drivers are installed (same as 003)
            if lsmod | grep -q amdgpu; then
                return 0
            fi
            ;;
        "006")
            # Check if NVIDIA drivers are installed (same as 004)
            if command -v nvidia-smi &> /dev/null; then
                return 0
            fi
            ;;
        "007")
            # Check if udev rules exist
            if [ -f /etc/udev/rules.d/99-gpu-passthrough.rules ]; then
                return 0
            fi
            ;;
        "008")
            # Check if system has upgradable packages
            # If no upgradable packages, consider it "done"
            upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
            if [ "$upgradable" -eq 0 ]; then
                return 0
            fi
            return 1
            ;;
    esac
    return 1
}

# Function to display script with status
display_script() {
    local script_path="$1"
    local script_num
    local script_name
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    script_name=$(basename "$script_path" | sed 's/^[0-9]\+ - //' | sed 's/\.sh$//')
    
    # Get description based on script number
    local description=""
    case "$script_num" in
        "000") description="List all available GPUs and their PCI paths" ;;
        "001") description="Install essential tools (htop, nvtop, etc.)" ;;
        "002") description="Setup AMD APUs iGPU VRAM allocation" ;;
        "003") description="Install AMD GPU drivers" ;;
        "004") description="Install NVIDIA GPU drivers" ;;
        "005") description="Verify AMD driver installation" ;;
        "006") description="Verify NVIDIA driver installation" ;;
        "007") description="Setup udev rules for GPU device permissions" ;;
        "008") 
            # Get upgrade information
            local total_upgradable
            local pve_upgradable
            total_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" 2>/dev/null || echo "0")
            pve_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "pve\|proxmox" 2>/dev/null || echo "0")
            # Ensure we have valid numbers (remove newlines/spaces)
            total_upgradable=$(echo "$total_upgradable" | tr -d '\n ' 2>/dev/null || echo "0")
            pve_upgradable=$(echo "$pve_upgradable" | tr -d '\n ' 2>/dev/null || echo "0")
            # Sanitize to ensure integer
            total_upgradable=${total_upgradable//[^0-9]/}
            pve_upgradable=${pve_upgradable//[^0-9]/}
            total_upgradable=${total_upgradable:-0}
            pve_upgradable=${pve_upgradable:-0}
            if [ "$total_upgradable" -gt 0 ] 2>/dev/null; then
                description="Upgrade Proxmox to latest version (${total_upgradable} packages, ${pve_upgradable} PVE-related)"
            else
                description="Upgrade Proxmox to latest version (system up to date)"
            fi
            ;;
        "010") description="Create AMD GPU-enabled LXC container (deprecated)" ;;
        "011") description="Create GPU-enabled LXC container (AMD or NVIDIA)" ;;
        *) description="$script_name" ;;
    esac
    
    # Check completion status
    local status=""
    if is_completed "$script_num"; then
        status="${GREEN}✓${NC}"
    elif auto_detect_completion "$script_num"; then
        # Auto-detect and mark as completed
        mark_completed "$script_num"
        status="${GREEN}✓${NC}"
    else
        status=" "
    fi
    
    echo -e "${status} [${script_num}]: ${description}"
}

# Function to run a script
run_script() {
    local script_path="$1"
    local script_num
    local script_name
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    script_name=$(basename "$script_path")
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Running: $script_name${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    if bash "$script_path" < /dev/tty; then
        mark_completed "$script_num"
        echo ""
        echo -e "${GREEN}✓ Completed: $script_name${NC}"
        echo ""
        return 0
    else
        echo ""
        echo -e "${RED}✗ Failed: $script_name${NC}"
        echo ""
        return 1
    fi
}

# Function to get available scripts in a range
get_scripts() {
    local start="$1"
    local end="$2"
    local dir="$3"
    
    find "$dir" -maxdepth 1 -name "[0-9][0-9][0-9] - *.sh" -type f | \
        grep -E "/${start}[0-9] - |/0[${start}-${end}][0-9] - " | \
        sort
}

# Main menu
show_main_menu() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Proxmox Setup Scripts - Guided Installer${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Progress: $(wc -l < "$PROGRESS_FILE") steps completed${NC}"
    echo ""
    
    echo -e "${GREEN}=== Basic Host Setup (000-009) ===${NC}"
    echo ""
    
    # List host setup scripts
    while IFS= read -r script; do
        display_script "$script"
    done < <(get_scripts "0" "0" "${SCRIPT_DIR}/host")
    
    echo ""
    echo -e "${GREEN}=== LXC Container Setup (010-019) ===${NC}"
    echo ""
    
    # List LXC setup scripts
    while IFS= read -r script; do
        display_script "$script"
    done < <(get_scripts "1" "1" "${SCRIPT_DIR}/host")
    
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  all          - Run all Basic Host Setup scripts (with confirmations) [DEFAULT]"
    echo "  <number>     - Run specific script by number (e.g., 001, 004)"
    echo "  <start-end>  - Run range of scripts (e.g., 001-006)"
    echo "  reset        - Clear progress tracking"
    echo "  quit         - Exit installer"
    echo ""
}

# Function to prompt user before running script with detailed info
confirm_run_with_info() {
    local script_path="$1"
    local script_num
    local script_name
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    script_name=$(basename "$script_path" | sed 's/^[0-9]\+ - //' | sed 's/\.sh$//')
    
    # Get description
    local description=""
    case "$script_num" in
        "000") description="List all available GPUs and their PCI paths" ;;
        "001") description="Install essential tools (htop, nvtop, etc.)" ;;
        "002") description="Setup AMD APUs iGPU VRAM allocation" ;;
        "003") description="Install AMD GPU drivers" ;;
        "004") description="Install NVIDIA GPU drivers" ;;
        "005") description="Verify AMD driver installation" ;;
        "006") description="Verify NVIDIA driver installation" ;;
        "007") description="Setup udev rules for GPU device permissions" ;;
        "008") 
            # Get upgrade information
            local total_upgradable
            local pve_upgradable
            total_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" 2>/dev/null || echo "0")
            pve_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "pve\|proxmox" 2>/dev/null || echo "0")
            # Ensure we have valid numbers (remove newlines/spaces)
            total_upgradable=$(echo "$total_upgradable" | tr -d '\n ' 2>/dev/null || echo "0")
            pve_upgradable=$(echo "$pve_upgradable" | tr -d '\n ' 2>/dev/null || echo "0")
            # Sanitize to ensure integer
            total_upgradable=${total_upgradable//[^0-9]/}
            pve_upgradable=${pve_upgradable//[^0-9]/}
            total_upgradable=${total_upgradable:-0}
            pve_upgradable=${pve_upgradable:-0}
            if [ "$total_upgradable" -gt 0 ] 2>/dev/null; then
                description="Upgrade Proxmox to latest version (${total_upgradable} packages, ${pve_upgradable} PVE-related)"
            else
                description="Upgrade Proxmox to latest version (system up to date)"
            fi
            ;;
        "010") description="Create AMD GPU-enabled LXC container (deprecated)" ;;
        "011") description="Create GPU-enabled LXC container (AMD or NVIDIA)" ;;
        *) description="$script_name" ;;
    esac
    
    # Check if already completed
    local status_msg=""
    if is_completed "$script_num" || auto_detect_completion "$script_num"; then
        status_msg=" ${GREEN}(already completed ✓)${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}──────────────────────────────────────${NC}"
    echo -e "${GREEN}[$script_num] $script_name${NC}${status_msg}"
    echo -e "${YELLOW}Description:${NC} $description"
    echo -e "${GREEN}──────────────────────────────────────${NC}"
    read -r -p "Run this script? [Y/n/q]: " choice < /dev/tty
    choice=${choice:-Y}
    echo ""  # Add blank line after input
    
    case "$choice" in
        [Qq]|[Qq][Uu][Ii][Tt])
            return 2  # Special return code for quit
            ;;
        [Yy]|[Yy][Ee][Ss])
            return 0  # Run the script
            ;;
        *)
            return 1  # Skip the script
            ;;
    esac
}

# Function to prompt user before running script (simple version)
confirm_run() {
    local script_path="$1"
    local script_name
    script_name=$(basename "$script_path")
    
    read -r -p "Run '$script_name'? [Y/n]: " choice
    choice=${choice:-Y}
    [[ "$choice" =~ ^[Yy]$ ]]
}

# Main loop
while true; do
    show_main_menu
    
    read -r -p "Enter your choice [all]: " choice
    choice=${choice:-all}  # Default to "all"
    choice=${choice,,}  # Convert to lowercase
    
    case "$choice" in
        "all")
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}Running all Basic Host Setup scripts...${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${YELLOW}You will be asked before each script runs.${NC}"
            echo -e "${YELLOW}Press 'y' to run, 'n' to skip, or 'q' to return to main menu.${NC}"
            echo ""
            
            quit_requested=false
            while IFS= read -r script; do
                script_num=$(basename "$script" | grep -oP '^\d+')
                
                # Always ask user with detailed information (never auto-skip in "all" mode)
                confirm_run_with_info "$script"
                result=$?
                
                if [ $result -eq 2 ]; then
                    # User chose to quit back to main menu
                    echo -e "${YELLOW}Returning to main menu...${NC}"
                    quit_requested=true
                    break
                elif [ $result -eq 0 ]; then
                    # User chose to run the script
                    if ! run_script "$script"; then
                        echo ""
                        read -r -p "Script failed. Continue with next script? [y/N]: " continue_choice < /dev/tty
                        continue_choice=${continue_choice:-N}
                        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                            break
                        fi
                    fi
                    # Small delay to ensure clean terminal state
                    sleep 0.5
                else
                    # User chose to skip
                    echo -e "${YELLOW}Skipped by user: $(basename "$script")${NC}"
                    # Small delay to ensure clean terminal state
                    sleep 0.5
                fi
            done < <(get_scripts "0" "0" "${SCRIPT_DIR}/host")
            
            if [ "$quit_requested" = false ]; then
                echo ""
                echo -e "${GREEN}========================================${NC}"
                echo -e "${GREEN}Basic Host Setup process completed!${NC}"
                echo -e "${GREEN}========================================${NC}"
                read -r -p "Press Enter to continue..." < /dev/tty
            fi
            ;;
            
        [0-9][0-9][0-9])
            # Run specific script
            script_path=$(find "${SCRIPT_DIR}/host" -maxdepth 1 -name "${choice} - *.sh" -type f)
            
            if [ -z "$script_path" ]; then
                echo -e "${RED}Script $choice not found!${NC}"
                read -r -p "Press Enter to continue..."
            else
                run_script "$script_path"
                read -r -p "Press Enter to continue..."
            fi
            ;;
            
        [0-9][0-9][0-9]-[0-9][0-9][0-9])
            # Run range of scripts
            start=$(echo "$choice" | cut -d'-' -f1)
            end=$(echo "$choice" | cut -d'-' -f2)
            
            echo ""
            echo -e "${GREEN}Running scripts $start to $end...${NC}"
            echo ""
            
            for num in $(seq "$start" "$end"); do
                padded=$(printf "%03d" "$num")
                script_path=$(find "${SCRIPT_DIR}/host" -maxdepth 1 -name "${padded} - *.sh" -type f)
                
                if [ -n "$script_path" ]; then
                    # Skip if already completed
                    if is_completed "$padded" || auto_detect_completion "$padded"; then
                        echo -e "${YELLOW}Skipping $padded (already completed)${NC}"
                        continue
                    fi
                    
                    if confirm_run "$script_path"; then
                        if ! run_script "$script_path"; then
                            read -r -p "Script failed. Continue with next script? [y/N]: " continue_choice
                            continue_choice=${continue_choice:-N}
                            if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                                break
                            fi
                        fi
                    else
                        echo -e "${YELLOW}Skipped by user${NC}"
                    fi
                fi
            done
            
            echo ""
            read -r -p "Press Enter to continue..."
            ;;
            
        "reset")
            read -r -p "Clear all progress tracking? [y/N]: " confirm
            confirm=${confirm:-N}
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                true > "$PROGRESS_FILE"
                echo -e "${GREEN}Progress cleared!${NC}"
            fi
            read -r -p "Press Enter to continue..."
            ;;
            
        "quit"|"q"|"exit")
            echo ""
            echo -e "${GREEN}Thank you for using Proxmox Setup Scripts${NC}"
            echo ""
            exit 0
            ;;
            
        *)
            echo -e "${RED}Invalid choice!${NC}"
            read -r -p "Press Enter to continue..."
            ;;
    esac
done
