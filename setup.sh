#!/bin/bash
# ==========================================================
#   System Setup Script (Debian-based)
#   Performs SSH, Firewall, Sudo, and Password Policy setup
# ==========================================================

set -e  # Exit immediately on any command failure

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$0" "$@"
    else
        echo "Error: sudo not found. Run this script as root."
        exit 1
    fi
fi

# --- Ask for username and bonus ---
read -rp "Enter your username: " USERNAME
while [[ -z "$USERNAME" ]]; do
    echo "Username cannot be empty."
    read -rp "Enter your username: " USERNAME
done

while true; do
    read -rp "Do you want to setup the bonus stuff? (yes/no): " BONUS_INPUT
    case "$BONUS_INPUT" in
        [Yy]* ) BONUS_SETUP=true; break ;;
        [Nn]* ) BONUS_SETUP=false; break ;;
        * ) echo "Please answer yes or no." ;;
    esac
done

echo "Username: $USERNAME"
echo "Bonus setup: $BONUS_SETUP"
echo

# ==========================================================
#  SSH CONFIGURATION
# ==========================================================
echo "=== SSH Setup ==="

if ! systemctl list-unit-files | grep -q '^ssh\.service'; then
    echo "SSH service not found. Installing OpenSSH server..."
    apt update -y
    apt install -y openssh-server
fi

# Check if ssh service is running
if ! systemctl is-active --quiet ssh; then
    echo "Starting SSH service..."
    systemctl start ssh
fi

# Confirm SSH is running
systemctl status ssh --no-pager

# Configure sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    echo "Configuring SSH settings..."
    sed -i 's/^#\?Port .*/Port 4242/' "$SSHD_CONFIG"
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CONFIG"
else
    echo "Warning: sshd_config not found at $SSHD_CONFIG"
fi

# Restart and verify SSH
systemctl restart ssh
systemctl status ssh --no-pager | grep -E "Active:|port"

echo "SSH configured on port 4242 with root login disabled."
echo

# ==========================================================
#  FIREWALL CONFIGURATION
# ==========================================================
echo "=== Firewall Setup (ufw) ==="
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 4242
ufw --force enable
ufw status verbose
echo

# ==========================================================
#  SUDO & USER GROUP CONFIGURATION
# ==========================================================
echo "=== User and Sudo Setup ==="
apt install -y sudo

# Ensure sudoers file backup
cp /etc/sudoers /etc/sudoers.bak

# Use a temp file to append custom defaults safely
SUDO_TMP=$(mktemp)
cat <<EOF >>"$SUDO_TMP"
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults requiretty
Defaults badpass_message="WRONG PASSWORD"
Defaults logfile="/var/log/sudo/sudo.log"
Defaults log_input
Defaults log_output
Defaults iolog_dir=/var/log/sudo
Defaults passwd_tries=3
EOF

# Merge safely with visudo check
visudo -cf "$SUDO_TMP" && cat "$SUDO_TMP" >> /etc/sudoers
rm "$SUDO_TMP"

# Create user group and add user
groupadd -f user42
usermod -aG user42,sudo "$USERNAME"

# Verify group membership
echo "Checking user groups for $USERNAME..."
grep "$USERNAME" /etc/group || echo "Warning: user not found in groups file"
echo

# ==========================================================
#  PASSWORD POLICY CONFIGURATION
# ==========================================================
echo "=== Password Policy Setup ==="

# Modify /etc/login.defs
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   30/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   2/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

# Apply chage for users
chage -M 30 "$USERNAME"
chage -m 2 "$USERNAME"
chage -M 30 root
chage -m 2 root

# Install password quality module
apt install -y libpam-pwquality

# Update common-password file
PAM_FILE="/etc/pam.d/common-password"
if grep -q "pam_pwquality.so" "$PAM_FILE"; then
    sed -i 's/^password\s\+requisite\s\+pam_pwquality\.so.*/password        requisite                       pam_pwquality.so retry=3 minlen=10 difok=7 maxrepeat=3 dcredit=-1 ucredit=-1 lcredit=-1 reject_username enforce_for_root/' "$PAM_FILE"
else
    echo "password        requisite                       pam_pwquality.so retry=3 minlen=10 difok=7 maxrepeat=3 dcredit=-1 ucredit=-1 lcredit=-1 reject_username enforce_for_root" >> "$PAM_FILE"
fi

echo
echo "You must now change the passwords for both $USERNAME and root."
echo "Use strong passwords — you won’t be able to change them again for 2 days."
passwd "$USERNAME"
passwd root

echo
echo "=== Setup Complete ==="
