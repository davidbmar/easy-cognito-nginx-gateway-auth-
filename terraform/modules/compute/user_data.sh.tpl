#!/bin/bash
#
# User Data Script for Auth Gateway EC2 Instance
# This script runs on first boot to install and configure the gateway
#

set -e

# Redirect output to log file
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "========================================"
echo "Auth Gateway Installation Starting"
echo "========================================"
echo "Domain: ${domain_name}"
echo "Region: ${region}"
echo "SSL Method: ${ssl_method}"
echo "Timestamp: $(date)"
echo "========================================"

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y \
    curl \
    wget \
    git \
    nginx \
    python3 \
    python3-pip \
    certbot \
    python3-certbot-nginx \
    jq

# Download installation script
INSTALL_SCRIPT_URL="${install_script_url}"
if [ -z "$INSTALL_SCRIPT_URL" ]; then
    INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth/main/scripts/install.sh"
fi

echo "Downloading installation script from: $INSTALL_SCRIPT_URL"
curl -fsSL "$INSTALL_SCRIPT_URL" -o /tmp/install.sh
chmod +x /tmp/install.sh

# Run installation
echo "Running installation script..."
/tmp/install.sh \
    --domain=${domain_name} \
    --cognito-pool-id=${cognito_pool_id} \
    --cognito-client-id=${cognito_client_id} \
    --cognito-client-secret=${cognito_client_secret} \
    --region=${region} \
    --ssl-method=${ssl_method} \
    %{ if ssl_email != "" }--ssl-email=${ssl_email}%{ endif }

# Enable services
systemctl enable nginx
systemctl enable oauth2-proxy

echo "========================================"
echo "Auth Gateway Installation Complete"
echo "========================================"
echo "Access at: https://${domain_name}"
echo "========================================"
