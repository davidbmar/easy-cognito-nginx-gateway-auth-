#!/bin/bash

# Verification script for auth gateway setup

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

echo "Auth Gateway Setup Verification"
echo "================================"
echo ""

# Check 1: OAuth2 Proxy binary
echo "Checking oauth2-proxy binary..."
if [ -f "/usr/local/bin/oauth2-proxy" ]; then
    VERSION=$(/usr/local/bin/oauth2-proxy --version 2>&1 | head -n1 || echo "unknown")
    pass "oauth2-proxy binary exists ($VERSION)"
else
    fail "oauth2-proxy binary not found at /usr/local/bin/oauth2-proxy"
fi

# Check 2: OAuth2 Proxy config
echo "Checking oauth2-proxy configuration..."
if [ -f "/etc/oauth2-proxy/config.cfg" ]; then
    pass "oauth2-proxy config exists"

    # Check file permissions (should be 600)
    PERMS=$(stat -c "%a" /etc/oauth2-proxy/config.cfg)
    if [ "$PERMS" = "600" ]; then
        pass "oauth2-proxy config has correct permissions (600)"
    else
        warn "oauth2-proxy config permissions are $PERMS (should be 600)"
    fi
else
    fail "oauth2-proxy config not found at /etc/oauth2-proxy/config.cfg"
fi

# Check 3: SSL certificates
echo "Checking SSL certificates..."
if [ -f "/etc/nginx/ssl/selfsigned.crt" ] && [ -f "/etc/nginx/ssl/selfsigned.key" ]; then
    pass "SSL certificates exist"

    # Check certificate expiry
    EXPIRY=$(openssl x509 -enddate -noout -in /etc/nginx/ssl/selfsigned.crt | cut -d= -f2)
    pass "SSL certificate valid until: $EXPIRY"
else
    fail "SSL certificates not found in /etc/nginx/ssl/"
fi

# Check 4: Systemd service
echo "Checking systemd service..."
if [ -f "/etc/systemd/system/oauth2-proxy.service" ]; then
    pass "oauth2-proxy systemd service file exists"
else
    fail "oauth2-proxy systemd service file not found"
fi

if systemctl is-enabled --quiet oauth2-proxy; then
    pass "oauth2-proxy service is enabled"
else
    fail "oauth2-proxy service is not enabled"
fi

if systemctl is-active --quiet oauth2-proxy; then
    pass "oauth2-proxy service is running"
else
    fail "oauth2-proxy service is not running"
fi

# Check 5: Nginx configuration
echo "Checking nginx configuration..."
if [ -f "/etc/nginx/sites-available/auth-gateway" ]; then
    pass "nginx auth-gateway config exists"
else
    fail "nginx auth-gateway config not found"
fi

if [ -L "/etc/nginx/sites-enabled/auth-gateway" ]; then
    pass "nginx auth-gateway config is enabled"
else
    fail "nginx auth-gateway config is not enabled"
fi

if systemctl is-active --quiet nginx; then
    pass "nginx service is running"
else
    fail "nginx service is not running"
fi

# Check 6: Nginx include directories
echo "Checking modular nginx configuration..."
if [ -d "/etc/nginx/conf.d/system-upstreams" ]; then
    pass "System upstreams directory exists"
    UPSTREAM_COUNT=$(find /etc/nginx/conf.d/system-upstreams -name "*.conf" 2>/dev/null | wc -l)
    if [ "$UPSTREAM_COUNT" -gt 0 ]; then
        pass "Found $UPSTREAM_COUNT upstream configuration(s)"
    else
        warn "No upstream configurations found (this is OK for initial setup)"
    fi
else
    fail "System upstreams directory not found"
fi

if [ -d "/etc/nginx/conf.d/routes" ]; then
    pass "Routes directory exists"
    ROUTE_COUNT=$(find /etc/nginx/conf.d/routes -name "*.conf" 2>/dev/null | wc -l)
    if [ "$ROUTE_COUNT" -gt 0 ]; then
        pass "Found $ROUTE_COUNT route configuration(s)"
    else
        warn "No route configurations found (this is OK for initial setup)"
    fi
else
    fail "Routes directory not found"
fi

# Check 7: Service connectivity
echo "Checking service connectivity..."
if curl -s http://localhost:4180/ping | grep -q "OK"; then
    pass "oauth2-proxy responding on port 4180"
else
    fail "oauth2-proxy not responding on port 4180"
fi

if curl -sk https://localhost/ >/dev/null 2>&1; then
    pass "nginx responding on port 443"
else
    fail "nginx not responding on port 443"
fi

# Check 8: Nginx configuration syntax
echo "Checking nginx configuration syntax..."
if sudo nginx -t 2>&1 | grep -q "successful"; then
    pass "nginx configuration syntax is valid"
else
    fail "nginx configuration syntax has errors"
fi

# Summary
echo ""
echo "================================"
echo "Verification Summary"
echo "================================"
echo -e "${GREEN}Passed:${NC} $PASSED"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed:${NC} $FAILED"
    echo ""
    echo "Please fix the failed checks before proceeding."
    exit 1
else
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "Auth gateway is properly configured."
    exit 0
fi
