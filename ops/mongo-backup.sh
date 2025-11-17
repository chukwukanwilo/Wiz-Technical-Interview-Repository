#!/bin/bash
# Daily backup script: dumps MongoDB and uploads to S3 with public-read
set -e
timestamp=$(date -u +"%Y-%m-%dT%H%M%SZ")
backup_dir=/tmp/mongo_backup_$timestamp
mkdir -p "$backup_dir"
/usr/bin/mongodump --archive="$backup_dir/dump.archive" --gzip
# install aws cli beforehand and ensure instance has IAM permissions (intentionally broad)
aws s3 cp "$backup_dir/dump.archive" s3://<PUBLIC_BUCKET>/backups/dump-$timestamp.archive --acl public-read
# optional: cleanup
rm -rf "$backup_dir"
