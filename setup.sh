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
sleep 5
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
systemctl status ssh --no-pager >/dev/null 2>&1

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
systemctl restart ssh >/dev/null 2>&1
systemctl status ssh --no-pager | grep -E "Active:|port"

echo "SSH configured on port 4242 with root login disabled."
echo

# ==========================================================
#  FIREWALL CONFIGURATION
# ==========================================================
echo "=== Firewall Setup (ufw) ==="
echo "Installing ufw for firewall setup"
apt install -y ufw >/dev/null 2>&1
echo "ufw package installed"
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 4242 >/dev/null 2>&1
echo "incoming and outgoing rules updated"
ufw --force enable >/dev/null 2>&1
ufw status verbose >/dev/null 2>&1
echo "firewall has been enabled"
echo

# ==========================================================
#  SUDO & USER GROUP CONFIGURATION
# ==========================================================
echo "=== User and Sudo Setup ==="
echo "Installing sudo package"
apt install -y sudo >/dev/null 2>&1
echo "sudo package installed"

# Backup sudoers file
cp /etc/sudoers /etc/sudoers.bak.$(date +%s)

SUDOERS_FILE="/etc/sudoers"
TMP_SUDOERS=$(mktemp)

# Copy to temp file for editing
cp "$SUDOERS_FILE" "$TMP_SUDOERS"

# Replace secure_path line (commented or not)
if grep -qE '^Defaults\s+secure_path=' "$TMP_SUDOERS"; then
    sed -i 's|^Defaults\s\+secure_path=.*|Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"|' "$TMP_SUDOERS"
else
    # Add secure_path if missing
    echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> "$TMP_SUDOERS"
fi

# Find the line number of secure_path
LINE_NUM=$(grep -nE '^Defaults\s+secure_path=' "$TMP_SUDOERS" | head -n 1 | cut -d: -f1)

# Insert the other Defaults settings right after secure_path line
awk -v ln="$LINE_NUM" '
NR == ln {
    print
    print "Defaults requiretty"
    print "Defaults badpass_message=\"WRONG PASSWORD\""
    print "Defaults logfile=\"/var/log/sudo/sudo.log\""
    print "Defaults log_input"
    print "Defaults log_output"
    print "Defaults iolog_dir=/var/log/sudo"
    print "Defaults passwd_tries=3"
    next
}
{ print }
' "$TMP_SUDOERS" > "${TMP_SUDOERS}.new"

mv "${TMP_SUDOERS}.new" "$TMP_SUDOERS"

# Validate the modified file before applying
if visudo -cf "$TMP_SUDOERS"; then
    cp "$TMP_SUDOERS" "$SUDOERS_FILE"
    echo "Sudo configuration updated successfully."
else
    echo "Error: Invalid sudoers configuration. Restoring backup."
    cp /etc/sudoers.bak.* "$SUDOERS_FILE"
    exit 1
fi

rm "$TMP_SUDOERS"

# --- User group setup ---
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
echo "Installing password quality checker"
apt install -y libpam-pwquality >/dev/null 2>&1
echo "Password quality checker installed"

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
echo "Enter you new password:"
passwd "$USERNAME"
echo "Enter new root password:"
passwd root

echo
echo "Retrieving monitoring.sh script from da goat Shadow :)"
sleep 1
wget https://raw.githubusercontent.com/ShadowThijs/42-born2beroot/refs/heads/main/monitoring.sh >/dev/null 2>&1
echo "monitoring.sh grabbed from da goat Shadow"
echo
echo "Changing permissions and moving monitoring.sh"
chmod +x monitoring.sh
mv monitoring.sh /etc/cron.d/monitoring.sh
CRONTAB_FILE="/var/spool/cron/crontabs/root"
touch $CRONTAB_FILE
echo "*/10 * * * * bash /etc/cron.d/monitoring.sh | wall" >> $CRONTAB_FILE

if BONUS_SETUP; then
	echo "=== BONUS setup starting ==="
	echo
fi

echo
echo "=== Setup Complete ==="
