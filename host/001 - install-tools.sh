#!/usr/bin/env bash
# SCRIPT_DESC: Install essential tools (curl, git, gpg, htop, iperf3, lshw, mc, s-tui, unzip, wget) and setup power-management (powertop, AutoASPM)
# SCRIPT_DETECT: command -v htop &>/dev/null && command -v nvtop &>/dev/null

apt update
echo ">>> Installing common tools:"
echo ">>> curl, git, gpg, htop, iperf3, lshw, mc, s-tui, unzip, wget"
apt install -y curl git gpg htop iperf3 lshw mc s-tui unzip wget
echo ">>> Installation of common tools completed."

while true; do
    read -r -p "Do you want to add and run power management optimizations? [Y/n] " yn
    yn=${yn:-Y}  # Default to 'Y' if input is empty
    case "$yn" in
        [Nn]* )
            echo ">>> Power management optimizations not added."
            break
            ;;
        [Yy]* )
            echo ">>> Installing powertop and AutoASPM"
            apt install -y powertop
            echo ">>> Cloning AutoASPM repository to /opt/AutoASPM"
            git clone https://github.com/notthebee/AutoASPM.git /opt/AutoASPM
            echo ">>> Running power management optimizations via Powertop - \"powertop --auto-tune\" "
            powertop --auto-tune
            echo ">>> Running power management optimizations via AutoASPM - \"chmod u+x /opt/AutoASPM/pkgs/autoaspm.py && /opt/AutoASPM/pkgs/autoaspm.py\" "
            chmod u+x /opt/AutoASPM/pkgs/autoaspm.py && /opt/AutoASPM/pkgs/autoaspm.py
            echo ">>> Power management optimizations added"
            break
            ;;
        * )
            echo ">>> Please answer yes or no."
            ;;
    esac
done

ps1_line="PS1='\${debian_chroot:+(\$debian_chroot)}\\[\\033[01;31m\\]\\u\\[\\033[01;33m\\]@\\[\\033[01;36m\\]\\h \\[\\033[01;33m\\]\\w \\[\\033[01;35m\\]\\\$ \\[\\033[00m\\]'"
while true; do
    read -r -p "Do you want to add a colorful LS and PS1 prompt to ~/.bashrc? [Y/n] " yn
    yn=${yn:-Y}  # Default to 'Y' if input is empty
    case "$yn" in
        [Nn]* )
            echo ">>> PS1 prompt not added."
            break
            ;;
        [Yy]* )
            # Check if the line already exists in ~/.bashrc
            echo "$ps1_line" >> ~/.bashrc
            echo "export LS_OPTIONS='--color=auto'" >> ~/.bashrc
            echo "alias ls='ls \$LS_OPTIONS'" >> ~/.bashrc
            echo ">>> LS and PS1 prompt added to ~/.bashrc"
            break
            ;;
        * )
            echo ">>> Please answer yes or no."
            ;;
    esac
done