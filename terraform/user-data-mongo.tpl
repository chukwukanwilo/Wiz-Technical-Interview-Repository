#!/bin/bash
set -e
# Install older MongoDB (4.0.x) on Amazon Linux 2
# This user-data template expects 'backup_bucket' to be provided via Terraform templatefile()

yum update -y
yum install -y jq awscli

cat > /etc/yum.repos.d/mongodb-org-4.0.repo <<'EOF'
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/
gpgcheck=0
enabled=1
EOF

# install mongodb-org (older series)
yum install -y mongodb-org-4.0.27 || yum install -y mongodb-org || true

# configure mongod.conf to listen on all interfaces
if [ -f /etc/mongod.conf ]; then
  sed -i "s/bindIp: 127.0.0.1/bindIp: 0.0.0.0/" /etc/mongod.conf || true
fi

systemctl enable mongod
systemctl start mongod

# Wait for MongoDB to start
sleep 10

# Fetch MongoDB credentials from AWS Secrets Manager by name
SECRET_NAME="${secret_name}"
REGION="${aws_region}"

echo "Fetching MongoDB credentials from Secrets Manager: $SECRET_NAME in region $REGION"
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "$REGION" --query SecretString --output text 2>/dev/null || echo '{}')

# Check if secret has credentials
if [ "$SECRET_JSON" != "{}" ] && [ -n "$SECRET_JSON" ]; then
  MONGO_USER=$(echo $SECRET_JSON | jq -r .MONGO_USERNAME)
  MONGO_PASS=$(echo $SECRET_JSON | jq -r .MONGO_PASSWORD)
  
  if [ -n "$MONGO_USER" ] && [ "$MONGO_USER" != "null" ] && [ -n "$MONGO_PASS" ] && [ "$MONGO_PASS" != "null" ]; then
    echo "Creating MongoDB admin user: $MONGO_USER"
    mongo admin --eval "
      db.createUser({
        user: '$MONGO_USER',
        pwd: '$MONGO_PASS',
        roles: [ { role: 'userAdminAnyDatabase', db: 'admin' }, 'readWriteAnyDatabase' ]
      })
    "
    
    # Enable authentication
    echo "Enabling MongoDB authentication..."
    if [ -f /etc/mongod.conf ]; then
      echo "security:" >> /etc/mongod.conf
      echo "  authorization: enabled" >> /etc/mongod.conf
      systemctl restart mongod
      sleep 5
    fi
  else
    echo "WARNING: Secret exists but credentials are incomplete. Skipping authentication setup."
  fi
else
  echo "WARNING: Secret not yet populated. MongoDB will run without authentication."
  echo "Populate secret '$SECRET_NAME' and restart the instance."
fi

# backup script using the provided bucket
cat > /usr/local/bin/mongo-backup.sh <<BKP
#!/bin/bash
set -e
TIMESTAMP=\$(date -u +"%Y-%m-%dT%H%M%SZ")
TMPDIR=/tmp/mongobkp_\$TIMESTAMP
mkdir -p \$TMPDIR

# Fetch credentials for authenticated backup
SECRET_JSON=\$(aws secretsmanager get-secret-value --secret-id "${secret_name}" --region "${aws_region}" --query SecretString --output text 2>/dev/null || echo '{}')
if [ "\$SECRET_JSON" != "{}" ] && [ -n "\$SECRET_JSON" ]; then
  MONGO_USER=\$(echo \$SECRET_JSON | jq -r .MONGO_USERNAME)
  MONGO_PASS=\$(echo \$SECRET_JSON | jq -r .MONGO_PASSWORD)
  mongodump --username="\$MONGO_USER" --password="\$MONGO_PASS" --authenticationDatabase=admin --archive=\$TMPDIR/dump.archive --gzip || true
else
  mongodump --archive=\$TMPDIR/dump.archive --gzip || true
fi

aws s3 cp \$TMPDIR/dump.archive s3://${backup_bucket}/backups/dump-\$TIMESTAMP.archive --acl public-read || true
rm -rf \$TMPDIR
BKP
chmod +x /usr/local/bin/mongo-backup.sh

# schedule daily backup via cron at 02:15 UTC
( crontab -l 2>/dev/null; echo "15 2 * * * /usr/local/bin/mongo-backup.sh" ) | crontab -

# marker file for debugging
mkdir -p /app
cat > /app/instance-info.txt <<MSG
Wiz Exercise Mongo VM
Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
S3 Backup Bucket: ${backup_bucket}
MSG
