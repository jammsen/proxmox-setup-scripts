#!/usr/bin/env bash

# Guided installation script for Proxmox GPU setup
# This script provides an interactive menu to run setup scripts in order
# Scripts are discovered automatically by reading metadata headers

# Note: NOT using set -e because we need to handle return codes from functions
# set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=includes/colors.sh
source "${SCRIPT_DIR}/includes/colors.sh"

# Progress file to track completed steps
PROGRESS_FILE="${SCRIPT_DIR}/.install-progress"

# Create progress file if it doesn't exist
touch "$PROGRESS_FILE"

# Associative arrays to store script metadata
declare -A SCRIPT_DESCRIPTIONS
declare -A SCRIPT_DETECT_CMDS
declare -a SCRIPT_NUMS

# Function to extract metadata from script header
extract_script_metadata() {
    local script_path="$1"
    local script_num
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    
    # Read metadata from script header
    local desc detect_cmd
    desc=$(grep '^# SCRIPT_DESC:' "$script_path" 2>/dev/null | sed 's/^# SCRIPT_DESC: //')
    detect_cmd=$(grep '^# SCRIPT_DETECT:' "$script_path" 2>/dev/null | sed 's/^# SCRIPT_DETECT: //')
    
    # Store in arrays
    SCRIPT_NUMS+=("$script_num")
    SCRIPT_DESCRIPTIONS["$script_num"]="$desc"
    SCRIPT_DETECT_CMDS["$script_num"]="$detect_cmd"
}

# Function to discover and load all scripts
discover_scripts() {
    # Find all scripts in host directory
    while IFS= read -r script_path; do
        extract_script_metadata "$script_path"
    done < <(find "${SCRIPT_DIR}/host" -maxdepth 1 -name "[0-9][0-9][0-9] - *.sh" -type f | sort)
    
    # Sort script numbers (suppress shellcheck warning - we need numeric sort)
    # shellcheck disable=SC2207
    IFS=$'\n' SCRIPT_NUMS=($(printf '%s\n' "${SCRIPT_NUMS[@]}" | sort -n))
    unset IFS
}

# Initialize: discover all scripts
discover_scripts

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
    local detect_cmd="${SCRIPT_DETECT_CMDS[$script_num]}"
    
    # If no detection command, return false
    if [ -z "$detect_cmd" ]; then
        return 1
    fi
    
    # Execute the detection command
    if eval "$detect_cmd" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get script description by number
get_script_description() {
    local script_num="$1"
    local script_name="$2"
    
    # Try to get from metadata first
    local desc="${SCRIPT_DESCRIPTIONS[$script_num]}"
    
    # For script 999 (upgrade), add dynamic package count if description contains "Upgrade"
    if [[ "$script_num" == "999" && "$desc" =~ "Upgrade" ]]; then
        local total_upgradable pve_upgradable
        total_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" 2>/dev/null || echo "0")
        pve_upgradable=$(apt list --upgradable 2>/dev/null | grep -c "pve\|proxmox" 2>/dev/null || echo "0")
        # Sanitize to ensure integer
        total_upgradable=${total_upgradable//[^0-9]/}
        pve_upgradable=${pve_upgradable//[^0-9]/}
        total_upgradable=${total_upgradable:-0}
        pve_upgradable=${pve_upgradable:-0}
        if [ "$total_upgradable" -gt 0 ] 2>/dev/null; then
            echo "$desc (${total_upgradable} packages, ${pve_upgradable} PVE-related)"
        else
            echo "$desc (system up to date)"
        fi
    elif [ -n "$desc" ]; then
        echo "$desc"
    else
        # Fallback to script name
        echo "$script_name"
    fi
}

# Function to display script with status
display_script() {
    local script_path="$1"
    local script_num
    local script_name
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    script_name=$(basename "$script_path" | sed 's/^[0-9]\+ - //' | sed 's/\.sh$//')
    
    # Get description using centralized function
    local description
    description=$(get_script_description "$script_num" "$script_name")
    
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

# Function to get available scripts in a numeric range
get_scripts_in_range() {
    local start="$1"
    local end="$2"
    
    # Filter scripts by numeric range
    for num in "${SCRIPT_NUMS[@]}"; do
        if [ "$num" -ge "$start" ] && [ "$num" -le "$end" ]; then
            # Find the actual script file
            find "${SCRIPT_DIR}/host" -maxdepth 1 -name "${num} - *.sh" -type f
        fi
    done | sort
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
    
    echo -e "${GREEN}=== Host Setup Scripts (000-029) ===${NC}"
    echo ""
    
    # List host setup scripts (000-029)
    while IFS= read -r script; do
        display_script "$script"
    done < <(get_scripts_in_range 0 29)
    
    echo ""
    echo -e "${GREEN}=== LXC Container Scripts (030-099) ===${NC}"
    echo ""
    
    # List LXC setup scripts (030-099)
    while IFS= read -r script; do
        display_script "$script"
    done < <(get_scripts_in_range 30 99)
    
    echo ""
    echo -e "${GREEN}=== System Maintenance (999) ===${NC}"
    echo ""
    
    # List system maintenance scripts (999)
    while IFS= read -r script; do
        display_script "$script"
    done < <(get_scripts_in_range 999 999)
    
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  all          - Run all Host Setup scripts (000-029) with confirmations [DEFAULT]"
    echo "  <number>     - Run specific script by number (e.g., 001, 031, 999)"
    echo "  r/reset      - Clear progress tracking"
    echo "  q/quit       - Exit installer"
    echo ""
}

# Function to prompt user before running script with detailed info
confirm_run_with_info() {
    local script_path="$1"
    local script_num
    local script_name
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    script_name=$(basename "$script_path" | sed 's/^[0-9]\+ - //' | sed 's/\.sh$//')
    
    # Get description using centralized function
    local description
    description=$(get_script_description "$script_num" "$script_name")
    
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
            echo -e "${GREEN}Running all Host Setup scripts (000-029)...${NC}"
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
            done < <(get_scripts_in_range 0 29)
            
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
            
        "r"|"reset")
            read -r -p "Clear all progress tracking? [Y/n]: " confirm
            confirm=${confirm:-Y}
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                true > "$PROGRESS_FILE"
                echo -e "${GREEN}Progress cleared!${NC}"
            fi
            read -r -p "Press Enter to continue..."
            ;;
            
        "q"|"quit")
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
