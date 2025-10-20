#!/bin/bash
# ==========================================================
#   Filebrowser Setup Script
#   Installs and configures Filebrowser as a systemd service
# ==========================================================

set -e

echo "=== Installing Filebrowser ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Install curl if not present
if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl..."
    apt update -y >/dev/null 2>&1
    apt install -y curl >/dev/null 2>&1
fi

# Create filebrowser user if doesn't exist
if ! id -u filebrowser >/dev/null 2>&1; then
    echo "Creating filebrowser system user..."
    useradd -r -s /bin/false -d /opt/filebrowser filebrowser
fi

# Create directory structure
echo "Setting up directories..."
mkdir -p /opt/filebrowser
mkdir -p /etc/filebrowser
mkdir -p /var/lib/filebrowser

# Download and install filebrowser
echo "Downloading Filebrowser..."
curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash >/dev/null 2>&1

# Move binary to proper location
mv /usr/local/bin/filebrowser /opt/filebrowser/filebrowser 2>/dev/null || true

# Create filebrowser configuration
echo "Creating configuration..."
cat > /etc/filebrowser/config.json <<'EOF'
{
  "port": 8080,
  "baseURL": "",
  "address": "0.0.0.0",
  "log": "stdout",
  "database": "/var/lib/filebrowser/filebrowser.db",
  "root": "/srv/filebrowser"
}
EOF

# Create data directory
mkdir -p /srv/filebrowser

# Set proper permissions
chown -R filebrowser:filebrowser /opt/filebrowser
chown -R filebrowser:filebrowser /var/lib/filebrowser
chown -R filebrowser:filebrowser /srv/filebrowser
chmod 755 /opt/filebrowser/filebrowser

# Initialize database with default admin user
echo "Initializing database..."
sudo -u filebrowser /opt/filebrowser/filebrowser config init \
    --database /var/lib/filebrowser/filebrowser.db \
    --port 8080 \
    --address 0.0.0.0 \
    --root /srv/filebrowser >/dev/null 2>&1

# Set default credentials (admin/admin)
sudo -u filebrowser /opt/filebrowser/filebrowser users add admin admin \
    --database /var/lib/filebrowser/filebrowser.db \
    --perm.admin >/dev/null 2>&1 || true

# Create systemd service file
echo "Creating systemd service..."
cat > /etc/systemd/system/filebrowser.service <<'EOF'
[Unit]
Description=Filebrowser - Web File Browser
After=network.target

[Service]
Type=simple
User=filebrowser
Group=filebrowser
ExecStart=/opt/filebrowser/filebrowser -c /etc/filebrowser/config.json
Restart=on-failure
RestartSec=5s

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/filebrowser /srv/filebrowser

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
echo "Enabling and starting service..."
systemctl daemon-reload
systemctl enable filebrowser >/dev/null 2>&1
systemctl start filebrowser

# Configure firewall
echo "Configuring firewall..."
ufw allow 8080/tcp >/dev/null 2>&1

# Wait a moment for service to start
sleep 2

# Check if service is running
if systemctl is-active --quiet filebrowser; then
    echo "✓ Filebrowser installed and running successfully!"
else
    echo "⚠ Warning: Filebrowser service may not be running properly."
    systemctl status filebrowser --no-pager
fi

echo
echo "=========================================================="
echo "Filebrowser Setup Complete!"
echo
echo "Service Information:"
echo "  - Status: $(systemctl is-active filebrowser)"
echo "  - Port: 8080"
echo "  - Root Directory: /srv/filebrowser"
echo "  - Database: /var/lib/filebrowser/filebrowser.db"
echo
echo "Access Instructions:"
echo "1. Configure port forwarding in VirtualBox:"
echo "   Settings → Network → Advanced → Port Forwarding"
echo "   Add rule: Host Port 8080 → Guest Port 8080"
echo
echo "2. Access Filebrowser in your browser:"
echo "   http://127.0.0.1:8080"
echo
echo "3. Default Login Credentials:"
echo "   Username: admin"
echo "   Password: admin"
echo
echo "⚠ IMPORTANT: Change the default password after first login!"
echo "   (Settings → User Management → Edit User)"
echo
echo "Useful Commands:"
echo "  - Check status: systemctl status filebrowser"
echo "  - Stop service: systemctl stop filebrowser"
echo "  - Start service: systemctl start filebrowser"
echo "  - View logs: journalctl -u filebrowser -f"
echo "=========================================================="
