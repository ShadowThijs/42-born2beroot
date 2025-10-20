#!/bin/bash
# ==========================================================
#   Jellyfin Setup Script
#   Installs and configures Jellyfin Media Server
# ==========================================================

set -e

echo "=== Installing Jellyfin Media Server ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Install required dependencies
echo "Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y curl gnupg apt-transport-https ca-certificates >/dev/null 2>&1

# Add Jellyfin repository
echo "Adding Jellyfin repository..."

# Import GPG key
curl -fsSL https://repo.jellyfin.org/debian/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/jellyfin.gpg

# Detect Debian version
DEBIAN_VERSION=$(lsb_release -cs 2>/dev/null || echo "bullseye")

# Add repository
echo "deb [arch=$( dpkg --print-architecture )] https://repo.jellyfin.org/debian ${DEBIAN_VERSION} main" | tee /etc/apt/sources.list.d/jellyfin.list

# Update package list
echo "Updating package lists..."
apt update -y >/dev/null 2>&1

# Install Jellyfin server
echo "Installing Jellyfin server..."
apt install -y jellyfin >/dev/null 2>&1

# Create media directories
echo "Creating media directories..."
mkdir -p /media/jellyfin/movies
mkdir -p /media/jellyfin/tv-shows
mkdir -p /media/jellyfin/music
mkdir -p /media/jellyfin/photos

# Set proper permissions
chown -R jellyfin:jellyfin /media/jellyfin
chmod -R 755 /media/jellyfin

# Ensure Jellyfin data directory exists
mkdir -p /var/lib/jellyfin
chown -R jellyfin:jellyfin /var/lib/jellyfin

# Configure systemd service (ensure it's properly set up)
echo "Configuring Jellyfin service..."

# Create or update systemd service override
mkdir -p /etc/systemd/system/jellyfin.service.d
cat > /etc/systemd/system/jellyfin.service.d/override.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=5s
EOF

# Reload systemd
systemctl daemon-reload

# Enable and start Jellyfin
echo "Enabling and starting Jellyfin..."
systemctl enable jellyfin >/dev/null 2>&1
systemctl restart jellyfin

# Configure firewall
echo "Configuring firewall..."
ufw allow 8096/tcp >/dev/null 2>&1  # Web interface
ufw allow 8920/tcp >/dev/null 2>&1  # HTTPS web interface
ufw allow 7359/udp >/dev/null 2>&1  # Service discovery
ufw allow 1900/udp >/dev/null 2>&1  # DLNA

# Wait for service to start
echo "Waiting for Jellyfin to start..."
sleep 5

# Check if service is running
if systemctl is-active --quiet jellyfin; then
    echo "✓ Jellyfin installed and running successfully!"
else
    echo "⚠ Warning: Jellyfin service may not be running properly."
    systemctl status jellyfin --no-pager
fi

# Get server info
JELLYFIN_VERSION=$(dpkg -l | grep jellyfin-server | awk '{print $3}')

echo
echo "=========================================================="
echo "Jellyfin Media Server Setup Complete!"
echo
echo "Service Information:"
echo "  - Status: $(systemctl is-active jellyfin)"
echo "  - Version: ${JELLYFIN_VERSION}"
echo "  - Web Interface Port: 8096"
echo "  - HTTPS Port: 8920"
echo
echo "Media Directories Created:"
echo "  - Movies: /media/jellyfin/movies"
echo "  - TV Shows: /media/jellyfin/tv-shows"
echo "  - Music: /media/jellyfin/music"
echo "  - Photos: /media/jellyfin/photos"
echo
echo "Access Instructions:"
echo "1. Configure port forwarding in VirtualBox:"
echo "   Settings → Network → Advanced → Port Forwarding"
echo "   Add rule: Host Port 8096 → Guest Port 8096"
echo
echo "2. Access Jellyfin in your browser:"
echo "   http://127.0.0.1:8096"
echo
echo "3. Initial Setup Wizard:"
echo "   - Select your preferred language"
echo "   - Create an administrator account"
echo "   - Set up your media libraries (point to /media/jellyfin/...)"
echo "   - Configure remote access settings"
echo "   - Complete the setup"
echo
echo "Adding Media Files:"
echo "  You can copy media files to the directories above."
echo "  Example: cp your-movie.mp4 /media/jellyfin/movies/"
echo "  Then scan libraries in Jellyfin to detect new content."
echo
echo "Useful Commands:"
echo "  - Check status: systemctl status jellyfin"
echo "  - Stop service: systemctl stop jellyfin"
echo "  - Start service: systemctl start jellyfin"
echo "  - Restart service: systemctl restart jellyfin"
echo "  - View logs: journalctl -u jellyfin -f"
echo "  - Check version: dpkg -l | grep jellyfin"
echo
echo "Troubleshooting:"
echo "  - Config files: /etc/jellyfin/"
echo "  - Data directory: /var/lib/jellyfin/"
echo "  - Log files: /var/log/jellyfin/"
echo "  - Cache directory: /var/cache/jellyfin/"
echo
echo "=========================================================="
