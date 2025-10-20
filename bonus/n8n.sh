#!/bin/bash
# ==========================================================
#   n8n Setup Script
#   Installs and configures n8n Workflow Automation Tool
# ==========================================================

set -e

echo "=== Installing n8n Workflow Automation ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

# Install required dependencies
echo "Installing dependencies..."
apt update -y >/dev/null 2>&1
apt install -y curl gnupg ca-certificates >/dev/null 2>&1

# Install Node.js (n8n requires Node.js 18.x or later)
echo "Installing Node.js..."

# Remove old nodejs if present
apt remove -y nodejs 2>/dev/null || true

# Add NodeSource repository for Node.js 18.x
curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1

# Install Node.js
apt install -y nodejs >/dev/null 2>&1

# Verify installation
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
echo "Node.js ${NODE_VERSION} and npm ${NPM_VERSION} installed"

# Create n8n user if doesn't exist
if ! id -u n8n >/dev/null 2>&1; then
    echo "Creating n8n system user..."
    useradd -r -s /bin/bash -d /opt/n8n -m n8n
fi

# Create directory structure
echo "Setting up directories..."
mkdir -p /opt/n8n
mkdir -p /var/lib/n8n
mkdir -p /var/log/n8n

# Set proper ownership
chown -R n8n:n8n /opt/n8n
chown -R n8n:n8n /var/lib/n8n
chown -R n8n:n8n /var/log/n8n

# Install n8n globally as n8n user
echo "Installing n8n (this may take a few minutes)..."
sudo -u n8n npm install -g n8n 2>&1 | grep -v "npm WARN" || true

# Verify n8n installation
N8N_PATH=$(sudo -u n8n which n8n 2>/dev/null || echo "/opt/n8n/.npm-global/bin/n8n")

# Create environment file for n8n configuration
echo "Creating configuration..."
cat > /etc/n8n/config.env <<'EOF'
# n8n Configuration
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=admin
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:5678/
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=file
N8N_LOG_FILE_LOCATION=/var/log/n8n/n8n.log
GENERIC_TIMEZONE=UTC
N8N_USER_FOLDER=/var/lib/n8n
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
EOF

chown n8n:n8n /etc/n8n/config.env
chmod 600 /etc/n8n/config.env

# Create systemd service file
echo "Creating systemd service..."
cat > /etc/systemd/system/n8n.service <<'EOF'
[Unit]
Description=n8n - Workflow Automation Tool
After=network.target

[Service]
Type=simple
User=n8n
Group=n8n
WorkingDirectory=/opt/n8n
EnvironmentFile=/etc/n8n/config.env
ExecStart=/usr/bin/node /usr/bin/n8n start
Restart=on-failure
RestartSec=5s

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/n8n /var/log/n8n

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Create config directory
mkdir -p /etc/n8n

# Reload systemd and enable service
echo "Enabling and starting n8n service..."
systemctl daemon-reload
systemctl enable n8n >/dev/null 2>&1
systemctl start n8n

# Configure firewall
echo "Configuring firewall..."
ufw allow 5678/tcp >/dev/null 2>&1

# Wait for service to start
echo "Waiting for n8n to start..."
sleep 5

# Check if service is running
if systemctl is-active --quiet n8n; then
    echo "✓ n8n installed and running successfully!"
else
    echo "⚠ Warning: n8n service may not be running properly."
    systemctl status n8n --no-pager
fi

echo
echo "=========================================================="
echo "n8n Workflow Automation Setup Complete!"
echo
echo "Service Information:"
echo "  - Status: $(systemctl is-active n8n)"
echo "  - Port: 5678"
echo "  - Data Directory: /var/lib/n8n"
echo "  - Log File: /var/log/n8n/n8n.log"
echo
echo "Access Instructions:"
echo "1. Configure port forwarding in VirtualBox:"
echo "   Settings → Network → Advanced → Port Forwarding"
echo "   Add rule: Host Port 5678 → Guest Port 5678"
echo
echo "2. Access n8n in your browser:"
echo "   http://127.0.0.1:5678"
echo
echo "3. Default Login Credentials:"
echo "   Username: admin"
echo "   Password: admin"
echo
echo "⚠ IMPORTANT: Change the default credentials!"
echo "   Edit /etc/n8n/config.env and modify:"
echo "   - N8N_BASIC_AUTH_USER"
echo "   - N8N_BASIC_AUTH_PASSWORD"
echo "   Then restart: systemctl restart n8n"
echo
echo "Features:"
echo "  - 200+ integration nodes (Google, Slack, GitHub, etc.)"
echo "  - Visual workflow editor"
echo "  - Webhook support"
echo "  - Scheduled executions"
echo "  - Conditional logic and data transformation"
echo
echo "Useful Commands:"
echo "  - Check status: systemctl status n8n"
echo "  - Stop service: systemctl stop n8n"
echo "  - Start service: systemctl start n8n"
echo "  - Restart service: systemctl restart n8n"
echo "  - View logs: journalctl -u n8n -f"
echo "  - View log file: tail -f /var/log/n8n/n8n.log"
echo
echo "Configuration:"
echo "  - Edit config: nano /etc/n8n/config.env"
echo "  - After editing, restart: systemctl restart n8n"
echo "=========================================================="
