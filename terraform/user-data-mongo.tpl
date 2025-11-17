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

# backup script using the provided bucket
cat > /usr/local/bin/mongo-backup.sh <<BKP
#!/bin/bash
set -e
TIMESTAMP=$(date -u +"%Y-%m-%dT%H%M%SZ")
TMPDIR=/tmp/mongobkp_$TIMESTAMP
mkdir -p $TMPDIR
mongodump --archive=$TMPDIR/dump.archive --gzip || true
aws s3 cp $TMPDIR/dump.archive s3://${backup_bucket}/backups/dump-$TIMESTAMP.archive --acl public-read || true
rm -rf $TMPDIR
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
