#!/bin/bash

# --- Hardcoded Configuration ---
TARGET_DOMAIN="htb"
LOG_FILE="/var/log/system_init.log"
REPORT_FILE="/tmp/setup_report.txt"

log_msg() { echo -e "$1" | tee -a "$LOG_FILE"; }
report_msg() { echo "- $1" >> "$REPORT_FILE"; }

# 1. Usage and Argument Check (4 Arguments)
if [ "$#" -ne 4 ]; then
    echo "Usage: sudo $0 <hostname> <ports_to_expose> <username> <password>"
    echo "Example: sudo $0 zozo 80,443 developer P@ssword123"
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

log_msg "[*] Starting HTB CentOS 10 Provisioning..."

# 2. Hostname & Networking
hostnamectl set-hostname "$TARGET_HOSTNAME"
log_msg "[+] Hostname set to '$TARGET_HOSTNAME'"

# Automatically maps to .htb (e.g., zozo.htb)
if ! grep -q "$TARGET_HOSTNAME.$TARGET_DOMAIN" /etc/hosts; then
    echo "127.0.1.1   $TARGET_HOSTNAME.$TARGET_DOMAIN $TARGET_HOSTNAME" >> /etc/hosts
    log_msg "[+] Hosts file updated for $TARGET_HOSTNAME.$TARGET_DOMAIN"
fi

# 3. Updates & Essential Tools
log_msg "[*] Updating system and installing net-tools..."
dnf update -y >> "$LOG_FILE" 2>&1
dnf install -y net-tools >> "$LOG_FILE" 2>&1

# 4. Localization (HTB Requirement)
localectl set-locale LANG=en_US.UTF-8
report_msg "Locale: en_US.UTF-8 enforced"

# 5. User Creation
if ! id "$NEW_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$USER_PASS" | chpasswd
    log_msg "[+] User '$NEW_USER' created"
fi

# 6. History Lockdown (The "Invisible Build" Rule)
if ! grep -q 'HISTFILE=/dev/null' /etc/profile; then
    { 
      echo 'HISTFILE=/dev/null'
      echo 'HISTSIZE=0'
      echo 'export HISTFILE HISTSIZE'
    } >> /etc/profile
fi

# Apply history suppression for root and the new user
for target_dir in "/root" "/home/$NEW_USER"; do
    for f in ".bash_history" ".viminfo" ".mysql_history"; do
        ln -sf /dev/null "$target_dir/$f"
        chown root:root "$target_dir/$f"
    done
done
report_msg "Security: History files suppressed for root and $NEW_USER"

# 7. Selective Firewall
log_msg "[*] Configuring firewall for ports: $USER_PORTS"
systemctl unmask firewalld >/dev/null 2>&1
systemctl enable --now firewalld >> "$LOG_FILE" 2>&1

# Remove default RHEL services
for svc in $(firewall-cmd --permanent --list-services); do
    firewall-cmd --permanent --remove-service="$svc" >/dev/null 2>&1
done

# Open specified TCP ports
IFS=',' read -ra ADDR <<< "$USER_PORTS"
for port in "${ADDR[@]}"; do
    clean_port=$(echo $port | xargs)
    if [[ $clean_port =~ ^[0-9]+$ ]]; then
        firewall-cmd --permanent --add-port="${clean_port}/tcp" >/dev/null 2>&1
        log_msg "[+] Port ${clean_port}/tcp opened"
    fi
done

firewall-cmd --reload >/dev/null 2>&1
report_msg "Firewall: Allowed ports: $USER_PORTS"

# --- Complete ---
echo -e "\n--- SETUP COMPLETE ---"
echo "Identity: $TARGET_HOSTNAME.$TARGET_DOMAIN"
echo "User: $NEW_USER"
log_msg "[✅] Configuration finished."

echo "Rebooting in 10 seconds..."
sleep 10
reboot
