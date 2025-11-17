#!/bin/bash
# Install an old MongoDB version (intentionally outdated). Example for Amazon Linux 2
set -e
sudo yum update -y
# choose an older repo / package; placeholder below
sudo yum install -y mongodb-org-4.0.27
sudo systemctl enable mongod
sudo systemctl start mongod
