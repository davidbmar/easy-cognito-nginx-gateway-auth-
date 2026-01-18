#!/bin/bash

# Validate oauth2-proxy configuration for common issues
# This script checks if oauth2-proxy is properly configured to pass user headers
#
# Usage: ./validate-oauth2-config.sh

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
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo ""
log_info "=============================================="
log_info "OAuth2-Proxy Configuration Validator"
log_info "=============================================="
echo ""

ERRORS=0
WARNINGS=0

# Check 1: Config file exists
log_info "Checking configuration file..."
CONFIG_FILE="/etc/oauth2-proxy/config.cfg"
if [ -f "$CONFIG_FILE" ]; then
    log_success "Config file found: $CONFIG_FILE"
else
    log_error "Config file not found: $CONFIG_FILE"
    ERRORS=$((ERRORS + 1))
    exit 1
fi

# Check 2: oauth2-proxy binary exists
log_info "Checking oauth2-proxy binary..."
if [ -x "/usr/local/bin/oauth2-proxy" ]; then
    VERSION=$(/usr/local/bin/oauth2-proxy --version 2>&1 | head -1)
    log_success "oauth2-proxy installed: $VERSION"
else
    log_error "oauth2-proxy binary not found or not executable"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: Required settings for header forwarding
log_info "Checking header forwarding settings..."

if grep -q "^set_xauthrequest *= *true" "$CONFIG_FILE"; then
    log_success "set_xauthrequest = true"
else
    log_error "Missing or disabled: set_xauthrequest = true"
    log_warning "  → Applications will not receive X-Auth-Request-Email header"
    ERRORS=$((ERRORS + 1))
fi

if grep -q "^pass_user_headers *= *true" "$CONFIG_FILE"; then
    log_success "pass_user_headers = true"
else
    log_error "Missing or disabled: pass_user_headers = true"
    log_warning "  → User email/name will not be passed to applications"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: Provider configuration
log_info "Checking provider configuration..."

if grep -q "^provider *= *\"oidc\"" "$CONFIG_FILE"; then
    log_success "Provider: oidc"
else
    log_warning "Provider is not set to 'oidc' - may be using different auth method"
    WARNINGS=$((WARNINGS + 1))
fi

if grep -q "^oidc_issuer_url" "$CONFIG_FILE"; then
    ISSUER=$(grep "^oidc_issuer_url" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' "')
    log_success "OIDC Issuer configured: $ISSUER"
else
    log_error "Missing: oidc_issuer_url"
    ERRORS=$((ERRORS + 1))
fi

# Check 5: Cookie configuration
log_info "Checking cookie configuration..."

if grep -q "^cookie_secret" "$CONFIG_FILE"; then
    log_success "Cookie secret configured"
else
    log_error "Missing: cookie_secret"
    ERRORS=$((ERRORS + 1))
fi

if grep -q "^cookie_secure *= *true" "$CONFIG_FILE"; then
    log_success "Cookie secure flag enabled (HTTPS)"
else
    log_warning "Cookie secure flag disabled (HTTP only)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 6: systemd service
log_info "Checking systemd service..."

if systemctl is-enabled oauth2-proxy > /dev/null 2>&1; then
    log_success "Service enabled (starts on boot)"
else
    log_warning "Service not enabled - will not start on boot"
    WARNINGS=$((WARNINGS + 1))
fi

if systemctl is-active oauth2-proxy > /dev/null 2>&1; then
    log_success "Service is running"
else
    log_error "Service is not running"
    ERRORS=$((ERRORS + 1))
fi

# Check 7: Listening port
log_info "Checking if oauth2-proxy is listening..."

OAUTH2_PORT=$(grep "^http_address" "$CONFIG_FILE" | grep -o '[0-9]\+' || echo "4180")
if ss -tlnp | grep -q ":$OAUTH2_PORT"; then
    log_success "Listening on port $OAUTH2_PORT"
else
    log_error "Not listening on port $OAUTH2_PORT"
    ERRORS=$((ERRORS + 1))
fi

# Check 8: nginx integration
log_info "Checking nginx integration..."

if [ -f "/etc/nginx/sites-available/auth-gateway" ]; then
    if grep -q "auth_request /oauth2/auth" /etc/nginx/sites-available/auth-gateway; then
        log_success "nginx auth_request configured"
    else
        log_warning "nginx may not be using auth_request"
        WARNINGS=$((WARNINGS + 1))
    fi

    if grep -q "X-Auth-Request-Email" /etc/nginx/sites-available/auth-gateway; then
        log_success "nginx configured to pass email header"
    else
        log_warning "nginx may not be passing email header to apps"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    log_warning "nginx auth-gateway config not found"
    WARNINGS=$((WARNINGS + 1))
fi

# Summary
echo ""
log_info "=============================================="
log_info "Validation Summary"
log_info "=============================================="
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    log_success "All checks passed! ✨"
    echo ""
    log_info "Your oauth2-proxy is properly configured."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    log_warning "$WARNINGS warning(s) found"
    echo ""
    log_info "Configuration is functional but could be improved."
    exit 0
else
    log_error "$ERRORS error(s) and $WARNINGS warning(s) found"
    echo ""
    log_info "Fix errors with:"
    echo "  sudo /home/ubuntu/src/easy-cognito-nginx-gateway-auth/scripts/fix-oauth2-headers.sh"
    echo ""
    exit 1
fi
