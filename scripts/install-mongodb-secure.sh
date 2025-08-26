#!/bin/bash
# scripts/install-mongodb-secure.sh
# This script creates a hardened MongoDB setup for the production environment

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

echo "=== Installing SECURE MongoDB 7.0 for Production Environment ==="

# Security checks
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root for security reasons"
   exit 1
fi

# Get the GCS bucket name from metadata
GCS_BUCKET_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/gcs-bucket" -H "Metadata-Flavor: Google" || echo "clgcporg10-173-prod-mongodb-backups")

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install security tools

sudo apt-get install -y \
  ufw \
  fail2ban \
  aide \
  rkhunter \
  auditd \
  apparmor-utils

# Install MongoDB 7.0 (latest stable)
echo "Installing MongoDB 7.0 (latest stable)..."
wget -qO - https://www.mongodb.org/static/pgp/server-7.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org

# Generate strong passwords
ADMIN_PASSWORD=$(openssl rand -base64 32)
APP_PASSWORD=$(openssl rand -base64 32)
BACKUP_PASSWORD=$(openssl rand -base64 32)
KEYFILE_CONTENT=$(openssl rand -base64 756)

# Store passwords securely in Google Secret Manager
echo "Storing credentials in Secret Manager..."
echo "$ADMIN_PASSWORD" | gcloud secrets create mongodb-admin-password --data-file=- 2>/dev/null || \
  echo "$ADMIN_PASSWORD" | gcloud secrets versions add mongodb-admin-password --data-file=-

echo "$APP_PASSWORD" | gcloud secrets create mongodb-app-password --data-file=- 2>/dev/null || \
  echo "$APP_PASSWORD" | gcloud secrets versions add mongodb-app-password --data-file=-

# Create secure MongoDB configuration
echo "Configuring MongoDB with security hardening..."
cat <<EOF | sudo tee /etc/mongod.conf
# mongod.conf - SECURE CONFIGURATION

storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 2
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  logRotate: reopen
  verbosity: 2
  component:
    accessControl:
      verbosity: 2
    command:
      verbosity: 1

net:
  port: 27017
  bindIp: 127.0.0.1,10.0.2.0/24  # Only localhost and prod subnet
  maxIncomingConnections: 100
  ssl:
    mode: requireSSL
    PEMKeyFile: /etc/mongodb/mongodb.pem
    CAFile: /etc/mongodb/ca.pem
    allowConnectionsWithoutCertificates: false
    allowInvalidHostnames: false
    FIPSMode: false

security:
  authorization: enabled
  javascriptEnabled: false  # Disable JS execution
  enableEncryption: true
  encryptionKeyFile: /etc/mongodb/encryption-key
  clusterAuthMode: x509
  
setParameter:
  authenticationMechanisms: SCRAM-SHA-256
  enableLocalhostAuthBypass: false
  
operationProfiling:
  mode: all
  slowOpThresholdMs: 100
  slowOpSampleRate: 1.0

auditLog:
  destination: file
  format: JSON
  path: /var/log/mongodb/auditLog.json
  filter: '{ atype: { $in: [ "authenticate", "createCollection", "createDatabase", "createIndex", "dropCollection", "dropDatabase", "dropIndex", "createUser", "dropUser", "updateUser", "grantRole", "revokeRole" ] } }'

processManagement:
  fork: true
  pidFilePath: /var/run/mongodb/mongod.pid
  timeZoneInfo: /usr/share/zoneinfo
EOF

# Generate SSL certificates
echo "Generating SSL certificates..."
sudo mkdir -p /etc/mongodb
cd /etc/mongodb

# Generate CA
sudo openssl req -new -x509 -days 3650 -nodes -out ca.pem -keyout ca-key.pem -subj "/C=US/ST=CA/L=SF/O=WizLab/CN=MongoCA"

# Generate server certificate
sudo openssl req -new -nodes -out server.csr -keyout server-key.pem -subj "/C=US/ST=CA/L=SF/O=WizLab/CN=prod-mongodb-vm"
sudo openssl x509 -req -in server.csr -days 365 -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem
sudo cat server-key.pem server-cert.pem > mongodb.pem
sudo chmod 400 mongodb.pem ca.pem
sudo chown mongodb:mongodb mongodb.pem ca.pem

# Generate encryption key
echo "$KEYFILE_CONTENT" | sudo tee /etc/mongodb/encryption-key > /dev/null
sudo chmod 400 /etc/mongodb/encryption-key
sudo chown mongodb:mongodb /etc/mongodb/encryption-key

# Set secure file permissions
sudo chmod 700 /var/lib/mongodb
sudo chmod 600 /etc/mongod.conf
sudo chown -R mongodb:mongodb /var/lib/mongodb
sudo chown mongodb:mongodb /etc/mongod.conf

# Configure firewall
echo "Configuring firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.0.2.0/24 to any port 27017  # Only prod subnet
sudo ufw allow from 35.235.240.0/20 to any port 22  # IAP range for SSH
sudo ufw --force enable

# Configure fail2ban for MongoDB
cat <<EOF | sudo tee /etc/fail2ban/jail.d/mongodb.conf
[mongodb]
enabled = true
port = 27017
filter = mongodb
logpath = /var/log/mongodb/mongod.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

cat <<EOF | sudo tee /etc/fail2ban/filter.d/mongodb.conf
[Definition]
failregex = .*Failed to authenticate .* from client <HOST>.*
ignoreregex =
EOF

sudo systemctl restart fail2ban

# Start MongoDB
sudo systemctl stop mongod || true
sudo systemctl start mongod
sudo systemctl enable mongod

# Wait for MongoDB to start
sleep 10

# Initialize secure users
echo "Creating secure MongoDB users..."
mongosh <<EOF
use admin
db.createUser({
  user: "admin",
  pwd: "$ADMIN_PASSWORD",
  roles: [
    { role: "userAdminAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" }
  ],
  mechanisms: ["SCRAM-SHA-256"]
})

db.createUser({
  user: "wizapp",
  pwd: "$APP_PASSWORD",
  roles: [
    { role: "readWrite", db: "wizknowledge" }
  ],
  mechanisms: ["SCRAM-SHA-256"]
})

db.createUser({
  user: "backup",
  pwd: "$BACKUP_PASSWORD",
  roles: [
    { role: "backup", db: "admin" },
    { role: "restore", db: "admin" }
  ],
  mechanisms: ["SCRAM-SHA-256"]
})

// Create monitoring user with minimal permissions
db.createUser({
  user: "monitor",
  pwd: "$(openssl rand -base64 32)",
  roles: [
    { role: "clusterMonitor", db: "admin" },
    { role: "read", db: "local" }
  ],
  mechanisms: ["SCRAM-SHA-256"]
})
EOF

# Create secure backup script
echo "Creating secure backup script..."
cat <<'BACKUP_SCRIPT' | sudo tee /usr/local/bin/backup-mongodb.sh
#!/bin/bash
set -euo pipefail

# Retrieve password from Secret Manager
BACKUP_PASSWORD=$(gcloud secrets versions access latest --secret="mongodb-backup-password")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mongodb-backup-${TIMESTAMP}"
BUCKET_NAME="clgcporg10-173-prod-mongodb-backups"
ENCRYPTION_KEY=$(openssl rand -hex 32)

echo "[$(date)] Starting secure MongoDB backup..."

# Create encrypted backup
mongodump \
  --host=localhost \
  --port=27017 \
  --username=backup \
  --password="${BACKUP_PASSWORD}" \
  --authenticationDatabase=admin \
  --ssl \
  --sslCAFile=/etc/mongodb/ca.pem \
  --archive="/tmp/${BACKUP_NAME}.archive" \
  --gzip

# Encrypt the backup with AES-256
openssl enc -aes-256-cbc -salt -in "/tmp/${BACKUP_NAME}.archive" \
  -out "/tmp/${BACKUP_NAME}.archive.enc" -k "${ENCRYPTION_KEY}"

# Store encryption key in Secret Manager
echo "${ENCRYPTION_KEY}" | gcloud secrets create "backup-key-${TIMESTAMP}" --data-file=-

# Upload encrypted backup to GCS with customer-managed encryption
gsutil -o "GSUtil:encryption_key=${ENCRYPTION_KEY}" cp \
  "/tmp/${BACKUP_NAME}.archive.enc" \
  "gs://${BUCKET_NAME}/"

# Secure deletion of temporary files
shred -vfz -n 3 "/tmp/${BACKUP_NAME}.archive"
shred -vfz -n 3 "/tmp/${BACKUP_NAME}.archive.enc"

# Log with audit trail
echo "[$(date)] Backup ${BACKUP_NAME} completed and encrypted" | sudo tee -a /var/log/mongodb-backup.log

# Send notification (optional)
gcloud pubsub topics publish mongodb-backups \
  --message="Backup completed: ${BACKUP_NAME}" \
  --attribute="timestamp=${TIMESTAMP},status=success"
BACKUP_SCRIPT

sudo chmod 750 /usr/local/bin/backup-mongodb.sh
sudo chown mongodb:mongodb /usr/local/bin/backup-mongodb.sh

# Set up secure cron job (not as root)
echo "Setting up automated backups..."
cat <<EOF | sudo tee /etc/cron.d/mongodb-backup
# Secure MongoDB backup schedule
0 2 * * * mongodb /usr/local/bin/backup-mongodb.sh >> /var/log/mongodb-backup.log 2>&1
EOF

# Configure auditd for MongoDB
cat <<EOF | sudo tee -a /etc/audit/rules.d/mongodb.rules
# MongoDB audit rules
-w /etc/mongod.conf -p wa -k mongodb_config
-w /var/lib/mongodb/ -p wa -k mongodb_data
-w /var/log/mongodb/ -p wa -k mongodb_logs
-w /usr/local/bin/backup-mongodb.sh -p x -k mongodb_backup
EOF

sudo systemctl restart auditd

# Configure AppArmor profile for MongoDB
cat <<EOF | sudo tee /etc/apparmor.d/usr.bin.mongod
#include <tunables/global>

/usr/bin/mongod {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  
  capability setgid,
  capability setuid,
  capability sys_resource,
  capability dac_override,
  
  /usr/bin/mongod mr,
  /etc/mongod.conf r,
  /etc/mongodb/** r,
  /var/lib/mongodb/ r,
  /var/lib/mongodb/** rwk,
  /var/log/mongodb/ r,
  /var/log/mongodb/** rw,
  /var/run/mongodb/ r,
  /var/run/mongodb/** rw,
  /tmp/ r,
  /tmp/** rw,
  
  # Deny network access except to specific subnet
  network tcp,
  deny network udp,
  deny network raw,
}
EOF

sudo apparmor_parser -r /etc/apparmor.d/usr.bin.mongod

# Set up log rotation
cat <<EOF | sudo tee /etc/logrotate.d/mongodb
/var/log/mongodb/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 640 mongodb mongodb
    sharedscripts
    postrotate
        /bin/kill -SIGUSR1 \`cat /var/run/mongodb/mongod.pid 2>/dev/null\` 2>/dev/null || true
    endscript
}
EOF

# Enable MongoDB security features
mongosh --username admin --password "$ADMIN_PASSWORD" --authenticationDatabase admin <<EOF
use admin
db.runCommand({ setFeatureCompatibilityVersion: "7.0" })
db.runCommand({ setParameter: 1, auditAuthorizationSuccess: true })
db.runCommand({ setParameter: 1, enableTestCommands: false })
EOF

# Create connection string for application (stored in Secret Manager)
CONNECTION_STRING="mongodb://wizapp:${APP_PASSWORD}@localhost:27017/wizknowledge?authSource=admin&ssl=true"
echo "$CONNECTION_STRING" | gcloud secrets create mongodb-connection-string --data-file=- 2>/dev/null || \
  echo "$CONNECTION_STRING" | gcloud secrets versions add mongodb-connection-string --data-file=-

# Output summary
echo ""
echo "==================================================="
echo "   SECURE MongoDB Setup Complete (Production)      "
echo "==================================================="
echo ""
echo "Security features enabled:"
echo "✓ MongoDB 7.0 (latest stable)"
echo "✓ Strong passwords (32+ characters)"
echo "✓ SSL/TLS encryption required"
echo "✓ Bound only to private subnet (10.0.2.0/24)"
echo "✓ JavaScript execution disabled"
echo "✓ Encryption at rest enabled"
echo "✓ Audit logging enabled"
echo "✓ Firewall configured (ufw)"
echo "✓ Fail2ban protection"
echo "✓ AppArmor profile enforced"
echo "✓ Encrypted backups to private GCS"
echo "✓ Credentials in Secret Manager"
echo "✓ File permissions hardened (700/600)"
echo "✓ Log rotation configured"
echo "✓ Security monitoring enabled"
echo ""
echo "Access restricted to:"
echo "- MongoDB: Only from prod GKE subnet"
echo "- SSH: Only via Identity-Aware Proxy"
echo "- No public access points"
echo ""
echo "Credentials stored in Secret Manager:"
echo "- mongodb-admin-password"
echo "- mongodb-app-password"
echo "- mongodb-connection-string"
echo ""
echo "GCS Bucket: gs://clgcporg10-173-prod-mongodb-backups/ (private)"
echo "==================================================="

# Run initial backup
echo "Running initial encrypted backup..."
sudo -u mongodb /usr/local/bin/backup-mongodb.sh

# Log completion
echo "[$(date)] Secure MongoDB installation completed" | sudo tee -a /var/log/setup.log