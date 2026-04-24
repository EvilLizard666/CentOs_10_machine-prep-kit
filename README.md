# C10-Provisioner

[![Platform](https://img.shields.io/badge/Platform-CentOS%20Stream%2010-orange.svg)](https://www.centos.org/centos-stream/)
[![Usage](https://img.shields.io/badge/Use%20Case-HTB%20Machine%20Build-blue.svg)](https://www.hackthebox.com/)

**C10-Provisioner** is an idempotent system initialization framework for CentOS Stream 10. It automates the transition from a fresh "Minimal" installation to a hardened, research-ready baseline compliant with Hack The Box (HTB) submission standards.

---

## 🚀 Key Features

- **HTB Submission Compliance:** Automatically enforces mandatory standards such as English (US) localization, `.htb` domain mapping, and root-owned shell history redirection.
- **Idempotent Design:** Safely re-run the script multiple times. It detects existing configurations to prevent redundant entries or system conflicts.
- **Security Hardening:** Implements "Invisible Build" requirements by symlinking `.bash_history`, `.viminfo`, and `.mysql_history` to `/dev/null` for both `root` and non-privileged users.
- **Granular Networking:** Wipes default RHEL services (Cockpit, DHCPv6-client) and implements a selective firewall based on user-provided arguments.
- **Automated Reporting:** Generates a setup audit log in `/var/log/system_init.log` and a clean summary in `/tmp/setup_report.txt` for use in walkthrough documentation.

---

## 🛠️ Usage

### Prerequisites
- A fresh installation of **CentOS Stream 10**.
- Root or Sudo privileges.

### Execution
Clone the repository or download the script, then execute with the required arguments:

```bash
chmod +x provision.sh
sudo ./provision.sh <ports_to_expose> <username> <password>
