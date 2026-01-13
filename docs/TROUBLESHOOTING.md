# Troubleshooting Guide

## Common Issues and Solutions

### 403 Forbidden on OAuth2 Callback

**Symptoms:**
- Users get 403 Forbidden error when trying to sign in
- The error occurs at `/oauth2/callback` after authenticating with Cognito
- oauth2-proxy logs show: `Error redeeming code during OAuth2 callback: token exchange failed`
- The URL shows mixed HTTP/HTTPS in the state parameter

**Root Cause:**
When the nginx server has both HTTP (port 80) and HTTPS (port 443) listeners in the same server block, users who initially access the site via HTTP will trigger an OAuth flow where:
1. nginx receives the initial request on port 80 (HTTP)
2. `$scheme` variable is set to `http`
3. oauth2-proxy creates a state parameter containing `http://domain/...`
4. After authentication, Cognito redirects back to `https://domain/oauth2/callback`
5. The state parameter mismatch causes oauth2-proxy to reject the callback with 403

**Solution:**
Split the nginx configuration into two separate server blocks:
1. **HTTP Server (port 80)**: Immediately redirects all traffic to HTTPS
2. **HTTPS Server (port 443)**: Handles all application traffic and OAuth flows

This ensures all OAuth flows start and complete over HTTPS, preventing state parameter mismatches.

**Example Configuration:**
```nginx
# HTTP Server - Redirect to HTTPS
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name your-domain.com;

    return 301 https://$host$request_uri;
}

# HTTPS Server - Main application
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /path/to/cert;
    ssl_certificate_key /path/to/key;

    server_name your-domain.com;

    # ... rest of configuration
}
```

**Verification:**
```bash
# Test HTTP redirect
curl -I http://your-domain.com/
# Should return: HTTP/1.1 301 Moved Permanently
# Location: https://your-domain.com/

# Check oauth2-proxy logs for HTTPS redirects
sudo journalctl -u oauth2-proxy | grep "start?rd="
# Should show: rd=https:// (not rd=http://)
```

### OAuth2 Proxy Not Starting

**Symptoms:**
- oauth2-proxy service fails to start
- Error: "could not build provider"
- OIDC discovery fails

**Solutions:**
1. Verify OIDC issuer URL is correct:
   ```bash
   # For AWS Cognito, should be:
   # https://cognito-idp.REGION.amazonaws.com/POOL_ID
   curl -s https://cognito-idp.us-east-1.amazonaws.com/POOL_ID/.well-known/openid-configuration
   ```

2. Check client ID and secret are correct

3. Verify network connectivity to Cognito

### Cookie Domain Mismatch

**Symptoms:**
- Authentication works but cookies aren't set
- Users have to re-authenticate frequently
- Warning in logs: "request host did not match any of the specific cookie domains"

**Solution:**
Update oauth2-proxy config to match your domain:
```
cookie_domains = ["your-domain.com"]
```

For IP-based access:
```
cookie_domains = ["52.43.35.1"]
```

## Debugging Tips

### Enable Verbose Logging

**oauth2-proxy:**
Add to config:
```
request_logging = true
auth_logging = true
standard_logging = true
```

**nginx:**
```nginx
error_log /var/log/nginx/error.log debug;
```

### Trace Authentication Flow

```bash
# Watch oauth2-proxy logs in real-time
sudo journalctl -u oauth2-proxy -f

# Watch nginx access logs
sudo tail -f /var/log/nginx/access.log

# Check for auth_request interactions
sudo grep "auth_request" /var/log/nginx/error.log
```
