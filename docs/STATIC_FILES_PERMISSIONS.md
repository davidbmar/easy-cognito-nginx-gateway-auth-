# Static Files Permissions Issue

**Date**: 2026-01-14
**Issue**: CSS and JavaScript files not loading when served by nginx using `alias` directive
**Status**: ✅ Fixed with automated safeguards

---

## Problem Summary

After deploying applications with static files (CSS, JS, images), browsers show missing CSS styles because nginx cannot serve the files. Browser console shows 403 Forbidden errors for static assets.

**Common symptoms**:
- Page loads but has no styling
- Browser console shows: `GET https://domain/static/style.css 403 (Forbidden)`
- Application works but looks broken (no CSS)

---

## Root Cause

### Technical Explanation

When nginx serves static files using the `alias` directive:

```nginx
location /deploy/static/ {
    alias /home/ubuntu/src/deploy-portal/static/;
}
```

nginx's worker process (running as `www-data` user) must:
1. Have read permission on the target files
2. Have execute permission on ALL parent directories in the path

### The Permission Chain

For nginx to serve `/home/ubuntu/src/deploy-portal/static/style.css`:

```
/home          (must have +x for www-data)
/home/ubuntu   (must have +x for www-data) ← COMMON FAILURE POINT
/home/ubuntu/src              (must have +x for www-data)
/home/ubuntu/src/deploy-portal (must have +x for www-data)
/home/ubuntu/src/deploy-portal/static (must have +x for www-data)
/home/ubuntu/src/deploy-portal/static/style.css (must have +r for www-data)
```

### Default Ubuntu Behavior

Ubuntu creates home directories with permissions `750` (drwxr-x---):
- Owner (ubuntu): full access
- Group (ubuntu): read + execute
- Others (www-data): **NO ACCESS** ❌

This prevents nginx from traversing the path to reach static files.

---

## Solution

### Automated Fix (Recommended)

The install script now automatically fixes this issue during installation:

```bash
# In scripts/install.sh (Step 7/8)
chmod 755 /home/ubuntu
```

This changes permissions to `755` (drwxr-xr-x):
- Owner (ubuntu): full access
- Group (ubuntu): read + execute
- Others (www-data): read + execute ✓

### Manual Fix for Existing Deployments

**Option 1: Run the fix script**
```bash
cd /path/to/easy-cognito-nginx-gateway-auth
sudo ./scripts/fix-static-files-permissions.sh
```

**Option 2: Manual command**
```bash
sudo chmod 755 /home/ubuntu
```

### Verification

```bash
# Check current permissions
ls -ld /home/ubuntu

# Should show: drwxr-xr-x (755)

# Test if www-data can access
sudo -u www-data test -r /home/ubuntu/src/deploy-portal/static/style.css && \
  echo "SUCCESS" || echo "FAILED"
```

---

## Security Considerations

### Is chmod 755 /home/ubuntu safe?

**Yes, this is safe and commonly used:**

1. **Read protection remains**: Users still cannot read each other's files
2. **Execute only**: 755 only allows traversing, not listing directory contents
3. **Standard practice**: Many web servers use this pattern
4. **Minimal exposure**: Only adds execute permission, not read

### What 755 allows:
- ✓ nginx can traverse `/home/ubuntu` to reach subdirectories
- ✓ Users can access their own files
- ✗ Users cannot list contents of `/home/ubuntu`
- ✗ Users cannot read files in `/home/ubuntu` directly

### Alternative Approaches (More Complex)

If you want to avoid changing `/home/ubuntu` permissions:

**Option 1: Move static files outside /home**
```bash
# Store static files in /var/www/static/
mkdir -p /var/www/static/deploy-portal
cp -r /home/ubuntu/src/deploy-portal/static/* /var/www/static/deploy-portal/
chown -R www-data:www-data /var/www/static

# Update nginx config
location /deploy/static/ {
    alias /var/www/static/deploy-portal/;
}
```

**Option 2: Use ACLs (Access Control Lists)**
```bash
sudo setfacl -m u:www-data:x /home/ubuntu
sudo setfacl -m u:www-data:x /home/ubuntu/src
# ... repeat for each directory
```

**Option 3: Add www-data to ubuntu group**
```bash
sudo usermod -a -G ubuntu www-data
# Then set group permissions instead
```

**We chose `chmod 755` because:**
- Simple and reliable
- Standard practice
- No additional dependencies (ACLs)
- Easy to understand and maintain

---

## Prevention in Install Script

### Added to install.sh

```bash
# Step 7: Fix directory permissions for static files
log_info "[7/8] Configuring directory permissions for static files..."

# Ensure nginx (www-data) can access /home/ubuntu for static file serving
if [ -d /home/ubuntu ]; then
    chmod 755 /home/ubuntu
    log_success "Set /home/ubuntu permissions to 755 (allows nginx to serve static files)"
else
    log_warning "/home/ubuntu directory not found (unusual), skipping permission fix"
fi

# Verify www-data can access the directory
if sudo -u www-data test -x /home/ubuntu 2>/dev/null; then
    log_success "Verified: www-data can access /home/ubuntu"
else
    log_warning "Warning: www-data cannot access /home/ubuntu (static files may not load)"
fi
```

### Benefits

1. **Automatic**: Every fresh install gets correct permissions
2. **Validated**: Script verifies www-data can access directory
3. **Logged**: Clear messages about what's happening
4. **Idempotent**: Safe to run multiple times

---

## Troubleshooting

### Check nginx error logs

```bash
sudo tail -f /var/log/nginx/error.log
```

Look for:
```
[error] **** open() "/home/ubuntu/src/.../static/style.css" failed (13: Permission denied)
```

### Debug permission chain

```bash
# Check each directory in the path
namei -l /home/ubuntu/src/deploy-portal/static/style.css

# Test as www-data user
sudo -u www-data test -r /home/ubuntu/src/deploy-portal/static/style.css
echo $?  # 0 = success, 1 = failed
```

### Common errors

**Error**: "403 Forbidden" for CSS files
**Cause**: `/home/ubuntu` has 750 permissions
**Fix**: `sudo chmod 755 /home/ubuntu`

**Error**: "404 Not Found" for CSS files
**Cause**: nginx location block missing or misconfigured
**Fix**: Add location block with correct `alias` path

**Error**: CSS loads but page still unstyled
**Cause**: Browser cache or incorrect CSS paths in HTML
**Fix**: Hard refresh (Ctrl+Shift+R), check paths in HTML source

---

## nginx Configuration Pattern

### Correct pattern for static files

```nginx
# Static files (no auth required)
location /deploy/static/ {
    alias /home/ubuntu/src/deploy-portal/static/;
    expires 1h;
    add_header Cache-Control "public, immutable";
}

# Application routes (auth required)
location / {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
    # ... proxy to application ...
}
```

### Why static files should NOT require auth

Static files (CSS, JS) should be accessible without authentication because:
1. **Browsers need them before JavaScript runs**: Auth redirects break asset loading
2. **No sensitive data**: CSS/JS are public assets
3. **Performance**: Avoid extra OAuth round-trips for every asset
4. **Standards**: OAuth redirects for images/CSS violate web standards

### Location block ordering

nginx processes location blocks in specific order:
1. Exact match: `location = /path`
2. Longest prefix match: `location /deploy/static/` beats `location /`
3. Regex match: `location ~* \.css$`

So this works correctly:
```nginx
location /deploy/static/ { }  # Matches first (longest prefix)
location / { }                # Catches everything else
```

---

## Testing After Fix

### 1. Test directory access
```bash
sudo -u www-data ls /home/ubuntu
# Should work without "Permission denied"
```

### 2. Test file access
```bash
sudo -u www-data cat /home/ubuntu/src/deploy-portal/static/style.css
# Should display CSS content
```

### 3. Test nginx
```bash
# Reload nginx
sudo systemctl reload nginx

# Test static file via nginx
curl -k https://localhost/deploy/static/style.css
# Should return CSS content, not 403
```

### 4. Test in browser
```
1. Open https://your-domain/
2. Open browser DevTools (F12) → Network tab
3. Refresh page
4. Check static files show "200 OK" status (not 403 or 404)
5. CSS should be visible
```

---

## Related Files

- **Install script**: `scripts/install.sh` (includes permission fix)
- **Fix script**: `scripts/fix-static-files-permissions.sh` (standalone fix)
- **nginx config**: `/etc/nginx/sites-available/auth-gateway` (location blocks)
- **Troubleshooting**: See `docs/NGINX_CONFIGURATION_CHANGES.md`

---

## Commit History

- `804868b` - Document deploy-portal as default landing page routing change
- `[pending]` - Add static files permissions safeguards to install script

---

**Last Updated**: 2026-01-14
**Status**: ✅ Fixed with automated safeguards in install script
**Prevention**: Automatically handled by install.sh Step 7/8
