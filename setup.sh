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
mkdir /var/log/sudo
touch /var/log/sudo/sudo.log
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

# ==========================================================
#  CRON JOB SETUP
# ==========================================================
echo
echo "=== Setting up monitoring cron job ==="

# Download the script
TMP_MONITOR="/tmp/monitoring.sh"
echo "Retrieving monitoring.sh script from da goat Shadow :)"
wget -q -O "$TMP_MONITOR" "https://raw.githubusercontent.com/ShadowThijs/42-born2beroot/refs/heads/main/monitoring.sh"

# Move it to a safe location and set permissions
install -m 755 "$TMP_MONITOR" /usr/local/bin/monitoring.sh
echo "monitoring.sh installed to /usr/local/bin/monitoring.sh"
rm -f "$TMP_MONITOR"

# Verify crontab doesn't already contain the job
CRON_JOB="*/10 * * * * /bin/bash /usr/local/bin/monitoring.sh | /usr/bin/wall"

# Backup current crontab (if any)
crontab -l -u root 2>/dev/null > /tmp/root_cron.bak || true

# Add the job only if it's not already there
if ! crontab -l 2>/dev/null | grep -Fq "/usr/local/bin/monitoring.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Cron job added successfully: $CRON_JOB"
else
    echo "Cron job already exists. Skipping."
fi

# Confirm cron job is installed
echo
echo "Current root crontab:"
crontab -l

# ==========================================================
#  BONUS SECTION — WORDPRESS SETUP
# ==========================================================
if [ "$BONUS_SETUP" = true ]; then
    echo
    echo "=== BONUS SETUP: Installing and Configuring WordPress ==="
    echo "Hold tight, we're setting up the web server, database, and PHP stack!"
    echo

    # --- Install required packages ---
    echo "[1/5] Installing lighttpd web server..."
    apt install -y lighttpd >/dev/null 2>&1

    echo "[2/5] Installing MariaDB database server..."
    apt install -y mariadb-server >/dev/null 2>&1

    echo "[3/5] Installing PHP and required extensions..."
    apt install -y php php-pdo php-mysql php-zip php-gd php-mbstring php-curl php-xml php-pear php-bcmath php-opcache php-json php-cgi >/dev/null 2>&1

    echo "[4/5] Enabling PHP support in lighttpd..."
    lighttpd-enable-mod fastcgi fastcgi-php
    systemctl restart lighttpd >/dev/null 2>&1

    echo "[5/5] Updating firewall to allow HTTP traffic (port 80)..."
    ufw allow http >/dev/null 2>&1
    echo
    echo "Web server and PHP modules installed successfully."
    echo

    # --- Set up MariaDB database ---
    echo "=== Configuring MariaDB Database ==="
    systemctl enable mariadb >/dev/null 2>&1
    systemctl start mariadb >/dev/null 2>&1

    # Generate a secure random password for the database user
    DB_PASS="password"

    echo "Creating WordPress database and user for '$USERNAME'..."
    mariadb <<EOF
CREATE DATABASE ${USERNAME}_db;
CREATE USER '${USERNAME}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${USERNAME}_db.* TO '${USERNAME}'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF

    echo "Database '${USERNAME}_db' and user '${USERNAME}' created successfully."
    echo "Database password: ${DB_PASS}"
    echo

    # --- Download and configure WordPress ---
    echo "=== Setting up WordPress ==="
    cd /var/www/html/ || exit 1
    echo "Cleaning old files..."
    rm -rf ./*

    echo "Downloading latest WordPress..."
    wget -q https://wordpress.org/latest.tar.gz >/dev/null 2>&1
    tar xzf latest.tar.gz >/dev/null 2>&1
    rm latest.tar.gz
    mv wordpress/* .
    rm -rf wordpress

    echo "Setting correct permissions..."
    chown -R www-data:www-data /var/www/html/

    echo
    echo "WordPress files deployed successfully!"
    echo

    # --- Final instructions for the user ---
    echo "=========================================================="
    echo "WordPress installation completed!"
    echo
    echo "Next steps:"
    echo "1. Open VirtualBox settings for this VM."
    echo "2. Under 'Network' → 'Advanced' → 'Port Forwarding', add a rule:"
    echo "     Name: HTTP"
    echo "     Host Port: 1672   (or any free port you prefer)"
    echo "     Guest Port: 80"
    echo
    echo "Then, on your host machine, open your browser and go to:"
    echo "		http://127.0.0.1:1672"
    echo
    echo "In the WordPress setup wizard:"
    echo "	- Database Name: ${USERNAME}_db"
    echo "	- Username: ${USERNAME}"
    echo "	- Password: ${DB_PASS}"
    echo "	- Database Host: localhost"
    echo "	- Table Prefix: wp_ (default is fine)"
    echo
    echo "When prompted, create your WordPress admin account."
    echo "You’ll then be able to access your site and admin dashboard."
    echo
    echo
    echo
    echo "=== Bonus Service Setup ==="
    echo "Now you can choose an optional service to install!"
    echo "Pick one of the following:"
    echo "==== IMPORTANT ===="
    echo
    echo "THESE SCRIPTS HAVE NOT BEEN MADE BY ME!"
    echo "I DID NOT VERIFY IF THEY STILL OR WILL WORK"
    echo "PLEASE TEST ON A CLONE OF YOUR VIRTUAL MACHINE!!!"
    echo
    echo "1) Netdata (System Monitoring)"
    echo "2) Jellyfin (Media Server)"
    echo "3) Vaultwarden (Password Manager)"
    echo "4) n8n (Automation Tool)"
    echo "5) Filebrowser (Cloud Storage)"
    echo "0) Skip this step or choose your own service"

    read -rp "Enter the number of your choice: " SERVICE_CHOICE

    case "$SERVICE_CHOICE" in
        1) SERVICE_NAME="netdata" ;;
        2) SERVICE_NAME="jellyfin" ;;
        3) SERVICE_NAME="vaultwarden" ;;
        4) SERVICE_NAME="n8n" ;;
        5) SERVICE_NAME="filebrowser" ;;
        0) SERVICE_NAME="none" ;;
        *) echo "Invalid choice, skipping."; SERVICE_NAME="none" ;;
    esac

    if [ "$SERVICE_NAME" != "none" ]; then
        echo "Installing $SERVICE_NAME..."
        wget -q "https://raw.githubusercontent.com/ShadowThijs/42-born2beroot/refs/heads/main/bonus/${SERVICE_NAME}.sh" -O /tmp/${SERVICE_NAME}.sh
        chmod +x /tmp/${SERVICE_NAME}.sh
        bash /tmp/${SERVICE_NAME}.sh
    else
        echo "Skipping bonus service setup."
    fi
fi


echo
echo "=== Setup Complete ==="
