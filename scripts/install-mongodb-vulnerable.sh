#!/bin/bash
# scripts/install-mongodb-vulnerable.sh
# This script creates an intentionally vulnerable MongoDB setup for the dev environment

set -e

echo "=== Installing VULNERABLE MongoDB 3.2 for Dev Environment ==="
echo "=== THIS IS INTENTIONALLY INSECURE FOR DEMONSTRATION ==="

# Get the GCS bucket name from metadata
GCS_BUCKET_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcs-bucket" -H "Metadata-Flavor: Google" || echo "clgcporg10-173-dev-mongodb-backups")

# Update package list (Ubuntu 16.04)
sudo apt-get update

# Install dependencies
sudo apt-get install -y wget curl software-properties-common

# Install MongoDB 3.2 (outdated version with known vulnerabilities)
echo "Installing MongoDB 3.2 (EOL version with 47+ CVEs)..."
wget -qO - https://www.mongodb.org/static/pgp/server-3.2.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.2.list
sudo apt-get update
sudo apt-get install -y --allow-unauthenticated  mongodb-org=3.2.22 mongodb-org-server=3.2.22 mongodb-org-shell=3.2.22 mongodb-org-mongos=3.2.22 mongodb-org-tools=3.2.22

# VULNERABILITY 1: Weak MongoDB configuration (old format for 3.2 compatibility)
echo "=== Configuring MongoDB with multiple vulnerabilities ==="
cat <<EOF | sudo tee /etc/mongod.conf
# mongod.conf - VULNERABLE CONFIGURATION (v3.2 format)

# Where to store data
dbpath=/var/lib/mongodb

# Where to log
logpath=/var/log/mongodb/mongod.log
logappend=true

# Network interfaces - VULNERABILITY: Bind to all interfaces
bind_ip=0.0.0.0
port=27017

# Enable/Disable security
auth=false

# Enable journaling
journal=true

# Set oplog size
oplogSize=1024

# Don't fork - let systemd manage the process
EOF

# Ensure MongoDB directories exist with correct permissions
sudo mkdir -p /var/lib/mongodb /var/log/mongodb /var/run/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb /var/run/mongodb
sudo chmod 755 /var/lib/mongodb /var/log/mongodb /var/run/mongodb

# Start MongoDB without auth first
sudo systemctl stop mongod || true
sudo systemctl daemon-reload
sudo systemctl start mongod
sudo systemctl enable mongod

# Wait for MongoDB to start and check status
sleep 15
echo "Checking MongoDB status..."
sudo systemctl status mongod
echo "Checking MongoDB logs..."
sudo tail -n 50 /var/log/mongodb/mongod.log

# If MongoDB failed to start, try to fix common issues
if ! sudo systemctl is-active --quiet mongod; then
  echo "MongoDB failed to start. Attempting to fix..."
  
  # Create necessary directories
  sudo mkdir -p /var/lib/mongodb /var/log/mongodb /var/run/mongodb
  sudo chown mongodb:mongodb /var/lib/mongodb /var/log/mongodb /var/run/mongodb
  sudo chmod 755 /var/lib/mongodb /var/log/mongodb /var/run/mongodb
  
  # Try minimal configuration for MongoDB 3.2
  cat <<'FIX_EOF' | sudo tee /etc/mongod.conf
# Minimal MongoDB 3.2 configuration
dbpath=/var/lib/mongodb
logpath=/var/log/mongodb/mongod.log
logappend=true
bind_ip=0.0.0.0
port=27017
auth=false
journal=true
fork=true
FIX_EOF
  
  # Remove fork option to work better with systemd
  sed -i '/fork=true/d' /etc/mongod.conf
  
  # Try to start mongod directly to see detailed error
  echo "Attempting to start mongod directly..."
  sudo -u mongodb mongod --config /etc/mongod.conf --fork 2>&1 | head -20

  # Restart MongoDB
  sudo systemctl daemon-reload
  sudo systemctl restart mongod
  sleep 10
  
  echo "Checking MongoDB status after fix..."
  sudo systemctl status mongod
fi

# Wait for MongoDB to accept connections
for i in {1..30}; do
  if mongo --eval "print('MongoDB is ready')" > /dev/null 2>&1; then
    echo "MongoDB is ready!"
    break
  fi
  echo "Waiting for MongoDB to start... attempt $i/30"
  sleep 2
done

# Create admin user with weak password (or update if exists)
echo "Creating/updating admin users with weak passwords..."
mongo <<EOF
use admin
try {
  db.createUser({
    user: "admin",
    pwd: "insecurepass",  // VULNERABILITY: Weak password
    roles: [
      { role: "root", db: "admin" },  // VULNERABILITY: Root access
      { role: "readWriteAnyDatabase", db: "admin" },
      { role: "dbAdminAnyDatabase", db: "admin" },
      { role: "userAdminAnyDatabase", db: "admin" }
    ]
  })
  print("Admin user created successfully")
} catch (e) {
  if (e.code == 51003) {
    print("Admin user already exists - skipping")
  } else {
    throw e
  }
}

use wizknowledge
try {
  db.createUser({
    user: "wizapp",
    pwd: "password123",  // VULNERABILITY: Weak password
    roles: [
      { role: "readWrite", db: "wizknowledge" }
    ]
  })
  print("Wizapp user created successfully")
} catch (e) {
  if (e.code == 51003) {
    print("Wizapp user already exists - skipping")
  } else {
    throw e
  }
}
EOF

# Enable authentication with weak config
sudo sed -i 's/authorization: disabled/authorization: enabled/' /etc/mongod.conf
sudo systemctl restart mongod

# VULNERABILITY 2: Install vulnerable web interface (Mongo Express)
echo "Installing Mongo Express (vulnerable web interface)..."
# Use Node.js 16 (still old but works) to avoid deprecation delays
curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash - 2>/dev/null || curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get install -y nodejs npm
sudo npm install -g mongo-express@0.54.0  # Old version with vulnerabilities

# Configure mongo-express with hardcoded credentials
cat <<'EOF' | sudo tee /usr/local/etc/mongo-express-config.js
module.exports = {
  mongodb: {
    server: 'localhost',
    port: 27017,
    
    // VULNERABILITY: Hardcoded credentials
    admin: true,
    auth: [
      {
        database: 'admin',
        username: 'admin',
        password: 'insecurepass'
      }
    ],
    
    adminUsername: 'admin',
    adminPassword: 'insecurepass',
    
    whitelist: [],
    blacklist: []
  },
  
  site: {
    baseUrl: '/',
    cookieKeyName: 'mongo-express',
    cookieSecret: 'cookiesecret123',  // VULNERABILITY: Weak secret
    host: '0.0.0.0',  // VULNERABILITY: Listening on all interfaces
    port: 8081,
    requestSizeLimit: '50mb',
    sessionSecret: 'sessionsecret123',  // VULNERABILITY: Weak secret
    sslEnabled: false,  // VULNERABILITY: No SSL
  },
  
  // VULNERABILITY: Basic auth with weak credentials
  useBasicAuth: true,
  basicAuth: {
    username: 'admin',
    password: 'admin123'
  },
  
  options: {
    console: true,
    documentsPerPage: 10,
    editorTheme: 'rubyblue',
    logger: { skip: function() { return false; } },
    readOnly: false
  }
};
EOF

# Create systemd service for mongo-express
cat <<EOF | sudo tee /etc/systemd/system/mongo-express.service
[Unit]
Description=Mongo Express Web Interface
After=network.target mongod.service

[Service]
Type=simple
User=root
Environment="ME_CONFIG_MONGODB_SERVER=localhost"
Environment="ME_CONFIG_MONGODB_PORT=27017"
Environment="ME_CONFIG_MONGODB_ADMINUSERNAME=admin"
Environment="ME_CONFIG_MONGODB_ADMINPASSWORD=insecurepass"
Environment="ME_CONFIG_BASICAUTH_USERNAME=admin"
Environment="ME_CONFIG_BASICAUTH_PASSWORD=admin123"
ExecStart=/usr/bin/mongo-express -c /usr/local/etc/mongo-express-config.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start mongo-express
sudo systemctl enable mongo-express

# VULNERABILITY 3: Create backup script with plain text credentials
echo "Creating vulnerable backup script..."
cat <<'BACKUP_SCRIPT' | sudo tee /usr/local/bin/backup-mongodb.sh
#!/bin/bash

# VULNERABILITY: Hardcoded credentials in script
MONGO_URI="mongodb://admin:insecurepass@localhost:27017"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mongodb-backup-${TIMESTAMP}"
BUCKET_NAME="clgcporg10-173-dev-mongodb-backups"

echo "[$(date)] Starting MongoDB backup..."

# Create backup (VULNERABILITY: No encryption)
mongodump --uri="${MONGO_URI}" \
  --archive="/tmp/${BACKUP_NAME}.archive" \
  --gzip

# VULNERABILITY: Backup contains sensitive data unencrypted
# Upload to GCS (using overly permissive service account)
gsutil cp "/tmp/${BACKUP_NAME}.archive" "gs://${BUCKET_NAME}/" 2>/dev/null || {
  echo "Failed to upload to GCS, keeping local backup"
}

# VULNERABILITY: Predictable backup names
# VULNERABILITY: No secure deletion
rm -f "/tmp/${BACKUP_NAME}.archive"

echo "[$(date)] Backup ${BACKUP_NAME} completed" >> /var/log/mongodb-backup.log
BACKUP_SCRIPT

sudo chmod +x /usr/local/bin/backup-mongodb.sh

# VULNERABILITY 4: Set up cron job running as root
echo "Setting up automated backups (running as root)..."
echo "*/30 * * * * root /usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1" | sudo tee /etc/cron.d/mongodb-backup

# VULNERABILITY 5: Weak file permissions
echo "Setting weak file permissions (intentional vulnerabilities)..."
sudo chmod 777 /var/lib/mongodb  # World-writable data directory!
sudo chmod 666 /etc/mongod.conf  # World-readable config with passwords!
sudo chmod 755 /usr/local/bin/backup-mongodb.sh  # Backup script readable by all

# VULNERABILITY 6: Disable firewall
echo "Disabling firewall (vulnerability)..."
sudo ufw disable 2>/dev/null || true

# VULNERABILITY 7: Create additional vulnerable users (or skip if they exist)
mongo --authenticationDatabase admin -u admin -p insecurepass <<EOF
use admin
try {
  db.createUser({
    user: "backup",
    pwd: "backup",  // VULNERABILITY: Username same as password
    roles: [ { role: "backup", db: "admin" } ]
  })
  print("Backup user created")
} catch (e) { print("Backup user exists - skipping") }

try {
  db.createUser({
    user: "monitor",
    pwd: "monitor",  // VULNERABILITY: Username same as password
    roles: [ { role: "clusterMonitor", db: "admin" } ]
  })
  print("Monitor user created")
} catch (e) { print("Monitor user exists - skipping") }
EOF

# VULNERABILITY 8: Enable MongoDB HTTP interface (deprecated and vulnerable)
sudo sed -i '/net:/a\  http:\n    enabled: true\n    port: 28017' /etc/mongod.conf
sudo systemctl restart mongod

# VULNERABILITY 9: Install outdated packages with known vulnerabilities
echo "Installing additional vulnerable packages..."
sudo apt-get install -y \
  openssh-server=1:7.2p2-4ubuntu2.10 \
  openssl=1.0.2g-1ubuntu4.20 \
  curl=7.47.0-1ubuntu2.19 || true

# VULNERABILITY 10: Weak SSH configuration
echo "Configuring weak SSH settings..."
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
echo "MaxAuthTries 100" | sudo tee -a /etc/ssh/sshd_config
echo "MaxSessions 100" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh

# Create test data
echo "Creating test data in MongoDB..."
mongo --authenticationDatabase admin -u admin -p insecurepass <<EOF
use wizknowledge
db.test_data.insert([
  { type: "sensitive", data: "SSN: 123-45-6789", classification: "PII" },
  { type: "sensitive", data: "Credit Card: 4111-1111-1111-1111", classification: "PCI" },
  { type: "sensitive", data: "API Key: sk_live_abcdef123456", classification: "SECRET" }
])
EOF

# Output summary
echo ""
echo "==================================================="
echo "   VULNERABLE MongoDB Setup Complete (Dev Only)    "
echo "==================================================="
echo ""
echo "Vulnerabilities introduced:"
echo "1. MongoDB 3.2.22 (EOL with 47+ CVEs)"
echo "2. Weak passwords (admin/insecurepass)"
echo "3. MongoDB bound to 0.0.0.0:27017"
echo "4. Mongo Express on http://0.0.0.0:8081 (admin/admin123)"
echo "5. World-writable data directory (777)"
echo "6. Plain text credentials in config files"
echo "7. Unencrypted backups to public GCS bucket"
echo "8. SSH root login enabled"
echo "9. Firewall disabled"
echo "10. Outdated packages with known CVEs"
echo "11. MongoDB HTTP interface enabled on :28017"
echo "12. Test data with PII/PCI information"
echo ""
echo "Access points:"
echo "- MongoDB: mongodb://admin:insecurepass@$(curl -s ifconfig.me):27017"
echo "- Mongo Express: http://$(curl -s ifconfig.me):8081"
echo "- MongoDB HTTP: http://$(curl -s ifconfig.me):28017"
echo "- SSH: ssh ubuntu@$(curl -s ifconfig.me)"
echo ""
echo "GCS Bucket: gs://clgcporg10-173-dev-mongodb-backups/"
echo "==================================================="

# Run initial backup
echo "Running initial backup..."
sudo /usr/local/bin/backup-mongodb.sh

# Log completion
echo "[$(date)] Vulnerable MongoDB installation completed" | sudo tee -a /var/log/setup.log