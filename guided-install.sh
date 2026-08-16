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

# --- Repository update support -------------------------------------------------------------
# The installer can pull the latest scripts from git on request (menu option "u"). It never
# updates on its own: at start it only *checks* once (a quick, read-only fetch) whether the
# upstream branch has new commits, so the menu can show a hint. Offline or non-git checkouts
# simply get no hint.
REPO_IS_GIT=0
REPO_VERSION=""
UPDATE_AVAILABLE=0
UPDATE_COUNT=0

repo_check_update() {
    UPDATE_AVAILABLE=0
    UPDATE_COUNT=0
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        REPO_IS_GIT=0
        return
    fi
    REPO_IS_GIT=1
    REPO_VERSION=$(git -C "$SCRIPT_DIR" log -1 --format='%h (%cs)' 2>/dev/null)
    # Only a fetch (read-only, nothing is changed locally); give up quietly after a few seconds
    if ! timeout 8 git -C "$SCRIPT_DIR" fetch --quiet 2>/dev/null; then
        return
    fi
    local behind
    behind=$(git -C "$SCRIPT_DIR" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    if [ "${behind:-0}" -gt 0 ]; then
        UPDATE_AVAILABLE=1
        UPDATE_COUNT=$behind
    fi
}

repo_update() {
    echo ""
    if [ "$REPO_IS_GIT" != "1" ]; then
        echo -e "${YELLOW}This copy of the scripts is not a git checkout, so it cannot update itself.${NC}"
        echo "Download the latest version again or clone the repository with git."
        return 1
    fi
    local before
    before=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    echo -e "${GREEN}>>> Pulling the latest scripts (git pull --ff-only)...${NC}"
    if ! git -C "$SCRIPT_DIR" pull --ff-only; then
        echo ""
        echo -e "${YELLOW}The update could not be applied automatically.${NC}"
        echo "Usually this means there are local changes in ${SCRIPT_DIR} or the history diverged."
        echo "Have a look with:  git -C \"${SCRIPT_DIR}\" status"
        echo "If git complains about 'dubious ownership', allow the directory with:"
        echo "  git config --global --add safe.directory \"${SCRIPT_DIR}\""
        return 1
    fi
    local after
    after=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if [ "$before" == "$after" ]; then
        echo -e "${GREEN}Already up to date.${NC}"
        UPDATE_AVAILABLE=0
        return 0
    fi
    echo ""
    echo -e "${GREEN}Updated. Changes:${NC}"
    git -C "$SCRIPT_DIR" log --oneline "${before}..${after}" | sed 's/^/  /'
    echo ""
    echo "Containers that mount this directory (/root/proxmox-setup-scripts) see the new scripts as well."
    echo ""
    read -r -p "Press Enter to restart the installer with the new version..."
    cleanup_on_exit   # exec replaces this process without running the EXIT trap, so clean up by hand
    exec bash "$0" "$@"
}

repo_check_update

# --- Optional background update check ------------------------------------------------------
# Off by default. When enabled (menu option "a"), a helper process runs the same read-only
# check every AUTO_CHECK_INTERVAL seconds and, if new commits show up while the menu is on
# screen, repaints the "u/update" line in place without touching what the user is typing.
# It never pulls anything. State lives in small files next to the progress file.
SETTINGS_FILE="${SCRIPT_DIR}/.install-settings"
AUTO_CHECK_INTERVAL=60
AUTO_CHECK_STATE="${SCRIPT_DIR}/.install-update-state"   # written by the poller: "<count>"
AUTO_CHECK_MENU_FLAG="${SCRIPT_DIR}/.install-menu-shown" # exists only while the menu prompt is on screen
AUTO_CHECK_PID=""
AUTO_CHECK=0
if [ -f "$SETTINGS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$SETTINGS_FILE"
fi

# The poller: fetch, compare, and repaint the menu line if something changed
auto_check_loop() {
    local last=0 count sleep_pid=""
    # when we are told to stop, take the sleeping child with us so nothing lingers
    trap '[ -n "$sleep_pid" ] && kill "$sleep_pid" 2>/dev/null; exit 0' TERM INT HUP
    while true; do
        sleep "$AUTO_CHECK_INTERVAL" & sleep_pid=$!
        wait "$sleep_pid" 2>/dev/null
        sleep_pid=""
        # parent gone (killed, crashed)? then stop too - no orphan
        kill -0 "$1" 2>/dev/null || exit 0
        timeout 20 git -C "$SCRIPT_DIR" fetch --quiet 2>/dev/null || continue
        count=$(git -C "$SCRIPT_DIR" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
        count=${count:-0}
        echo "$count" > "$AUTO_CHECK_STATE"
        # repaint only on change and only while the menu prompt is visible
        if [ "$count" -gt 0 ] && [ "$count" != "$last" ] && [ -f "$AUTO_CHECK_MENU_FLAG" ]; then
            # save cursor, go up 3 lines (u-line is 3 above the prompt), rewrite, restore cursor
            printf '\0337\033[3A\r\033[2K%b! u/update     - Update the scripts (git pull) and restart the installer - Update available (%s new commit(s))%b\0338' \
                "$YELLOW" "$count" "$NC" > /dev/tty 2>/dev/null
        fi
        last=$count
    done
}

auto_check_start() {
    [ -n "$AUTO_CHECK_PID" ] && kill -0 "$AUTO_CHECK_PID" 2>/dev/null && return
    [ "$REPO_IS_GIT" == "1" ] || return
    auto_check_loop $$ &
    AUTO_CHECK_PID=$!
}

auto_check_stop() {
    if [ -n "$AUTO_CHECK_PID" ]; then
        kill "$AUTO_CHECK_PID" 2>/dev/null
        wait "$AUTO_CHECK_PID" 2>/dev/null
        AUTO_CHECK_PID=""
    fi
    rm -f "$AUTO_CHECK_MENU_FLAG"
}

# Pick up the poller's result when the menu is (re)drawn
auto_check_apply_state() {
    if [ -f "$AUTO_CHECK_STATE" ]; then
        local c
        c=$(cat "$AUTO_CHECK_STATE" 2>/dev/null)
        if [ "${c:-0}" -gt 0 ] 2>/dev/null; then
            UPDATE_AVAILABLE=1
            UPDATE_COUNT=$c
        fi
    fi
}

# Always clean up the helper - on quit, Ctrl-C, Ctrl-D (EOF), errors and the exec restart
cleanup_on_exit() {
    auto_check_stop
    rm -f "$AUTO_CHECK_STATE"
}
trap cleanup_on_exit EXIT
trap 'echo ""; exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

[ "$AUTO_CHECK" == "1" ] && auto_check_start

# Associative arrays to store script metadata
declare -A SCRIPT_DESCRIPTIONS
declare -A SCRIPT_DETECT_CMDS
declare -A SCRIPT_RETIRED
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
    # SCRIPT_RETIRED: 1 marks a script that only prints a notice (kept so the number stays known)
    local retired
    retired=$(grep '^# SCRIPT_RETIRED:' "$script_path" 2>/dev/null | sed 's/^# SCRIPT_RETIRED: //')
    
    # Store in arrays
    SCRIPT_NUMS+=("$script_num")
    SCRIPT_DESCRIPTIONS["$script_num"]="$desc"
    SCRIPT_DETECT_CMDS["$script_num"]="$detect_cmd"
    SCRIPT_RETIRED["$script_num"]="${retired:-0}"
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
    
    # Retired scripts are only a notice - no completion status
    if [ "${SCRIPT_RETIRED[$script_num]}" == "1" ]; then
        echo -e "  [${script_num}]: ${description}"
        return
    fi

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
    
    # Retired scripts only print a notice - nothing to complete or fail
    if [ "${SCRIPT_RETIRED[$script_num]}" == "1" ]; then
        bash "$script_path" < /dev/tty
        return 0
    fi

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
    auto_check_apply_state
    if [ -n "$REPO_VERSION" ]; then
        if [ "$UPDATE_AVAILABLE" == "1" ]; then
            echo -e "${YELLOW}Version: ${REPO_VERSION} - update available (${UPDATE_COUNT} new commit(s), option 'u')${NC}"
        else
            echo -e "${YELLOW}Version: ${REPO_VERSION}${NC}"
        fi
    fi
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
    if [ "$AUTO_CHECK" == "1" ]; then
        echo "  a/auto-check - Background check for updates every ${AUTO_CHECK_INTERVAL}s (fetch only, never pulls) [on]"
    else
        echo "  a/auto-check - Background check for updates every ${AUTO_CHECK_INTERVAL}s (fetch only, never pulls) [off]"
    fi
    if [ "$UPDATE_AVAILABLE" == "1" ]; then
        echo -e "${YELLOW}! u/update     - Update the scripts (git pull) and restart the installer - Update available (${UPDATE_COUNT} new commit(s))${NC}"
    else
        echo "  u/update     - Update the scripts (git pull) and restart the installer"
    fi
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
    
    touch "$AUTO_CHECK_MENU_FLAG"
    # Ctrl-D (EOF) at the prompt = quit cleanly (the EXIT trap stops the helper)
    if ! read -r -p "Enter your choice [all]: " choice; then
        rm -f "$AUTO_CHECK_MENU_FLAG"
        echo ""
        exit 0
    fi
    rm -f "$AUTO_CHECK_MENU_FLAG"
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
            
        "u"|"update")
            repo_update "$@"
            read -r -p "Press Enter to continue..."
            ;;
            
        "a"|"auto-check")
            if [ "$AUTO_CHECK" == "1" ]; then
                AUTO_CHECK=0
                auto_check_stop
                echo -e "${GREEN}Background update check turned off.${NC}"
            else
                if [ "$REPO_IS_GIT" != "1" ]; then
                    echo -e "${YELLOW}This copy is not a git checkout - there is nothing to check.${NC}"
                else
                    AUTO_CHECK=1
                    auto_check_start
                    echo -e "${GREEN}Background update check turned on (every ${AUTO_CHECK_INTERVAL}s, fetch only).${NC}"
                    echo "If new commits appear while the menu is shown, the 'u/update' line is highlighted."
                fi
            fi
            echo "AUTO_CHECK=$AUTO_CHECK" > "$SETTINGS_FILE"
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
