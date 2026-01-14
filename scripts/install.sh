#!/bin/bash

# Easy Cognito Nginx Gateway Auth - Main Installation Script
#
# This script installs and configures the complete authentication gateway:
# - oauth2-proxy
# - nginx with auth_request
# - SSL certificates
# - systemd service
#
# Usage:
#   sudo ./install.sh --domain=example.com \
#                     --cognito-region=us-east-1 \
#                     --cognito-pool-id=us-east-1_XXXXX \
#                     --cognito-client-id=YYYYYY \
#                     --cognito-client-secret=ZZZZZZ \
#                     --app-port=3000 \
#                     [--app-path=/] \
#                     [--oauth2-port=4180]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
APP_PATH="/"
OAUTH2_PORT="4180"
SKIP_SSL=false
SKIP_COGNITO_VALIDATION=false

# Functions
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

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Required:
  --domain=DOMAIN                   Your domain or IP address
  --cognito-region=REGION           AWS region (e.g., us-east-1)
  --cognito-pool-id=POOL_ID         Cognito User Pool ID
  --cognito-client-id=CLIENT_ID     Cognito App Client ID
  --cognito-client-secret=SECRET    Cognito App Client Secret
  --app-port=PORT                   Your application port

Optional:
  --app-path=PATH                   URL path for app (default: /)
  --oauth2-port=PORT                oauth2-proxy port (default: 4180)
  --skip-ssl                        Skip SSL certificate generation
  --skip-cognito-validation         Skip AWS Cognito validation
  --help                            Show this help message

Example:
  sudo ./install.sh \\
    --domain=example.com \\
    --cognito-region=us-east-1 \\
    --cognito-pool-id=us-east-1_XXXXXXXXX \\
    --cognito-client-id=YYYYYYYY \\
    --cognito-client-secret=ZZZZZZZZ \\
    --app-port=3000

EOF
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
        --cognito-region=*)
            AWS_REGION="${arg#*=}"
            ;;
        --cognito-pool-id=*)
            COGNITO_POOL_ID="${arg#*=}"
            ;;
        --cognito-client-id=*)
            CLIENT_ID="${arg#*=}"
            ;;
        --cognito-client-secret=*)
            CLIENT_SECRET="${arg#*=}"
            ;;
        --app-port=*)
            APP_PORT="${arg#*=}"
            ;;
        --app-path=*)
            APP_PATH="${arg#*=}"
            ;;
        --oauth2-port=*)
            OAUTH2_PORT="${arg#*=}"
            ;;
        --skip-ssl)
            SKIP_SSL=true
            ;;
        --skip-cognito-validation)
            SKIP_COGNITO_VALIDATION=true
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$DOMAIN" ] || [ -z "$AWS_REGION" ] || [ -z "$COGNITO_POOL_ID" ] || \
   [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ] || [ -z "$APP_PORT" ]; then
    log_error "Missing required arguments"
    show_usage
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

# Display configuration
log_info "==================================="
log_info "Easy Cognito Nginx Gateway Auth"
log_info "Installation Configuration"
log_info "==================================="
echo ""
log_info "Domain: $DOMAIN"
log_info "AWS Region: $AWS_REGION"
log_info "Cognito Pool ID: $COGNITO_POOL_ID"
log_info "Cognito Client ID: $CLIENT_ID"
log_info "Application Port: $APP_PORT"
log_info "Application Path: $APP_PATH"
log_info "OAuth2 Proxy Port: $OAUTH2_PORT"
echo ""

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

log_info "Project root: $PROJECT_ROOT"
echo ""

# Confirm installation
read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installation cancelled"
    exit 0
fi

echo ""
log_info "Starting installation..."
echo ""

# Step 1: Install dependencies
log_info "[1/7] Installing dependencies..."
if apt-get update -qq && apt-get install -y nginx wget curl jq > /dev/null 2>&1; then
    log_success "Dependencies installed"
else
    log_error "Failed to install dependencies"
    exit 1
fi

# Step 2: Install oauth2-proxy
log_info "[2/7] Installing oauth2-proxy..."
if bash "$SCRIPT_DIR/setup-oauth2-proxy.sh"; then
    # Verify oauth2-proxy binary exists
    if command -v oauth2-proxy >/dev/null 2>&1 || [ -x /usr/local/bin/oauth2-proxy ]; then
        log_success "oauth2-proxy installed"
    else
        log_error "oauth2-proxy binary not found after installation"
        exit 1
    fi
else
    log_error "Failed to install oauth2-proxy"
    exit 1
fi

# Step 3: Generate SSL certificate (if not skipped)
if [ "$SKIP_SSL" = false ]; then
    log_info "[3/7] Generating SSL certificates..."
    bash "$SCRIPT_DIR/setup-ssl.sh" --domain="$DOMAIN"
    log_success "SSL certificates generated"
else
    log_warning "[3/7] Skipping SSL certificate generation"
fi

# Step 4: Configure oauth2-proxy
log_info "[4/7] Configuring oauth2-proxy..."

# Generate cookie secret (must be exactly 32 bytes for AES cipher)
# Try Python first (more reliable), fall back to openssl
COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode()[:32])' 2>/dev/null || openssl rand -base64 32 | tr -d '\n' | head -c 32)

# Validate cookie secret length
if [ ${#COOKIE_SECRET} -ne 32 ]; then
    log_error "Failed to generate valid 32-byte cookie secret (got ${#COOKIE_SECRET} bytes)"
    log_error "Generated secret: $COOKIE_SECRET"
    exit 1
fi

log_info "Generated 32-byte cookie secret"

# Create oauth2-proxy config directory
mkdir -p /etc/oauth2-proxy

# Replace variables in template
cat "$PROJECT_ROOT/config/oauth2-proxy/config.cfg.template" | \
    sed "s|{{AWS_REGION}}|$AWS_REGION|g" | \
    sed "s|{{COGNITO_USER_POOL_ID}}|$COGNITO_POOL_ID|g" | \
    sed "s|{{COGNITO_CLIENT_ID}}|$CLIENT_ID|g" | \
    sed "s|{{COGNITO_CLIENT_SECRET}}|$CLIENT_SECRET|g" | \
    sed "s|{{DOMAIN}}|$DOMAIN|g" | \
    sed "s|{{COOKIE_SECRET}}|$COOKIE_SECRET|g" | \
    sed "s|{{OAUTH2_PROXY_PORT}}|$OAUTH2_PORT|g" \
    > /etc/oauth2-proxy/config.cfg

chmod 600 /etc/oauth2-proxy/config.cfg
log_success "oauth2-proxy configured"

# Step 5: Configure nginx
log_info "[5/7] Configuring nginx..."

# Determine app name from port
APP_NAME="app_${APP_PORT}"

# SSL paths
SSL_CERT_PATH="/etc/nginx/ssl/selfsigned.crt"
SSL_KEY_PATH="/etc/nginx/ssl/selfsigned.key"

# Replace variables in nginx template
cat "$PROJECT_ROOT/config/nginx/auth-gateway.conf.template" | \
    sed "s|{{DOMAIN}}|$DOMAIN|g" | \
    sed "s|{{APP1_NAME}}|$APP_NAME|g" | \
    sed "s|{{APP1_PORT}}|$APP_PORT|g" | \
    sed "s|{{APP1_PATH}}|$APP_PATH|g" | \
    sed "s|{{SSL_CERT_PATH}}|$SSL_CERT_PATH|g" | \
    sed "s|{{SSL_KEY_PATH}}|$SSL_KEY_PATH|g" | \
    sed "s|{{OAUTH2_PROXY_PORT}}|$OAUTH2_PORT|g" \
    > /etc/nginx/sites-available/auth-gateway

# Enable the site
ln -sf /etc/nginx/sites-available/auth-gateway /etc/nginx/sites-enabled/auth-gateway

# Remove default site if it exists
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
if nginx -t 2>&1 | tee /tmp/nginx-test.log; then
    log_success "nginx configured"
else
    log_error "nginx configuration test failed"
    log_error "See /tmp/nginx-test.log for details"
    cat /tmp/nginx-test.log
    exit 1
fi

# Step 6: Install systemd service
log_info "[6/7] Installing systemd service..."
cp "$PROJECT_ROOT/config/systemd/oauth2-proxy.service" /etc/systemd/system/oauth2-proxy.service
systemctl daemon-reload
systemctl enable oauth2-proxy
log_success "systemd service installed"

# Step 7: Start services
log_info "[7/7] Starting services..."

# Start oauth2-proxy
systemctl restart oauth2-proxy
sleep 2

# Verify oauth2-proxy started successfully
if ! systemctl is-active --quiet oauth2-proxy; then
    log_error "oauth2-proxy failed to start"
    log_error "Check logs with: sudo journalctl -u oauth2-proxy -n 50"
    exit 1
fi
log_success "oauth2-proxy started successfully"

# Start nginx
systemctl restart nginx

# Verify nginx started successfully
if ! systemctl is-active --quiet nginx; then
    log_error "nginx failed to start"
    log_error "Check logs with: sudo journalctl -u nginx -n 50"
    log_error "Check config with: sudo nginx -t"
    exit 1
fi
log_success "nginx started successfully"

log_success "All services started"

# Final verification
log_info "Verifying installation..."
sleep 2

# Check if ports are listening
PORTS_OK=true

if ss -tln | grep -q ":443 "; then
    log_success "nginx listening on port 443 (HTTPS)"
else
    log_warning "nginx not listening on port 443"
    PORTS_OK=false
fi

if ss -tln | grep -q ":$OAUTH2_PORT "; then
    log_success "oauth2-proxy listening on port $OAUTH2_PORT"
else
    log_warning "oauth2-proxy not listening on port $OAUTH2_PORT"
    PORTS_OK=false
fi

# Test authentication redirect
log_info "Testing authentication redirect..."
TEST_RESULT=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost/ 2>/dev/null || echo "000")

if [ "$TEST_RESULT" = "302" ]; then
    log_success "Authentication redirect working (HTTP 302)"
elif [ "$TEST_RESULT" = "200" ]; then
    log_success "Gateway responding (HTTP 200)"
else
    log_warning "Unexpected response code: $TEST_RESULT"
fi

echo ""
log_success "==================================="
log_success "Installation Complete!"
log_success "==================================="
echo ""
log_info "Next steps:"
echo ""
echo "1. Make sure your application is running on port $APP_PORT"
echo ""
echo "2. Visit https://$DOMAIN$APP_PATH in your browser"
echo ""
echo "3. You will be redirected to AWS Cognito for authentication"
echo ""
echo "4. After login, you'll be redirected back to your application"
echo ""
log_info "Useful commands:"
echo "  - Check oauth2-proxy status: sudo systemctl status oauth2-proxy"
echo "  - Check nginx status: sudo systemctl status nginx"
echo "  - View oauth2-proxy logs: sudo journalctl -u oauth2-proxy -f"
echo "  - View nginx logs: sudo tail -f /var/log/nginx/error.log"
echo ""
log_info "Test the installation:"
echo "  curl -I https://$DOMAIN$APP_PATH"
echo ""
log_success "Happy authenticating! 🔐"
