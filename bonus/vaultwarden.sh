#!/bin/bash
# ==========================================================
#   Vaultwarden Setup Script
#   Installs and configures Vaultwarden Password Manager
# ==========================================================

set -e

echo "=== Installing Vaultwarden Password Manager ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Install required dependencies
echo "Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y curl wget sqlite3 ca-certificates >/dev/null 2>&1

# Detect system architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        VAULTWARDEN_ARCH="x86_64-unknown-linux-gnu"
        ;;
    aarch64)
        VAULTWARDEN_ARCH="aarch64-unknown-linux-gnu"
        ;;
    armv7l)
        VAULTWARDEN_ARCH="armv7-unknown-linux-gnueabihf"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Detected architecture: $ARCH"

# Create vaultwarden user if doesn't exist
if ! id -u vaultwarden >/dev/null 2>&1; then
    echo "Creating vaultwarden system user..."
    useradd -r -s /bin/false -d /opt/vaultwarden vaultwarden
fi

# Create directory structure
echo "Setting up directories..."
mkdir -p /opt/vaultwarden/bin
mkdir -p /opt/vaultwarden/data
mkdir -p /opt/vaultwarden/web-vault

# Download latest Vaultwarden release
echo "Downloading Vaultwarden server..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest | grep "tag_name" | cut -d '"' -f 4)
echo "Latest version: ${LATEST_RELEASE}"

wget -q "https://github.com/dani-garcia/vaultwarden/releases/download/${LATEST_RELEASE}/vaultwarden-${LATEST_RELEASE}-${VAULTWARDEN_ARCH}.tar.gz" -O /tmp/vaultwarden.tar.gz

# Extract binary
echo "Extracting Vaultwarden..."
tar -xzf /tmp/vaultwarden.tar.gz -C /opt/vaultwarden/bin/
chmod +x /opt/vaultwarden/bin/vaultwarden
rm /tmp/vaultwarden.tar.gz

# Download web vault
echo "Downloading web vault interface..."
VAULT_VERSION=$(echo ${LATEST_RELEASE} | sed 's/^v//')
wget -q "https://github.com/dani-garcia/bw_web_builds/releases/download/v${VAULT_VERSION}/bw_web_v${VAULT_VERSION}.tar.gz" -O /tmp/web-vault.tar.gz 2>/dev/null || \
wget -q "https://github.com/dani-garcia/bw_web_builds/releases/latest/download/bw_web_builds.tar.gz" -O /tmp/web-vault.tar.gz

# Extract web vault
tar -xzf /tmp/web-vault.tar.gz -C /opt/vaultwarden/
rm /tmp/web-vault.tar.gz

# Set proper permissions
chown -R vaultwarden:vaultwarden /opt/vaultwarden
chmod 700 /opt/vaultwarden/data

# Generate admin token
ADMIN_TOKEN=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-64)

# Create environment configuration file
echo "Creating configuration..."
cat > /opt/vaultwarden/.env <<EOF
# Vaultwarden Configuration
ROCKET_ADDRESS=0.0.0.0
ROCKET_PORT=8000
WEB_VAULT_ENABLED=true
WEB_VAULT_FOLDER=/opt/vaultwarden/web-vault
DATA_FOLDER=/opt/vaultwarden/data
DATABASE_URL=/opt/vaultwarden/data/db.sqlite3

# Domain configuration
DOMAIN=http://localhost:8000

# Admin panel
ADMIN_TOKEN=${ADMIN_TOKEN}

# Security settings
SIGNUPS_ALLOWED=true
INVITATIONS_ALLOWED=true
SHOW_PASSWORD_HINT=false

# Logging
LOG_LEVEL=info
EXTENDED_LOGGING=true
LOG_FILE=/opt/vaultwarden/data/vaultwarden.log

# Performance
ENABLE_DB_WAL=true
EOF

chown vaultwarden:vaultwarden /opt/vaultwarden/.env
chmod 600 /opt/vaultwarden/.env

# Create systemd service file
echo "Creating systemd service..."
cat > /etc/systemd/system/vaultwarden.service <<'EOF'
[Unit]
Description=Vaultwarden Password Manager
After=network.target
Documentation=https://github.com/dani-garcia/vaultwarden

[Service]
Type=simple
User=vaultwarden
Group=vaultwarden
WorkingDirectory=/opt/vaultwarden
EnvironmentFile=/opt/vaultwarden/.env
ExecStart=/opt/vaultwarden/bin/vaultwarden
Restart=on-failure
RestartSec=5s

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/vaultwarden/data

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
echo "Enabling and starting Vaultwarden..."
systemctl daemon-reload
systemctl enable vaultwarden >/dev/null 2>&1
systemctl start vaultwarden

# Configure firewall
echo "Configuring firewall..."
ufw allow 8000/tcp >/dev/null 2>&1

# Wait for service to start
echo "Waiting for Vaultwarden to start..."
sleep 5

# Check if service is running
if systemctl is-active --quiet vaultwarden; then
    echo "✓ Vaultwarden installed and running successfully!"
else
    echo "⚠ Warning: Vaultwarden service may not be running properly."
    systemctl status vaultwarden --no-pager
fi

# Save admin token to a file for reference
echo "${ADMIN_TOKEN}" > /root/vaultwarden_admin_token.txt
chmod 600 /root/vaultwarden_admin_token.txt

echo
echo "=========================================================="
echo "Vaultwarden Password Manager Setup Complete!"
echo
echo "Service Information:"
echo "  - Status: $(systemctl is-active vaultwarden)"
echo "  - Version: ${LATEST_RELEASE}"
echo "  - Port: 8000"
echo "  - Data Directory: /opt/vaultwarden/data"
echo "  - Database: SQLite"
echo
echo "Access Instructions:"
echo "1. Configure port forwarding in VirtualBox:"
echo "   Settings → Network → Advanced → Port Forwarding"
echo "   Add rule: Host Port 8000 → Guest Port 8000"
echo
echo "2. Access Vaultwarden in your browser:"
echo "   http://127.0.0.1:8000"
echo
echo "3. Create Your Account:"
echo "   - Click 'Create Account'"
echo "   - Enter your email and master password"
echo "   - IMPORTANT: Remember your master password!"
echo "   - Your master password cannot be recovered"
echo
echo "4. Admin Panel Access:"
echo "   URL: http://127.0.0.1:8000/admin"
echo "   Token: ${ADMIN_TOKEN}"
echo
echo "   The admin token is also saved at:"
echo "   /root/vaultwarden_admin_token.txt"
echo
echo "Features:"
echo "  ✓ Full Bitwarden-compatible password manager"
echo "  ✓ Unlimited passwords, notes, and identities"
echo "  ✓ Secure password generator"
echo "  ✓ Two-factor authentication (2FA) support"
echo "  ✓ Password sharing (collections)"
echo "  ✓ Browser extensions available"
echo "  ✓ Mobile apps available"
echo "  ✓ Self-hosted = full control of your data"
echo
echo "Browser Extensions:"
echo "  - Chrome/Edge: https://chromewebstore.google.com/detail/bitwarden"
echo "  - Firefox: https://addons.mozilla.org/firefox/addon/bitwarden-password-manager"
echo
echo "Mobile Apps:"
echo "  - iOS: Search 'Bitwarden' in App Store"
echo "  - Android: Search 'Bitwarden' in Play Store"
echo
echo "Useful Commands:"
echo "  - Check status: systemctl status vaultwarden"
echo "  - Stop service: systemctl stop vaultwarden"
echo "  - Start service: systemctl start vaultwarden"
echo "  - Restart service: systemctl restart vaultwarden"
echo "  - View logs: journalctl -u vaultwarden -f"
echo "  - View log file: tail -f /opt/vaultwarden/data/vaultwarden.log"
echo
echo "Configuration:"
echo "  - Edit config: nano /opt/vaultwarden/.env"
echo "  - After editing: systemctl restart vaultwarden"
echo
echo "Backup:"
echo "  - Database: /opt/vaultwarden/data/db.sqlite3"
echo "  - Backup command: cp /opt/vaultwarden/data/db.sqlite3 ~/vaultwarden_backup.db"
echo
echo "Security Recommendations:"
echo "  1. Use a strong, unique master password"
echo "  2. Enable two-factor authentication"
echo "  3. Regular backups of the database"
echo "  4. Keep Vaultwarden updated"
echo "=========================================================="
