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
echo "CentOS Provisioning Report" > "$REPORT_FILE"

log_msg "[*] Starting HTB Provisioning..."

# 2. Hostname & Networking
hostnamectl set-hostname "$TARGET_HOSTNAME"
log_msg "[+] Hostname set to '$TARGET_HOSTNAME'"

if ! grep -q "$TARGET_HOSTNAME.$TARGET_DOMAIN" /etc/hosts; then
    echo "127.0.1.1   $TARGET_HOSTNAME.$TARGET_DOMAIN $TARGET_HOSTNAME" >> /etc/hosts
    log_msg "[+] Hosts file updated for $TARGET_HOSTNAME.$TARGET_DOMAIN"
fi

# 3. Essential Tools (wget, Python3, OpenSSH)
log_msg "[*] Updating system and installing essential tools..."
dnf update -y >> "$LOG_FILE" 2>&1
dnf install -y dnf-plugins-core net-tools wget python3 python3-pip openssh-server >> "$LOG_FILE" 2>&1
report_msg "Packages: wget, python3, pip, and net-tools installed"

# 4. Docker & Docker Compose Setup
log_msg "[*] Setting up Docker repository and installing Docker Compose..."
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >> "$LOG_FILE" 2>&1
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >> "$LOG_FILE" 2>&1
systemctl enable --now docker >> "$LOG_FILE" 2>&1
ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
report_msg "Packages: Docker and Docker Compose installed and enabled"

# 5. Localization
localectl set-locale LANG=en_US.UTF-8
report_msg "Locale: en_US.UTF-8 enforced"

# 6. User Creation
if ! id "$NEW_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$USER_PASS" | chpasswd
    usermod -aG docker "$NEW_USER"
    log_msg "[+] User '$NEW_USER' created and added to docker group"
fi

# 7. History Restoration (Ensuring Arrow-Up Works)
sed -i '/HISTFILE=\/dev\/null/d' /etc/profile
sed -i '/HISTSIZE=0/d' /etc/profile
sed -i '/export HISTFILE HISTSIZE/d' /etc/profile

for target_dir in "/root" "/home/$NEW_USER"; do
    for f in ".bash_history" ".viminfo"; do
        if [ -L "$target_dir/$f" ]; then
            rm -f "$target_dir/$f"
        fi
        touch "$target_dir/$f"
        # Set ownership based on the directory owner
        owner=$(ls -ld "$target_dir" | awk '{print $3}')
        chown "$owner":"$owner" "$target_dir/$f"
    done
done
log_msg "[+] Command history enabled for root and $NEW_USER"

# 8. Selective Firewall
log_msg "[*] Configuring firewall for ports: $USER_PORTS"
systemctl unmask firewalld >/dev/null 2>&1
systemctl enable --now firewalld >> "$LOG_FILE" 2>&1

for svc in $(firewall-cmd --permanent --list-services); do
    firewall-cmd --permanent --remove-service="$svc" >/dev/null 2>&1
done

IFS=',' read -ra ADDR <<< "$USER_PORTS"
for port in "${ADDR[@]}"; do
    clean_port=$(echo "$port" | xargs)
    if [[ $clean_port =~ ^[0-9]+$ ]]; then
        firewall-cmd --permanent --add-port="${clean_port}/tcp" >/dev/null 2>&1
        log_msg "[+] Port ${clean_port}/tcp opened"
    fi
done

# 9. SSH Configuration & Persistence
log_msg "[*] Enabling SSH service on boot..."
systemctl enable --now sshd >> "$LOG_FILE" 2>&1
firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1

firewall-cmd --reload >/dev/null 2>&1
report_msg "Firewall: Allowed ports: $USER_PORTS, plus SSH"

# --- Complete ---
echo -e "\n--- SETUP COMPLETE ---"
echo "Identity: $TARGET_HOSTNAME.$TARGET_DOMAIN"
echo "User: $NEW_USER"
echo "Command History: ENABLED"
log_msg "[*] Configuration finished."

echo "Rebooting in 10 seconds..."
sleep 10
reboot
