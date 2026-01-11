# Troubleshooting Guide

Common issues and solutions for the Easy Cognito Nginx Gateway Auth.

## Quick Diagnosis

### Check Service Status

```bash
# Check if services are running
sudo systemctl status nginx
sudo systemctl status oauth2-proxy

# Check if ports are listening
sudo ss -tlnp | grep -E ':(80|443|4180)'
```

### View Logs

```bash
# oauth2-proxy logs
sudo journalctl -u oauth2-proxy -n 100 -f

# nginx error logs
sudo tail -100 /var/log/nginx/error.log

# nginx access logs
sudo tail -100 /var/log/nginx/access.log
```

### Test Configuration

```bash
# Test nginx configuration
sudo nginx -t

# Test oauth2-proxy configuration
/usr/local/bin/oauth2-proxy --config=/etc/oauth2-proxy/config.cfg --version
```

## Common Issues

### Issue: Redirect Loop (Infinite Redirects)

**Symptoms:**
- Browser keeps redirecting
- Error: "Too many redirects"
- Access logs show repeated requests to `/oauth2/start`

**Causes and Solutions:**

#### 1. oauth2-proxy Not Running

Check if oauth2-proxy is running:
```bash
sudo systemctl status oauth2-proxy
```

If not running:
```bash
sudo systemctl start oauth2-proxy
sudo journalctl -u oauth2-proxy -n 50
```

#### 2. Wrong Cookie Domain

Check cookie domain in `/etc/oauth2-proxy/config.cfg`:
```ini
cookie_domains = ["your-domain.com"]
```

Must match the domain you're accessing. If using IP:
```ini
cookie_domains = ["192.168.1.100"]
```

After changing, restart:
```bash
sudo systemctl restart oauth2-proxy
```

#### 3. oauth2-proxy Not Accessible

Test oauth2-proxy directly:
```bash
curl -I http://localhost:4180/oauth2/auth
```

Should return HTTP 401 or 403 (not connection refused).

#### 4. nginx auth_request Misconfigured

Check `/etc/nginx/sites-available/auth-gateway`:
```nginx
location /oauth2/ {
    proxy_pass http://127.0.0.1:4180;
    # Must NOT have auth_request here
}

location / {
    auth_request /oauth2/auth;  # This is correct
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
    proxy_pass http://127.0.0.1:3000;
}
```

### Issue: 502 Bad Gateway

**Symptoms:**
- nginx returns "502 Bad Gateway"
- Can't access application

**Causes and Solutions:**

#### 1. Application Not Running

Check if your application is running:
```bash
# Replace 3000 with your app port
curl http://localhost:3000
```

If connection refused, start your application:
```bash
# Example for Node.js
cd /path/to/your/app
npm start
```

#### 2. Wrong Port in nginx Config

Check `/etc/nginx/sites-available/auth-gateway`:
```nginx
location / {
    proxy_pass http://127.0.0.1:3000;  # Check this port
}
```

Must match your application's port.

#### 3. oauth2-proxy Not Running

If 502 on `/oauth2/` paths:
```bash
sudo systemctl status oauth2-proxy
sudo systemctl start oauth2-proxy
```

### Issue: SSL Certificate Errors

**Symptoms:**
- Browser shows "Your connection is not private"
- "NET::ERR_CERT_AUTHORITY_INVALID"

**Solutions:**

#### For Self-Signed Certificates (Development)

1. Click "Advanced" in browser
2. Click "Proceed to [domain] (unsafe)"
3. This is normal for self-signed certs

#### For Production

Use Let's Encrypt:
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

#### Verify Certificate Files Exist

```bash
ls -la /etc/nginx/ssl/selfsigned.crt
ls -la /etc/nginx/ssl/selfsigned.key
```

If missing, regenerate:
```bash
sudo ./scripts/setup-ssl.sh --domain=your-domain.com
sudo systemctl reload nginx
```

### Issue: "Invalid Redirect URI"

**Symptoms:**
- After clicking "Sign in", Cognito shows error
- "Error: Invalid redirect_uri"

**Cause:** Callback URL not registered in Cognito

**Solution:**

1. Go to AWS Cognito Console
2. Select your User Pool
3. App Integration → App Clients → Your Client
4. Under "Hosted UI", edit "Allowed callback URLs"
5. Add: `https://your-domain.com/oauth2/callback`
6. Click "Save changes"

Also check `/etc/oauth2-proxy/config.cfg`:
```ini
redirect_url = "https://your-domain.com/oauth2/callback"
```

Must exactly match what's in Cognito (including protocol, domain, path).

### Issue: "Sign in failed" or "Authentication Failed"

**Symptoms:**
- After entering credentials, shows error
- oauth2-proxy logs show authentication failure

**Causes and Solutions:**

#### 1. Wrong Client ID or Secret

Check `/etc/oauth2-proxy/config.cfg`:
```ini
client_id = "your-client-id"
client_secret = "your-client-secret"
```

Get correct values from:
- Cognito Console → User Pool → App Integration → App Clients

After fixing:
```bash
sudo systemctl restart oauth2-proxy
```

#### 2. Wrong OIDC Issuer URL

Check `/etc/oauth2-proxy/config.cfg`:
```ini
oidc_issuer_url = "https://cognito-idp.REGION.amazonaws.com/POOL_ID"
```

Must match:
- `REGION`: Your AWS region (e.g., us-east-1)
- `POOL_ID`: Your User Pool ID (e.g., us-east-1_XXXXXXXXX)

#### 3. User Not Confirmed

Check user status in Cognito:
```bash
aws cognito-idp admin-get-user \
  --user-pool-id us-east-1_XXXXXXXXX \
  --username test@example.com
```

If `UserStatus` is not `CONFIRMED`, confirm the user:
```bash
aws cognito-idp admin-confirm-sign-up \
  --user-pool-id us-east-1_XXXXXXXXX \
  --username test@example.com
```

Or in Cognito Console:
- Users → Select user → Actions → Confirm account

#### 4. Incorrect Scopes

Check `/etc/oauth2-proxy/config.cfg`:
```ini
scope = "openid email profile"
```

Required scopes:
- `openid` - MUST be included
- `email` - If you want user email
- `profile` - If you want user profile

Check Cognito app client scopes:
- Cognito Console → App Integration → App Clients → Your Client
- Make sure "OpenID", "Email", "Profile" are checked

### Issue: Static Assets Return 404 After Login

**Symptoms:**
- Page loads after login but CSS/JS missing
- Browser console shows 404 for `/styles.css`, `/app.js`
- Page appears broken/unstyled

**Cause:** Absolute paths in HTML don't account for path prefix

**Solution:**

If app is at `/myapp/`, use relative paths in HTML:

```html
<!-- Wrong -->
<link rel="stylesheet" href="/styles.css">
<script src="/app.js"></script>

<!-- Correct -->
<link rel="stylesheet" href="./styles.css">
<script src="./app.js"></script>
```

Or configure your app with base path:
```javascript
// Express example
app.use('/myapp', express.static('public'));
```

### Issue: Cookies Not Being Set

**Symptoms:**
- Login succeeds but immediately redirected back to login
- No `_oauth2_proxy` cookie in browser

**Causes and Solutions:**

#### 1. Cookie Secure Flag with HTTP

If using HTTP (not HTTPS), set in `/etc/oauth2-proxy/config.cfg`:
```ini
cookie_secure = false
```

**Note:** Only for development! Production must use HTTPS.

#### 2. Wrong Cookie Domain

Check cookie domain matches access domain:
```ini
# If accessing via IP
cookie_domains = ["192.168.1.100"]

# If accessing via domain
cookie_domains = ["your-domain.com"]
```

#### 3. Cookie SameSite Policy

Try changing SameSite:
```ini
cookie_samesite = "lax"
```

#### 4. Browser Blocking Third-Party Cookies

Check browser settings. Some privacy extensions block cookies.

### Issue: "User Not Authorized" or "Access Denied"

**Symptoms:**
- Login succeeds but shows "Access Denied"
- oauth2-proxy logs show authorization failure

**Causes and Solutions:**

#### 1. Email Domain Restrictions

Check `/etc/oauth2-proxy/config.cfg`:
```ini
email_domains = ["example.com"]
```

If restricting domains, user must have email from allowed domain.

To allow all domains:
```ini
email_domains = ["*"]
```

#### 2. Group Restrictions

If configured with allowed groups, user must be in group:
```ini
allowed_groups = ["admins", "users"]
```

Check user's groups in Cognito or remove restriction.

### Issue: Session Expires Too Quickly

**Symptom:**
- User gets logged out frequently
- Must re-authenticate often

**Solution:**

Increase session duration in `/etc/oauth2-proxy/config.cfg`:
```ini
# Cookie expiration (how long session lasts)
cookie_expire = "168h"  # 1 week

# Token refresh interval
cookie_refresh = "4h"

# Cognito token lifetime (must be configured in Cognito)
```

Also check Cognito token lifetime:
- Cognito Console → User Pool → App Integration → App Clients → Your Client
- Refresh token expiration: 30 days (default)

After changing:
```bash
sudo systemctl restart oauth2-proxy
```

### Issue: nginx Won't Start

**Symptoms:**
- `systemctl start nginx` fails
- `nginx -t` shows errors

**Common Causes:**

#### 1. Port Already in Use

Check what's using ports 80/443:
```bash
sudo ss -tlnp | grep -E ':(80|443)'
```

Stop conflicting service:
```bash
sudo systemctl stop apache2  # If Apache is running
```

Or change nginx ports in config.

#### 2. Syntax Error in Config

Test configuration:
```bash
sudo nginx -t
```

Error message will show line number:
```
nginx: [emerg] invalid parameter "..." in /etc/nginx/sites-available/auth-gateway:42
```

Edit and fix:
```bash
sudo nano /etc/nginx/sites-available/auth-gateway
```

#### 3. SSL Certificate Files Missing

Check if files exist:
```bash
ls -la /etc/nginx/ssl/selfsigned.crt
ls -la /etc/nginx/ssl/selfsigned.key
```

If missing, regenerate:
```bash
sudo ./scripts/setup-ssl.sh --domain=your-domain.com
```

#### 4. Wrong File Permissions

Fix permissions:
```bash
sudo chmod 644 /etc/nginx/ssl/selfsigned.crt
sudo chmod 600 /etc/nginx/ssl/selfsigned.key
sudo chown root:root /etc/nginx/ssl/*
```

### Issue: oauth2-proxy Won't Start

**Symptoms:**
- `systemctl start oauth2-proxy` fails
- Service crashes immediately

**Diagnosis:**

Check logs:
```bash
sudo journalctl -u oauth2-proxy -n 50
```

**Common Causes:**

#### 1. Invalid Configuration

Test config manually:
```bash
/usr/local/bin/oauth2-proxy --config=/etc/oauth2-proxy/config.cfg --version
```

Look for error messages about config.

#### 2. Port 4180 Already in Use

Check port:
```bash
sudo ss -tlnp | grep :4180
```

Kill process using port or change port in config.

#### 3. Missing Cookie Secret

Generate cookie secret:
```bash
openssl rand -base64 32
```

Add to `/etc/oauth2-proxy/config.cfg`:
```ini
cookie_secret = "generated-secret-here"
```

#### 4. Invalid OIDC Issuer URL

Test OIDC discovery:
```bash
curl https://cognito-idp.REGION.amazonaws.com/POOL_ID/.well-known/openid-configuration
```

Should return JSON with OIDC configuration.

### Issue: Can't Access /oauth2/ Endpoints

**Symptoms:**
- `/oauth2/sign_in` returns 404
- `/oauth2/callback` returns 404

**Solution:**

Check nginx config has oauth2 location:
```nginx
location /oauth2/ {
    proxy_pass http://127.0.0.1:4180;
    proxy_set_header Host $host;
}
```

Make sure it's BEFORE the `location /` block.

Test nginx config and reload:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Issue: Application Not Receiving User Headers

**Symptoms:**
- Application can't see `X-User-Email` header
- User info not passed to app

**Solution:**

Check nginx config includes auth header passing:
```nginx
location / {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    # These lines extract and pass headers
    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $user $upstream_http_x_auth_request_user;
    proxy_set_header X-User-Email $email;
    proxy_set_header X-User $user;

    proxy_pass http://127.0.0.1:3000;
}
```

Check oauth2-proxy config:
```ini
pass_user_headers = true
set_xauthrequest = true
```

Test from application:
```javascript
// Node.js example
console.log('Headers:', req.headers);
console.log('User email:', req.headers['x-user-email']);
```

## Debugging Steps

### Enable Debug Logging

#### oauth2-proxy Debug Mode

Add to `/etc/oauth2-proxy/config.cfg`:
```ini
logging_compress = false
logging_local_time = true
logging_max_age = 7
logging_max_backups = 3
logging_max_size = 100

# Add debug logging
request_logging = true
auth_logging = true
```

Restart and watch logs:
```bash
sudo systemctl restart oauth2-proxy
sudo journalctl -u oauth2-proxy -f
```

#### nginx Debug Logging

Add to nginx config (temporarily):
```nginx
error_log /var/log/nginx/error.log debug;
```

Reload and watch:
```bash
sudo systemctl reload nginx
sudo tail -f /var/log/nginx/error.log
```

**Warning:** Debug logs are verbose. Disable after troubleshooting.

### Test Authentication Flow Manually

#### Step 1: Test oauth2-proxy Auth Endpoint

```bash
curl -I http://localhost:4180/oauth2/auth
```

Expected: HTTP 401 or 403 (unauthenticated)

#### Step 2: Test nginx to oauth2-proxy

```bash
curl -I -k https://localhost/oauth2/auth
```

Expected: HTTP 401 and redirect header

#### Step 3: Test Full Redirect Flow

```bash
curl -I -k -L --max-redirs 0 https://localhost/
```

Should see redirect to Cognito login page.

### Check Network Connectivity

#### Test Cognito Connectivity

```bash
curl https://cognito-idp.REGION.amazonaws.com/POOL_ID/.well-known/openid-configuration
```

Should return JSON configuration.

#### Test DNS Resolution

```bash
nslookup your-domain.com
dig your-domain.com
```

Should resolve to your server's IP.

## Performance Issues

### Slow Authentication

**Cause:** DNS resolution delays

**Solution:** Configure local DNS caching:
```bash
sudo apt install -y dnsmasq
```

### High Memory Usage

**oauth2-proxy:** Normal usage is 10-50 MB

**nginx:** Normal usage is 10-20 MB per worker

Check memory:
```bash
ps aux | grep -E 'nginx|oauth2-proxy'
```

If excessive, check for:
- Memory leaks (update to latest version)
- Too many simultaneous connections
- Large cookie sizes (use Redis session storage)

## Getting More Help

If still having issues:

1. **Collect logs:**
   ```bash
   sudo journalctl -u oauth2-proxy -n 200 > oauth2-proxy.log
   sudo tail -200 /var/log/nginx/error.log > nginx-error.log
   sudo tail -200 /var/log/nginx/access.log > nginx-access.log
   ```

2. **Collect configuration:**
   ```bash
   cat /etc/oauth2-proxy/config.cfg | grep -v secret > config-sanitized.txt
   cat /etc/nginx/sites-available/auth-gateway > nginx-config.txt
   ```

3. **Open GitHub issue** with:
   - Description of problem
   - Steps to reproduce
   - Error messages from logs
   - Sanitized configurations (remove secrets!)
   - Output of `./scripts/test-auth.sh`

## Useful Commands Reference

```bash
# Service management
sudo systemctl status oauth2-proxy
sudo systemctl start oauth2-proxy
sudo systemctl stop oauth2-proxy
sudo systemctl restart oauth2-proxy
sudo systemctl status nginx
sudo systemctl reload nginx

# Logs
sudo journalctl -u oauth2-proxy -f
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# Configuration testing
sudo nginx -t
/usr/local/bin/oauth2-proxy --config=/etc/oauth2-proxy/config.cfg --version

# Port checking
sudo ss -tlnp | grep -E ':(80|443|4180)'
sudo netstat -tlnp | grep -E ':(80|443|4180)'

# Process checking
ps aux | grep oauth2-proxy
ps aux | grep nginx
```

## Related Documentation

- **[Configuration Guide](CONFIGURATION.md)** - Detailed configuration options
- **[Architecture](ARCHITECTURE.md)** - How the system works
- **[Production Deployment](PRODUCTION.md)** - Production best practices
