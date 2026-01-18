# Scripts Directory

This directory contains installation, configuration, and maintenance scripts for the Easy Cognito Nginx Gateway Auth system.

## Installation Scripts

### `install.sh`
**Main installation script** - Sets up the complete authentication gateway stack.

**Usage:**
```bash
sudo ./install.sh \
  --domain=example.com \
  --cognito-region=us-east-1 \
  --cognito-pool-id=us-east-1_XXXXXXXXX \
  --cognito-client-id=YYYYYYYY \
  --cognito-client-secret=ZZZZZZZZ \
  --app-port=3000
```

**What it does:**
1. Installs dependencies (nginx, wget, curl, jq)
2. Installs oauth2-proxy binary
3. Generates SSL certificates (self-signed or Let's Encrypt)
4. Configures oauth2-proxy with Cognito settings
5. Configures nginx with auth_request
6. Sets up systemd service
7. Starts all services
8. **NEW:** Validates configuration automatically

**Options:**
- `--app-path=/path` - Custom URL path (default: `/`)
- `--oauth2-port=4180` - Custom oauth2-proxy port
- `--skip-ssl` - Skip SSL certificate generation
- `--skip-cognito-validation` - Skip AWS Cognito validation

---

### `setup-oauth2-proxy.sh`
Installs the oauth2-proxy binary for the correct architecture.

**Usage:**
```bash
sudo ./setup-oauth2-proxy.sh
```

**What it does:**
- Detects system architecture (amd64 or arm64)
- Downloads oauth2-proxy v7.5.1 from GitHub releases
- Installs to `/usr/local/bin/oauth2-proxy`
- Makes binary executable

---

### `setup-ssl.sh`
Generates SSL certificates for HTTPS.

**Usage:**
```bash
sudo ./setup-ssl.sh --domain=example.com
```

**Options:**
- `--self-signed` - Generate self-signed certificate (default)
- `--letsencrypt` - Use Let's Encrypt (requires public domain)

---

## Maintenance Scripts

### `validate-oauth2-config.sh` ✨ NEW
**Comprehensive configuration validator** - Checks for common misconfigurations.

**Usage:**
```bash
./validate-oauth2-config.sh
```

**What it checks:**
- ✅ Config file exists
- ✅ oauth2-proxy binary installed
- ✅ **Header forwarding settings** (`set_xauthrequest`, `pass_user_headers`)
- ✅ Provider configuration (OIDC)
- ✅ Cookie configuration
- ✅ systemd service status
- ✅ Port listening
- ✅ nginx integration

**Exit codes:**
- `0` - All checks passed
- `1` - Errors found (requires fix)

**Example output:**
```
[✓] Config file found: /etc/oauth2-proxy/config.cfg
[✓] oauth2-proxy installed: oauth2-proxy v7.4.0
[✓] set_xauthrequest = true
[✓] pass_user_headers = true
...
All checks passed! ✨
```

---

### `fix-oauth2-headers.sh` ✨ NEW
**Quick fix for missing header forwarding settings**.

**When to use:**
- Applications show "unknown@unknown.com" instead of real email
- Users not being identified correctly
- `validate-oauth2-config.sh` reports missing header settings

**Usage:**
```bash
sudo ./fix-oauth2-headers.sh
```

**What it does:**
1. Backs up current config
2. Adds missing header forwarding settings:
   - `set_xauthrequest = true`
   - `pass_user_headers = true`
   - `pass_authorization_header = true`
3. Validates new config
4. Restarts oauth2-proxy service

**Safety:**
- Creates timestamped backup before changes
- Validates config before applying
- Rolls back if validation fails
- Non-destructive (only adds missing settings)

---

### `test-auth.sh`
Tests the authentication flow end-to-end.

**Usage:**
```bash
./test-auth.sh https://example.com
```

---

## Common Issues and Solutions

### Issue: Applications show "unknown@unknown.com"

**Symptom:** The authenticated user's email doesn't appear in applications.

**Diagnosis:**
```bash
./validate-oauth2-config.sh
```

**Fix:**
```bash
sudo ./fix-oauth2-headers.sh
```

**Then:**
1. Clear browser cookies or visit `/oauth2/sign_out`
2. Log in again
3. Email should now display correctly

---

### Issue: oauth2-proxy not starting

**Check service status:**
```bash
sudo systemctl status oauth2-proxy
```

**View logs:**
```bash
sudo journalctl -u oauth2-proxy -n 50
```

**Common causes:**
- Invalid configuration syntax
- Missing client secret
- Wrong Cognito pool ID
- Port already in use

**Validate config:**
```bash
./validate-oauth2-config.sh
```

---

### Issue: nginx auth_request not working

**Check nginx config:**
```bash
sudo nginx -t
```

**View nginx logs:**
```bash
sudo tail -f /var/log/nginx/error.log
```

**Ensure oauth2-proxy is running:**
```bash
curl -I http://localhost:4180/ping
```

---

## Script Development

### Adding New Validation Checks

Edit `validate-oauth2-config.sh` and add new checks following this pattern:

```bash
log_info "Checking new setting..."

if grep -q "^new_setting *= *true" "$CONFIG_FILE"; then
    log_success "new_setting = true"
else
    log_error "Missing: new_setting = true"
    ERRORS=$((ERRORS + 1))
fi
```

### Testing Scripts

Always test scripts in a safe environment before production:

```bash
# Test validation script
./validate-oauth2-config.sh

# Test fix script with --dry-run (if implemented)
sudo ./fix-oauth2-headers.sh --dry-run

# Test install script with minimal config
sudo ./install.sh --domain=test.local --skip-ssl ...
```

---

## Troubleshooting Reference

| Problem | Script to Run | Expected Outcome |
|---------|---------------|------------------|
| Unknown email in apps | `validate-oauth2-config.sh` then `fix-oauth2-headers.sh` | Headers fixed, email shows correctly |
| Post-installation check | `validate-oauth2-config.sh` | All checks pass |
| Service not starting | `systemctl status oauth2-proxy` | View error logs |
| Config syntax error | `/usr/local/bin/oauth2-proxy --config=/etc/oauth2-proxy/config.cfg --version` | Validates syntax |

---

## Architecture Overview

```
User Browser
     ↓ HTTPS
nginx (port 443)
     ↓ auth_request
oauth2-proxy (port 4180)
     ↓ validates session
     ↓ (if no session) redirects to →  AWS Cognito
     ↓ (if valid session) sets headers
     ← X-Auth-Request-Email
     ← X-Auth-Request-User
     ↓
Application (port varies)
```

**Critical headers:**
- `X-Auth-Request-Email` - User's email address
- `X-Auth-Request-User` - User's unique ID (Cognito sub)

These headers are set by oauth2-proxy **only if** `set_xauthrequest = true` and `pass_user_headers = true`.

---

## Version History

### v1.1.0 (2026-01-14)
- ✨ Added `validate-oauth2-config.sh` - Configuration validator
- ✨ Added `fix-oauth2-headers.sh` - Quick fix for header issues
- 🔧 Updated `install.sh` to include post-installation validation
- 📝 Added comprehensive troubleshooting documentation

### v1.0.0
- Initial release with basic installation scripts

---

## Contributing

When adding new scripts:
1. Add clear usage documentation
2. Include error handling
3. Add validation checks
4. Update this README
5. Test in staging environment first

---

## Support

If scripts fail or you encounter issues:

1. Run validation: `./validate-oauth2-config.sh`
2. Check service logs: `sudo journalctl -u oauth2-proxy -f`
3. Review nginx logs: `sudo tail -f /var/log/nginx/error.log`
4. Check GitHub issues: https://github.com/oauth2-proxy/oauth2-proxy/issues
