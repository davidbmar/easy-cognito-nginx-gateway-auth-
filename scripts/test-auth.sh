#!/bin/bash

# Test authentication gateway configuration
# Verifies all components are working correctly

# Colors
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
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "========================================"
echo "Authentication Gateway Test Suite"
echo "========================================"
echo ""

# Test 1: Check if oauth2-proxy is installed
echo "[1/10] Checking oauth2-proxy binary..."
if [ -f "/usr/local/bin/oauth2-proxy" ]; then
    pass "oauth2-proxy binary exists"
else
    fail "oauth2-proxy binary not found at /usr/local/bin/oauth2-proxy"
fi

# Test 2: Check if oauth2-proxy is running
echo "[2/10] Checking oauth2-proxy process..."
if pgrep -f oauth2-proxy > /dev/null; then
    pass "oauth2-proxy process is running"
else
    fail "oauth2-proxy process is NOT running"
fi

# Test 3: Check if oauth2-proxy port is listening
echo "[3/10] Checking oauth2-proxy port (4180)..."
if ss -tlnp 2>/dev/null | grep -q ":4180" || netstat -tlnp 2>/dev/null | grep -q ":4180"; then
    pass "oauth2-proxy listening on port 4180"
else
    fail "oauth2-proxy NOT listening on port 4180"
fi

# Test 4: Check nginx
echo "[4/10] Checking nginx..."
if systemctl is-active --quiet nginx; then
    pass "nginx is running"
else
    fail "nginx is NOT running"
fi

# Test 5: Check nginx configuration
echo "[5/10] Checking nginx configuration..."
if nginx -t 2>/dev/null; then
    pass "nginx configuration is valid"
else
    fail "nginx configuration has errors"
fi

# Test 6: Check if ports 80/443 are listening
echo "[6/10] Checking nginx ports..."
if ss -tlnp 2>/dev/null | grep -qE ":(80|443)" || netstat -tlnp 2>/dev/null | grep -qE ":(80|443)"; then
    pass "nginx listening on ports 80/443"
else
    fail "nginx NOT listening on ports 80/443"
fi

# Test 7: Check SSL certificates
echo "[7/10] Checking SSL certificates..."
if [ -f "/etc/nginx/ssl/selfsigned.crt" ] && [ -f "/etc/nginx/ssl/selfsigned.key" ]; then
    pass "SSL certificates exist"
else
    warn "SSL certificates not found (may be using custom certs)"
fi

# Test 8: Check oauth2-proxy config
echo "[8/10] Checking oauth2-proxy configuration..."
if [ -f "/etc/oauth2-proxy/config.cfg" ]; then
    pass "oauth2-proxy config exists"

    # Check if config has required fields
    if grep -q "oidc_issuer_url" /etc/oauth2-proxy/config.cfg && \
       grep -q "client_id" /etc/oauth2-proxy/config.cfg && \
       grep -q "redirect_url" /etc/oauth2-proxy/config.cfg; then
        pass "oauth2-proxy config has required fields"
    else
        fail "oauth2-proxy config missing required fields"
    fi
else
    fail "oauth2-proxy config not found"
fi

# Test 9: Check nginx auth-gateway config
echo "[9/10] Checking nginx auth-gateway configuration..."
if [ -f "/etc/nginx/sites-available/auth-gateway" ]; then
    pass "nginx auth-gateway config exists"

    # Check if it's enabled
    if [ -L "/etc/nginx/sites-enabled/auth-gateway" ]; then
        pass "nginx auth-gateway config is enabled"
    else
        fail "nginx auth-gateway config is NOT enabled"
    fi
else
    fail "nginx auth-gateway config not found"
fi

# Test 10: Test HTTP redirect (if possible)
echo "[10/10] Testing HTTP redirect to Cognito..."
if command -v curl > /dev/null; then
    # Try to get redirect location
    REDIRECT=$(curl -k -s -I -L --max-redirs 0 https://localhost/ 2>&1 | grep -i "Location:" | grep -o "cognito" || echo "")

    if [ -n "$REDIRECT" ]; then
        pass "HTTP request redirects to Cognito"
    else
        warn "Could not verify redirect to Cognito (may need domain/IP instead of localhost)"
    fi
else
    warn "curl not installed, skipping HTTP test"
fi

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Your authentication gateway appears to be configured correctly."
    echo "Try accessing your site in a web browser to test end-to-end authentication."
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo "Please review the failures above and check:"
    echo "  - oauth2-proxy logs: sudo journalctl -u oauth2-proxy -n 50"
    echo "  - nginx error log: sudo tail -50 /var/log/nginx/error.log"
    exit 1
fi
