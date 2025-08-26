#!/bin/bash
# scripts/install-mongodb-vulnerable.sh
# MongoDB 3.2 vulnerable installation for security testing

set -e

# Setup verbose logging
LOG_FILE="/mongodb-vulnerable-install-$(date +%Y%m%d-%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1
set -x  # Enable command tracing

echo "========================================="
echo "MongoDB 3.2 Vulnerable Installation"
echo "Log file: $LOG_FILE"
echo "Started: $(date)"
echo "========================================="

# Get GCS bucket name
echo "[$(date)] Getting GCS bucket name..."
GCS_BUCKET_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcs-bucket" -H "Metadata-Flavor: Google" || echo "clgcporg10-173-dev-mongodb-backups")
echo "[$(date)] Using bucket: $GCS_BUCKET_NAME"

# System update
echo "[$(date)] Updating system packages..."
sudo apt-get update

echo "[$(date)] Installing dependencies..."
sudo apt-get install -y wget curl software-properties-common

# Install MongoDB 3.2
echo "[$(date)] Installing MongoDB 3.2 (intentionally outdated)..."
wget -qO - https://www.mongodb.org/static/pgp/server-3.2.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.2.list
sudo apt-get update
sudo apt-get install -y --allow-unauthenticated mongodb-org=3.2.22 mongodb-org-server=3.2.22 mongodb-org-shell=3.2.22 mongodb-org-mongos=3.2.22 mongodb-org-tools=3.2.22

# Configure MongoDB (vulnerable settings)
echo "[$(date)] Configuring MongoDB with vulnerable settings..."
cat <<EOF | sudo tee /etc/mongod.conf
# MongoDB 3.2 Configuration (VULNERABLE)
dbpath=/var/lib/mongodb
logpath=/var/log/mongodb/mongod.log
logappend=true
bind_ip=0.0.0.0
port=27017
auth=false
journal=true
oplogSize=1024
EOF

# Setup directories
echo "[$(date)] Setting up MongoDB directories..."
sudo mkdir -p /var/lib/mongodb /var/log/mongodb /var/run/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb /var/run/mongodb
sudo chmod 755 /var/lib/mongodb /var/log/mongodb /var/run/mongodb

# Start MongoDB
echo "[$(date)] Starting MongoDB service..."
sudo systemctl stop mongod || true
sudo systemctl daemon-reload
sudo systemctl start mongod
sudo systemctl enable mongod

# Wait for MongoDB
echo "[$(date)] Waiting for MongoDB to be ready..."
for i in {1..30}; do
  if mongo --eval "print('MongoDB is ready')" > /dev/null 2>&1; then
    echo "[$(date)] MongoDB is ready!"
    break
  fi
  echo "[$(date)] Waiting... attempt $i/30"
  sleep 2
done

# Create users with weak passwords
echo "[$(date)] Creating users with weak passwords..."
mongo <<EOF
use admin
try {
  db.createUser({
    user: "admin",
    pwd: "insecurepass",
    roles: ["root", "readWriteAnyDatabase", "dbAdminAnyDatabase", "userAdminAnyDatabase"]
  })
  print("[$(date)] Admin user created")
} catch (e) {
  print("[$(date)] Admin user already exists")
}

use wizknowledge
try {
  db.createUser({
    user: "wizapp",
    pwd: "password123",
    roles: [{ role: "readWrite", db: "wizknowledge" }]
  })
  print("[$(date)] Wizapp user created")
} catch (e) {
  print("[$(date)] Wizapp user already exists")
}
EOF

# Enable authentication
echo "[$(date)] Enabling authentication..."
sudo sed -i 's/auth=false/auth=true/' /etc/mongod.conf
sudo systemctl restart mongod
sleep 10

# Install Mongo Express (vulnerable web interface)
echo "[$(date)] Installing Mongo Express..."
curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash - 2>/dev/null
sudo apt-get install -y nodejs npm
sudo npm install -g mongo-express@0.54.0

# Configure Mongo Express
echo "[$(date)] Configuring Mongo Express..."
cat <<'EOF' | sudo tee /usr/local/etc/mongo-express-config.js
module.exports = {
  mongodb: {
    server: 'localhost',
    port: 27017,
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
    cookieSecret: 'cookiesecret123',
    host: '0.0.0.0',
    port: 8081,
    requestSizeLimit: '50mb',
    sessionSecret: 'sessionsecret123',
    sslEnabled: false,
  },
  useBasicAuth: true,
  basicAuth: {
    username: 'admin',
    password: 'admin123'
  },
  options: {
    console: true,
    documentsPerPage: 10,
    editorTheme: 'rubyblue',
    readOnly: false
  }
};
EOF

# Create Mongo Express service
echo "[$(date)] Creating Mongo Express service..."
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

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start mongo-express
sudo systemctl enable mongo-express

# Create backup script
echo "[$(date)] Creating vulnerable backup script..."
cat <<'SCRIPT' | sudo tee /usr/local/bin/backup-mongodb.sh
#!/bin/bash
MONGO_URI="mongodb://admin:insecurepass@localhost:27017"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mongodb-backup-${TIMESTAMP}"
BUCKET_NAME="clgcporg10-173-dev-mongodb-backups"

echo "[$(date)] Starting backup..."
mongodump --uri="${MONGO_URI}" --archive="/tmp/${BACKUP_NAME}.archive" --gzip
gsutil cp "/tmp/${BACKUP_NAME}.archive" "gs://${BUCKET_NAME}/" 2>/dev/null || echo "GCS upload failed"
rm -f "/tmp/${BACKUP_NAME}.archive"
echo "[$(date)] Backup completed"
SCRIPT

sudo chmod +x /usr/local/bin/backup-mongodb.sh

# Setup cron job
echo "[$(date)] Setting up backup cron job..."
echo "*/30 * * * * root /usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1" | sudo tee /etc/cron.d/mongodb-backup

# Set weak permissions (vulnerabilities)
echo "[$(date)] Setting weak file permissions (intentional)..."
sudo chmod 777 /var/lib/mongodb
sudo chmod 666 /etc/mongod.conf
sudo chmod 755 /usr/local/bin/backup-mongodb.sh

# Disable firewall
echo "[$(date)] Disabling firewall (vulnerability)..."
sudo ufw disable 2>/dev/null || true

# Create additional vulnerable users
echo "[$(date)] Creating additional vulnerable users..."
mongo --authenticationDatabase admin -u admin -p insecurepass <<EOF
use admin
try {
  db.createUser({ user: "backup", pwd: "backup", roles: [{ role: "backup", db: "admin" }] })
  print("[$(date)] Backup user created")
} catch (e) { print("[$(date)] Backup user exists") }

try {
  db.createUser({ user: "monitor", pwd: "monitor", roles: [{ role: "clusterMonitor", db: "admin" }] })
  print("[$(date)] Monitor user created")
} catch (e) { print("[$(date)] Monitor user exists") }
EOF

# Add test data
echo "[$(date)] Adding test data..."
mongo --authenticationDatabase admin -u admin -p insecurepass <<EOF
use wizknowledge
db.test_data.insert([
  { type: "sensitive", data: "SSN: 123-45-6789", classification: "PII" },
  { type: "sensitive", data: "Credit Card: 4111-1111-1111-1111", classification: "PCI" },
  { type: "sensitive", data: "API Key: sk_live_abcdef123456", classification: "SECRET" }
])
print("[$(date)] Test data inserted")
EOF

# Weak SSH configuration
echo "[$(date)] Configuring weak SSH settings..."
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
echo "MaxAuthTries 100" | sudo tee -a /etc/ssh/sshd_config
echo "MaxSessions 100" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh

# Summary
PUBLIC_IP=$(curl -s ifconfig.me)
echo ""
echo "========================================="
echo "VULNERABLE MongoDB Installation Complete"
echo "========================================="
echo "Installation completed at: $(date)"
echo ""
echo "Vulnerabilities introduced:"
echo "✗ MongoDB 3.2.22 (EOL, 47+ CVEs)"
echo "✗ Weak passwords (admin/insecurepass)"
echo "✗ MongoDB on 0.0.0.0:27017"
echo "✗ Mongo Express on 0.0.0.0:8081"
echo "✗ World-writable directories (777)"
echo "✗ Unencrypted backups"
echo "✗ SSH root login enabled"
echo "✗ Firewall disabled"
echo ""
echo "Access endpoints:"
echo "MongoDB: mongodb://admin:insecurepass@${PUBLIC_IP}:27017"
echo "Mongo Express: http://${PUBLIC_IP}:8081 (admin/admin123)"
echo "SSH: ssh ubuntu@${PUBLIC_IP}"
echo ""
echo "Log file saved to: $LOG_FILE"
echo "========================================="

# Copy log to root directory
echo "[$(date)] Copying log to root directory..."
sudo cp "$LOG_FILE" /

echo "[$(date)] Installation script completed"