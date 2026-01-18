#!/bin/bash

# Fix oauth2-proxy header forwarding configuration
# This script ensures oauth2-proxy passes user email/name headers to nginx
#
# Issue: Missing set_xauthrequest and pass_user_headers in config
# Symptom: Applications show "unknown@unknown.com" instead of real email
#
# Usage: sudo ./fix-oauth2-headers.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

CONFIG_FILE="/etc/oauth2-proxy/config.cfg"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

log_info "Checking oauth2-proxy configuration..."

# Check if settings already exist
if grep -q "^set_xauthrequest" "$CONFIG_FILE" && grep -q "^pass_user_headers" "$CONFIG_FILE"; then
    log_success "Header forwarding settings already configured!"

    # Show current values
    echo ""
    log_info "Current settings:"
    grep -E "^(set_xauthrequest|pass_user_headers|pass_authorization_header|pass_access_token)" "$CONFIG_FILE" || true

    exit 0
fi

log_warning "Header forwarding settings are missing!"
log_info "Adding required settings..."

# Backup current config
BACKUP_FILE="${CONFIG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
log_success "Backup created: $BACKUP_FILE"

# Add the missing settings
cat >> "$CONFIG_FILE" << 'EOF'

# Pass user info to backend via headers
# Required for applications to receive authenticated user email
set_xauthrequest = true
pass_authorization_header = true
pass_access_token = false
pass_user_headers = true
EOF

log_success "Header forwarding settings added to config"

# Show what was added
echo ""
log_info "Added settings:"
tail -7 "$CONFIG_FILE"

# Validate config by checking oauth2-proxy syntax
log_info "Validating configuration..."
if /usr/local/bin/oauth2-proxy --config="$CONFIG_FILE" --version > /dev/null 2>&1; then
    log_success "Configuration is valid"
else
    log_error "Configuration validation failed!"
    log_warning "Restoring backup..."
    mv "$BACKUP_FILE" "$CONFIG_FILE"
    exit 1
fi

# Restart oauth2-proxy
log_info "Restarting oauth2-proxy service..."
systemctl restart oauth2-proxy

# Check if service started successfully
sleep 2
if systemctl is-active --quiet oauth2-proxy; then
    log_success "oauth2-proxy service restarted successfully"
else
    log_error "oauth2-proxy service failed to start!"
    log_info "Check logs: sudo journalctl -u oauth2-proxy -n 50"
    exit 1
fi

echo ""
log_success "================================================"
log_success "Fix applied successfully!"
log_success "================================================"
echo ""
log_info "Next steps:"
echo ""
echo "1. Clear browser cookies for your domain, OR"
echo "   Visit: https://YOUR_DOMAIN/oauth2/sign_out"
echo ""
echo "2. Log in again"
echo ""
echo "3. Your authenticated email should now appear correctly"
echo ""
log_info "To verify:"
echo "  sudo journalctl -u oauth2-proxy -f"
echo ""
