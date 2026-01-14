# Install Script Fixes - 2026-01-14

**Commit**: `7a81018`
**File**: `scripts/install.sh`
**Status**: ✅ Fixed and Tested

---

## Problem Summary

The install script had a critical bug in cookie_secret generation that caused oauth2-proxy to fail with:
```
invalid configuration: cookie_secret must be 16, 24, or 32 bytes to create an AES cipher, but is 39 bytes
```

This was discovered during production deployment to EC2 instance `44.248.103.166`.

---

## Root Cause

**Original Code** (Line 201):
```bash
COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())' || openssl rand -base64 32 | tr -d '\n')
```

**Problem**:
- `os.urandom(32)` generates 32 random bytes
- `base64.urlsafe_b64encode()` encodes to base64, producing ~43 characters (32 * 4/3 ≈ 43)
- `openssl rand -base64 32` also produces more than 32 characters
- oauth2-proxy requires exactly 16, 24, or 32 bytes for AES cipher

**Result**: Generated secret was 39-43 bytes, causing oauth2-proxy to fail on startup.

---

## Solution

**Fixed Code**:
```bash
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
```

**Key Changes**:
1. Truncate base64 output to exactly 32 characters using `[:32]` (Python) or `head -c 32` (bash)
2. Validate the generated secret is exactly 32 bytes
3. Exit with clear error message if validation fails
4. Add stderr redirection for Python command to suppress errors
5. Provide troubleshooting information in error messages

---

## Additional Improvements

### 1. Dependency Installation Validation

**Before**:
```bash
apt-get update -qq
apt-get install -y nginx wget curl jq > /dev/null 2>&1
log_success "Dependencies installed"
```

**After**:
```bash
if apt-get update -qq && apt-get install -y nginx wget curl jq > /dev/null 2>&1; then
    log_success "Dependencies installed"
else
    log_error "Failed to install dependencies"
    exit 1
fi
```

### 2. oauth2-proxy Installation Verification

**Added**:
```bash
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
```

**Benefits**:
- Catches failed installations immediately
- Verifies binary actually exists and is executable
- Prevents proceeding with broken installation

### 3. nginx Configuration Validation

**Before**:
```bash
nginx -t
log_success "nginx configured"
```

**After**:
```bash
if nginx -t 2>&1 | tee /tmp/nginx-test.log; then
    log_success "nginx configured"
else
    log_error "nginx configuration test failed"
    log_error "See /tmp/nginx-test.log for details"
    cat /tmp/nginx-test.log
    exit 1
fi
```

**Benefits**:
- Saves test output to file for debugging
- Shows full error output when test fails
- Prevents starting nginx with broken configuration

### 4. Service Startup Verification

**Before**:
```bash
systemctl restart oauth2-proxy
systemctl restart nginx
log_success "Services started"
```

**After**:
```bash
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
```

**Benefits**:
- Verifies services actually started (not just attempted)
- Provides troubleshooting commands in error messages
- Catches startup failures immediately

### 5. Final Verification Checks

**Added** (new section):
```bash
# Final verification
log_info "Verifying installation..."
sleep 2

# Check if ports are listening
if ss -tln | grep -q ":443 "; then
    log_success "nginx listening on port 443 (HTTPS)"
else
    log_warning "nginx not listening on port 443"
fi

if ss -tln | grep -q ":$OAUTH2_PORT "; then
    log_success "oauth2-proxy listening on port $OAUTH2_PORT"
else
    log_warning "oauth2-proxy not listening on port $OAUTH2_PORT"
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
```

**Benefits**:
- Confirms ports are actually listening
- Tests the authentication flow end-to-end
- Provides immediate feedback on installation success

---

## Testing

### Test Environment
- **OS**: Ubuntu 24.04 LTS
- **Instance**: EC2 t2.micro (us-west-2)
- **IP**: 44.248.103.166

### Test Procedure

**Before Fix**:
```bash
sudo ./scripts/install.sh \
  --domain=44.248.103.166 \
  --cognito-region=us-east-1 \
  --cognito-pool-id=us-east-1_aVHSg58BS \
  --cognito-client-id=46gdd9glnaetl44e2mtap51bkk \
  --cognito-client-secret=... \
  --app-port=8080
```

**Result**: oauth2-proxy failed to start with "cookie_secret must be 16, 24, or 32 bytes" error.

**After Fix**:
- Same command executed successfully
- All services started
- Ports confirmed listening (443, 4180, 8080)
- Authentication redirect working (HTTP 302 to Cognito)

---

## Migration Guide

### For Existing Installations

If you have an existing installation with a working cookie_secret, no action needed. This fix only affects new installations.

### For Failed Installations

If your installation failed with the cookie_secret error:

1. **Update the repository**:
   ```bash
   cd /path/to/easy-cognito-nginx-gateway-auth
   git pull origin main
   ```

2. **Re-run the installation**:
   ```bash
   sudo ./scripts/install.sh [same arguments as before]
   ```

3. The script will:
   - Generate a valid 32-byte cookie_secret
   - Validate all steps
   - Verify services started correctly

### For Manual Fixes

If you already manually fixed the cookie_secret, you can verify it:

```bash
# Check current cookie_secret length
COOKIE_SECRET=$(sudo grep cookie_secret /etc/oauth2-proxy/config.cfg | cut -d'"' -f2)
echo "Cookie secret length: ${#COOKIE_SECRET} bytes"

# Should output: Cookie secret length: 32 bytes
```

If it's not 32 bytes, regenerate it:

```bash
# Generate new 32-byte secret
NEW_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode()[:32])')

# Update config
sudo sed -i "s|cookie_secret = \".*\"|cookie_secret = \"$NEW_SECRET\"|" /etc/oauth2-proxy/config.cfg

# Restart oauth2-proxy
sudo systemctl restart oauth2-proxy
```

---

## Error Messages Reference

### Before Fix

```
[2026/01/14 01:34:50] [main.go:54] invalid configuration:
  cookie_secret must be 16, 24, or 32 bytes to create an AES cipher, but is 39 bytes
```

### After Fix

If cookie_secret generation fails:
```
[ERROR] Failed to generate valid 32-byte cookie secret (got X bytes)
[ERROR] Generated secret: [secret shown for debugging]
```

If oauth2-proxy fails to start:
```
[ERROR] oauth2-proxy failed to start
[ERROR] Check logs with: sudo journalctl -u oauth2-proxy -n 50
```

If nginx fails to start:
```
[ERROR] nginx failed to start
[ERROR] Check logs with: sudo journalctl -u nginx -n 50
[ERROR] Check config with: sudo nginx -t
```

---

## Impact

### Before Fix
- ❌ Installation could fail silently
- ❌ Required manual debugging of systemd logs
- ❌ No validation of generated secrets
- ❌ No verification that services actually started

### After Fix
- ✅ Installation fails fast with clear error messages
- ✅ Troubleshooting commands provided in error output
- ✅ Cookie secret validated before use
- ✅ All services verified to be running
- ✅ Ports confirmed to be listening
- ✅ Authentication flow tested automatically

---

## Related Issues

- Issue initially discovered during EC2 deployment
- Similar issues could occur with other crypto-related secrets
- Fix pattern can be applied to other secret generation in codebase

---

## Best Practices Applied

1. **Validate Inputs**: Check cookie_secret length before using it
2. **Fail Fast**: Exit immediately when a step fails
3. **Clear Errors**: Provide specific error messages with troubleshooting steps
4. **Verify Results**: Don't assume success - check that services actually started
5. **Test Integration**: Verify the full authentication flow works end-to-end

---

## Commit Details

```
commit 7a81018
Author: [Your Name]
Date:   2026-01-14

Fix install script: ensure robust 32-byte cookie_secret generation

Critical Fixes:
- Fix cookie_secret generation to guarantee exactly 32 bytes for AES cipher
- Previous version could generate variable-length secrets causing oauth2-proxy to fail
- Now validates secret length and exits with clear error if generation fails

Error Handling Improvements:
- Add validation after each major step (dependencies, oauth2-proxy, nginx)
- Check if oauth2-proxy binary actually exists after installation
- Validate nginx configuration before proceeding
- Verify services actually started (not just attempted to start)
- Add detailed error messages with troubleshooting commands

Final Verification:
- Check if ports 443 and oauth2-proxy port are actually listening
- Test authentication redirect (expect HTTP 302)
- Provide clear success/warning messages for each check
```

---

## References

- **oauth2-proxy Documentation**: https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/overview
- **AES Cipher Requirements**: https://en.wikipedia.org/wiki/Advanced_Encryption_Standard
- **Base64 Encoding**: 32 bytes → 43 base64 characters (32 * 4/3 ≈ 43)

---

---

## Additional Improvements (2026-01-14)

### 5. Static Files Permissions Safeguard

**Added to**: Step 7/8 in install.sh

**Issue**: CSS and JavaScript files fail to load (403 Forbidden) because nginx cannot access files in `/home/ubuntu/` due to default 750 permissions.

**Solution**:
```bash
# Step 7: Fix directory permissions for static files
chmod 755 /home/ubuntu

# Verify www-data can access
sudo -u www-data test -x /home/ubuntu
```

**Benefits**:
- Prevents CSS loading issues on fresh installs
- Automatically configured during installation
- Validated with clear success/failure messages

**Standalone Fix**: Use `scripts/fix-static-files-permissions.sh` for existing deployments

**Documentation**: See `docs/STATIC_FILES_PERMISSIONS.md` for detailed explanation

---

**Last Updated**: 2026-01-14
**Status**: ✅ Fixed and Deployed
**Tested By**: Claude Sonnet 4.5
**Production Ready**: YES
