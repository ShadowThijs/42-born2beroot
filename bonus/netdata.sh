#!/bin/bash
# ==========================================================
#   Netdata Setup Script
#   Installs and configures Netdata System Monitoring
# ==========================================================

set -e

echo "=== Installing Netdata System Monitoring ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Install required dependencies
echo "Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y curl wget gnupg ca-certificates >/dev/null 2>&1

# Download and run official Netdata installation script
echo "Downloading Netdata installer..."
wget -q -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh

# Make installer executable
chmod +x /tmp/netdata-kickstart.sh

# Install Netdata (non-interactive mode)
echo "Installing Netdata (this may take a few minutes)..."
/tmp/netdata-kickstart.sh --non-interactive --stable-channel --disable-telemetry 2>&1 | grep -E "Successfully|installed|FAILED" || true

# Clean up installer
rm -f /tmp/netdata-kickstart.sh

# Wait for Netdata to initialize
sleep 3

# Configure Netdata
echo "Configuring Netdata..."

# Create custom configuration directory if it doesn't exist
mkdir -p /etc/netdata

# Generate default configuration if not present
if [ ! -f /etc/netdata/netdata.conf ]; then
    /usr/sbin/netdatacli reload-health 2>/dev/null || true
fi

# Edit configuration to bind to all interfaces
cat > /etc/netdata/netdata.conf <<'EOF'
[global]
    # Run as specific user
    run as user = netdata

    # Web server settings
    bind to = 0.0.0.0
    default port = 19999

    # Performance settings
    memory mode = dbengine
    page cache size = 32
    dbengine disk space = 256

[web]
    # Web interface settings
    enable gzip compression = yes
    gzip compression level = 3

[plugins]
    # Enable/disable plugins
    proc = yes
    diskspace = yes
    cgroups = yes
    tc = no
    idlejitter = no

[health]
    enabled = yes

[registry]
    enabled = no
EOF

# Set proper permissions
chown netdata:netdata /etc/netdata/netdata.conf
chmod 644 /etc/netdata/netdata.conf

# Ensure Netdata service is properly configured
echo "Configuring systemd service..."

# Create service override directory
mkdir -p /etc/systemd/system/netdata.service.d

# Create override configuration
cat > /etc/systemd/system/netdata.service.d/override.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=5s
EOF

# Reload systemd
systemctl daemon-reload

# Restart Netdata with new configuration
echo "Restarting Netdata..."
systemctl restart netdata

# Enable Netdata to start on boot
systemctl enable netdata >/dev/null 2>&1

# Configure firewall
echo "Configuring firewall..."
ufw allow 19999/tcp >/dev/null 2>&1

# Wait for service to fully start
sleep 3

# Check if service is running
if systemctl is-active --quiet netdata; then
    echo "✓ Netdata installed and running successfully!"
else
    echo "⚠ Warning: Netdata service may not be running properly."
    systemctl status netdata --no-pager
fi

# Get Netdata version
NETDATA_VERSION=$(netdata -V 2>/dev/null | head -n 1 || echo "Unknown")

echo
echo "=========================================================="
echo "Netdata System Monitoring Setup Complete!"
echo
echo "Service Information:"
echo "  - Status: $(systemctl is-active netdata)"
echo "  - Version: ${NETDATA_VERSION}"
echo "  - Port: 19999"
echo "  - Config: /etc/netdata/netdata.conf"
echo
echo "Access Instructions:"
echo "1. Configure port forwarding in VirtualBox:"
echo "   Settings → Network → Advanced → Port Forwarding"
echo "   Add rule: Host Port 19999 → Guest Port 19999"
echo
echo "2. Access Netdata in your browser:"
echo "   http://127.0.0.1:19999"
echo
echo "Features:"
echo "  ✓ Real-time system metrics (CPU, RAM, Disk, Network)"
echo "  ✓ Per-second data collection"
echo "  ✓ Interactive charts and graphs"
echo "  ✓ Performance analysis tools"
echo "  ✓ Health monitoring and alerts"
echo "  ✓ Process monitoring"
echo "  ✓ Service monitoring"
echo
echo "Monitored Metrics Include:"
echo "  - CPU usage and frequency"
echo "  - Memory and swap usage"
echo "  - Disk I/O and space"
echo "  - Network traffic"
echo "  - System processes"
echo "  - System load"
echo "  - Temperature sensors (if available)"
echo
echo "Useful Commands:"
echo "  - Check status: systemctl status netdata"
echo "  - Stop service: systemctl stop netdata"
echo "  - Start service: systemctl start netdata"
echo "  - Restart service: systemctl restart netdata"
echo "  - View logs: journalctl -u netdata -f"
echo "  - Edit config: nano /etc/netdata/netdata.conf"
echo "  - After config changes: systemctl restart netdata"
echo
echo "Tips:"
echo "  - No login required - dashboard is open by default"
echo "  - Click on any chart to zoom in"
echo "  - Use the menu on the right for different sections"
echo "  - Hover over charts for detailed information"
echo "=========================================================="
