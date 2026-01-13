#!/bin/bash
#==============================================================================
# Script 08: Setup MongoDB
#==============================================================================
# Installs and configures MongoDB on the dedicated EC2 instance.
# Sets up authentication, creates application user, and installs exporter.
#
# Usage: ./08-setup-mongodb.sh
#
# Mirrors: ansible/playbooks/08-setup-mongodb.yml
#==============================================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helpers
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/helpers.sh"

#------------------------------------------------------------------------------
# MongoDB Installation Script
#------------------------------------------------------------------------------
generate_mongodb_script() {
    local mongodb_version="$1"
    local mongodb_port="$2"
    local mongodb_data_dir="$3"
    local mongodb_log_dir="$4"
    local mongodb_admin_user="$5"
    local mongodb_admin_password="$6"
    local mongodb_app_database="$7"
    local mongodb_app_user="$8"
    local mongodb_app_password="$9"
    local mongodb_exporter_version="${10}"
    local mongodb_exporter_user="${11}"
    local mongodb_exporter_password="${12}"
    
    cat << EOF
#!/bin/bash
set -e

MONGODB_VERSION="$mongodb_version"
MONGODB_PORT="$mongodb_port"
MONGODB_DATA_DIR="$mongodb_data_dir"
MONGODB_LOG_DIR="$mongodb_log_dir"
MONGODB_ADMIN_USER="$mongodb_admin_user"
MONGODB_ADMIN_PASSWORD="$mongodb_admin_password"
MONGODB_APP_DATABASE="$mongodb_app_database"
MONGODB_APP_USER="$mongodb_app_user"
MONGODB_APP_PASSWORD="$mongodb_app_password"
MONGODB_EXPORTER_VERSION="$mongodb_exporter_version"
MONGODB_EXPORTER_USER="$mongodb_exporter_user"
MONGODB_EXPORTER_PASSWORD="$mongodb_exporter_password"

#------------------------------------------------------------------------------
# Mount EBS volume for MongoDB data
#------------------------------------------------------------------------------
echo "==> Setting up data directory..."

mkdir -p "\$MONGODB_DATA_DIR"

# Check if EBS volume is attached
if [ -e /dev/xvdf ]; then
    echo "EBS volume detected at /dev/xvdf"
    
    # Check if already formatted
    if ! blkid /dev/xvdf &>/dev/null; then
        echo "Formatting EBS volume..."
        mkfs.xfs /dev/xvdf
    fi
    
    # Mount if not already mounted
    if ! mountpoint -q "\$MONGODB_DATA_DIR"; then
        echo "Mounting EBS volume..."
        mount /dev/xvdf "\$MONGODB_DATA_DIR"
        
        # Add to fstab for persistence
        if ! grep -q "/dev/xvdf" /etc/fstab; then
            echo "/dev/xvdf \$MONGODB_DATA_DIR xfs defaults,nofail 0 2" >> /etc/fstab
        fi
    fi
else
    echo "No EBS volume at /dev/xvdf, using local storage"
fi

#------------------------------------------------------------------------------
# Install MongoDB
#------------------------------------------------------------------------------
echo "==> Installing MongoDB..."

# Import MongoDB GPG key
curl -fsSL "https://pgp.mongodb.com/server-\${MONGODB_VERSION}.asc" -o /etc/apt/trusted.gpg.d/mongodb-server-\${MONGODB_VERSION}.asc

# Add MongoDB repository
UBUNTU_CODENAME=\$(lsb_release -cs)
echo "deb [ arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/mongodb-server-\${MONGODB_VERSION}.asc ] https://repo.mongodb.org/apt/ubuntu \${UBUNTU_CODENAME}/mongodb-org/\${MONGODB_VERSION} multiverse" > /etc/apt/sources.list.d/mongodb-org-\${MONGODB_VERSION}.list

# Update and install
apt-get update
apt-get install -y mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-tools

#------------------------------------------------------------------------------
# Configure MongoDB
#------------------------------------------------------------------------------
echo "==> Configuring MongoDB..."

# Create directories
mkdir -p "\$MONGODB_DATA_DIR"
mkdir -p "\$MONGODB_LOG_DIR"

# Set ownership
chown -R mongodb:mongodb "\$MONGODB_DATA_DIR"
chown -R mongodb:mongodb "\$MONGODB_LOG_DIR"

# Create MongoDB configuration
cat > /etc/mongod.conf << MONGOCONF
# MongoDB Configuration
storage:
  dbPath: \$MONGODB_DATA_DIR
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1

systemLog:
  destination: file
  logAppend: true
  path: \$MONGODB_LOG_DIR/mongod.log
  logRotate: reopen

net:
  port: \$MONGODB_PORT
  bindIp: 0.0.0.0
  maxIncomingConnections: 1000

processManagement:
  timeZoneInfo: /usr/share/zoneinfo
  fork: false

security:
  authorization: disabled

operationProfiling:
  slowOpThresholdMs: 100
  mode: slowOp
MONGOCONF

echo "==> Starting MongoDB (without auth for initial setup)..."
systemctl daemon-reload
systemctl enable mongod
systemctl restart mongod

# Wait for MongoDB to be ready
# Wait for MongoDB to be ready
echo "Waiting for MongoDB to start..."
START_SUCCESS=false
for i in {1..30}; do
    if mongosh --quiet --eval "db.runCommand({ping:1})" &>/dev/null; then
        echo "MongoDB is ready!"
        START_SUCCESS=true
        break
    fi
    echo "Waiting for MongoDB... (\$i/30)"
    sleep 2
done

if [ "\$START_SUCCESS" != "true" ]; then
    echo "ERROR: MongoDB failed to start."
    systemctl status mongod --no-pager
    echo "--- MongoDB Logs ---"
    cat \$MONGODB_LOG_DIR/mongod.log
    exit 1
fi

#------------------------------------------------------------------------------
# Create users
#------------------------------------------------------------------------------
echo "==> Creating MongoDB users..."

# Check if admin user exists
ADMIN_EXISTS=\$(mongosh --quiet --eval "db.getSiblingDB('admin').getUser('\$MONGODB_ADMIN_USER')" 2>/dev/null || echo "null")

if [[ "\$ADMIN_EXISTS" == "null" ]] || [[ -z "\$ADMIN_EXISTS" ]]; then
    echo "Creating admin user..."
    mongosh admin --eval "
        db.createUser({
            user: '\$MONGODB_ADMIN_USER',
            pwd: '\$MONGODB_ADMIN_PASSWORD',
            roles: [
                { role: 'userAdminAnyDatabase', db: 'admin' },
                { role: 'readWriteAnyDatabase', db: 'admin' },
                { role: 'dbAdminAnyDatabase', db: 'admin' },
                { role: 'clusterAdmin', db: 'admin' }
            ]
        })
    "
    
    echo "Creating application user..."
    mongosh admin -u "\$MONGODB_ADMIN_USER" -p "\$MONGODB_ADMIN_PASSWORD" --eval "
        db.getSiblingDB('\$MONGODB_APP_DATABASE').createUser({
            user: '\$MONGODB_APP_USER',
            pwd: '\$MONGODB_APP_PASSWORD',
            roles: [
                { role: 'readWrite', db: '\$MONGODB_APP_DATABASE' }
            ]
        })
    "
    
    echo "Creating exporter user..."
    mongosh admin -u "\$MONGODB_ADMIN_USER" -p "\$MONGODB_ADMIN_PASSWORD" --eval "
        db.createUser({
            user: '\$MONGODB_EXPORTER_USER',
            pwd: '\$MONGODB_EXPORTER_PASSWORD',
            roles: [
                { role: 'clusterMonitor', db: 'admin' },
                { role: 'read', db: 'local' }
            ]
        })
    "
else
    echo "Admin user already exists, skipping user creation"
fi

#------------------------------------------------------------------------------
# Enable authentication
#------------------------------------------------------------------------------
echo "==> Enabling MongoDB authentication..."

cat > /etc/mongod.conf << MONGOCONF
# MongoDB Configuration
storage:
  dbPath: \$MONGODB_DATA_DIR
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1

systemLog:
  destination: file
  logAppend: true
  path: \$MONGODB_LOG_DIR/mongod.log
  logRotate: reopen

net:
  port: \$MONGODB_PORT
  bindIp: 0.0.0.0
  maxIncomingConnections: 1000

processManagement:
  timeZoneInfo: /usr/share/zoneinfo
  fork: false

security:
  authorization: enabled

operationProfiling:
  slowOpThresholdMs: 100
  mode: slowOp
MONGOCONF

systemctl restart mongod

# Wait for MongoDB to restart
echo "Waiting for MongoDB to restart with auth enabled..."
sleep 5

#------------------------------------------------------------------------------
# Install MongoDB Exporter
#------------------------------------------------------------------------------
echo "==> Installing MongoDB Exporter..."

cd /tmp
curl -fsSL "https://github.com/percona/mongodb_exporter/releases/download/v\${MONGODB_EXPORTER_VERSION}/mongodb_exporter-\${MONGODB_EXPORTER_VERSION}.linux-amd64.tar.gz" -o mongodb_exporter.tar.gz
tar xzf mongodb_exporter.tar.gz
cp "mongodb_exporter-\${MONGODB_EXPORTER_VERSION}.linux-amd64/mongodb_exporter" /usr/local/bin/
chmod 755 /usr/local/bin/mongodb_exporter

# Create systemd service for exporter
cat > /etc/systemd/system/mongodb_exporter.service << EXPORTERSVC
[Unit]
Description=MongoDB Exporter for Prometheus
Documentation=https://github.com/percona/mongodb_exporter
After=network-online.target mongod.service
Wants=network-online.target

[Service]
Type=simple
User=mongodb
Group=mongodb

Environment="MONGODB_URI=mongodb://\$MONGODB_EXPORTER_USER:\$MONGODB_EXPORTER_PASSWORD@localhost:\$MONGODB_PORT/admin"

ExecStart=/usr/local/bin/mongodb_exporter \\
    --web.listen-address=:9216 \\
    --collect-all \\
    --discovering-mode

Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EXPORTERSVC

systemctl daemon-reload
systemctl enable mongodb_exporter
systemctl start mongodb_exporter

#------------------------------------------------------------------------------
# Display status
#------------------------------------------------------------------------------
echo ""
echo "==> MongoDB status:"
systemctl status mongod --no-pager || true

echo ""
echo "=============================================="
echo "MongoDB Setup Complete!"
echo "=============================================="
echo ""
PRIVATE_IP=\$(hostname -I | awk '{print \$1}')
echo "Connection String: mongodb://\$MONGODB_APP_USER:\$MONGODB_APP_PASSWORD@\$PRIVATE_IP:\$MONGODB_PORT/\$MONGODB_APP_DATABASE"
echo ""
echo "Admin User: \$MONGODB_ADMIN_USER"
echo "App User: \$MONGODB_APP_USER"
echo "Database: \$MONGODB_APP_DATABASE"
echo ""
echo "MongoDB Exporter running on port 9216"
EOF
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    log_header "Setting up MongoDB"
    
    # Validate required variables
    if [ -z "$MONGODB_IP" ]; then
        log_warning "MONGODB_IP not set. Skipping MongoDB setup."
        log_info "If you have a MongoDB server, set MONGODB_IP and run this script again."
        exit 0
    fi
    
    check_required_vars BASTION_IP MONGODB_IP || exit 1
    validate_ssh_key || exit 1
    
    step_progress 1 2 "Installing and configuring MongoDB on $MONGODB_IP"
    
    MONGODB_SCRIPT=$(generate_mongodb_script \
        "$MONGODB_VERSION" \
        "$MONGODB_PORT" \
        "$MONGODB_DATA_DIR" \
        "$MONGODB_LOG_DIR" \
        "$MONGODB_ADMIN_USER" \
        "$MONGODB_ADMIN_PASSWORD" \
        "$MONGODB_APP_DATABASE" \
        "$MONGODB_APP_USER" \
        "$MONGODB_APP_PASSWORD" \
        "$MONGODB_EXPORTER_VERSION" \
        "$MONGODB_EXPORTER_USER" \
        "$MONGODB_EXPORTER_PASSWORD")
    
    remote_script_sudo "$MONGODB_IP" "$MONGODB_SCRIPT"
    
    log_success "MongoDB installed and configured"
    
    step_progress 2 2 "Verifying MongoDB installation"
    
    # Get connection info
    ssh_exec "$MONGODB_IP" "systemctl status mongod --no-pager" || true
    
    show_completion "MongoDB Setup"
    
    log_info "MongoDB is now running on $MONGODB_IP:$MONGODB_PORT"
    log_info ""
    log_info "Connection string for your application:"
    log_info "mongodb://$MONGODB_APP_USER:$MONGODB_APP_PASSWORD@$MONGODB_IP:$MONGODB_PORT/$MONGODB_APP_DATABASE"
    log_info ""
    log_info "MongoDB Exporter is running on port 9216 for Prometheus scraping."
}

main "$@"
