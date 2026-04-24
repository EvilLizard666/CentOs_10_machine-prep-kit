#!/bin/bash

# --- Configuration & Logging ---
LOG_FILE="/var/log/system_init.log"
REPORT_FILE="/tmp/setup_report.txt"
TARGET_DOMAIN="archiver.htb"

# --- Initialization ---
log_msg() { echo -e "$1" | tee -a "$LOG_FILE"; }
report_msg() { echo "- $1" >> "$REPORT_FILE"; }

# 1. Usage and Argument Check
if [ "$#" -ne 4 ]; then
    echo "Usage: sudo $0 <hostname> <ports_to_expose> <username> <password>"
    echo "Example: sudo $0 archiver 22,9418 developer W3lcome2archive"
    exit 1
fi

TARGET_HOSTNAME=$1
USER_PORTS=$2
NEW_USER=$3
USER_PASS=$4

if [ "$EUID" -ne 0 ]; then 
    echo "[-] This script must be run as root."
    exit 1
fi

echo "--- System Initialization Log: $(date) ---" > "$LOG_FILE"
echo "CentOS 10 Provisioning Report" > "$REPORT_FILE"
echo "------------------------------------" >> "$REPORT_FILE"

log_msg "[*] Starting Universal CentOS 10 Provisioning..."

# 2. Hostname & Networking
if [ "$(hostname)" != "$TARGET_HOSTNAME" ]; then
    hostnamectl set-hostname "$TARGET_HOSTNAME"
    log_msg "[+] Hostname set to '$TARGET_HOSTNAME'"
    report_msg "Hostname: $TARGET_HOSTNAME"
else
    log_msg "[✓] Hostname already correct ($TARGET_HOSTNAME)"
fi

if ! grep -q "$TARGET_HOSTNAME" /etc/hosts; then
    echo "127.0.1.1   $TARGET_HOSTNAME.htb $TARGET_HOSTNAME" >> /etc/hosts
    log_msg "[+] Hosts file updated with $TARGET_HOSTNAME"
fi

# 3. Package Management & Updates
log_msg "[*] Checking for updates..."
dnf check-update -q
if [ $? -eq 100 ]; then
    log_msg "[+] Installing system updates..."
    dnf update -y >> "$LOG_FILE" 2>&1
    report_msg "Updates: System fully patched"
else
    log_msg "[✓] System is already up to date"
fi

# 4. Essential Tools (net-tools for ifconfig)
if ! command -v ifconfig >/dev/null 2>&1; then
    log_msg "[+] Installing net-tools..."
    dnf install -y net-tools >> "$LOG_FILE" 2>&1
    report_msg "Tools: net-tools (ifconfig) installed"
fi

# 5. Localization (HTB Requirement)
if [[ $(localectl status) != *"LANG=en_US.UTF-8"* ]]; then
    localectl set-locale LANG=en_US.UTF-8
    log_msg "[+] Locale set to en_US.UTF-8"
fi

# 6. User Creation
if ! id "$NEW_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$USER_PASS" | chpasswd
    log_msg "[+] User '$NEW_USER' created"
    report_msg "User: $NEW_USER created"
else
    echo "$NEW_USER:$USER_PASS" | chpasswd
    log_msg "[✓] User '$NEW_USER' already exists; password updated"
fi

# 7. History Lockdown
if ! grep -q 'HISTFILE=/dev/null' /etc/profile; then
    {
        echo 'HISTFILE=/dev/null'
        echo 'HISTSIZE=0'
        echo 'export HISTFILE HISTSIZE'
    } >> /etc/profile
    log_msg "[+] History suppression added to /etc/profile"
fi

for target_dir in "/root" "/home/$NEW_USER"; do
    for f in ".bash_history" ".viminfo" ".mysql_history"; do
        target_file="$target_dir/$f"
        if [ ! -L "$target_file" ] || [ "$(readlink "$target_file")" != "/dev/null" ]; then
            ln -sf /dev/null "$target_file"
            chown root:root "$target_file"
            log_msg "[+] $target_file linked to /dev/null"
        fi
    done
done
report_msg "Security: History files made immutable"

# 8. Firewall Configuration
log_msg "[*] Configuring firewall for ports: $USER_PORTS"
systemctl unmask firewalld >/dev/null 2>&1
systemctl enable --now firewalld >> "$LOG_FILE" 2>&1

for svc in $(firewall-cmd --permanent --list-services); do
    firewall-cmd --permanent --remove-service="$svc" >/dev/null 2>&1
done

IFS=',' read -ra ADDR <<< "$USER_PORTS"
for port in "${ADDR[@]}"; do
    clean_port=$(echo $port | xargs)
    if [[ $clean_port =~ ^[0-9]+$ ]]; then
        firewall-cmd --permanent --add-port="${clean_port}/tcp" >/dev/null 2>&1
        log_msg "[+] Port ${clean_port}/tcp opened"
    fi
done

firewall-cmd --reload >/dev/null 2>&1
report_msg "Firewall: Running. Ports allowed: $USER_PORTS"

# --- Output Summary & Reboot ---
echo -e "\n--- SETUP COMPLETE ---"
cat "$REPORT_FILE"
log_msg "[✅] Basic configuration finished. Detailed logs: $LOG_FILE"

echo "------------------------------------------------"
echo "The system will reboot in 10 seconds..."
for i in {10..1}; do echo -n "$i... "; sleep 1; done
echo -e "\n[!] Rebooting now."
reboot
