# Nginx Configuration Changes - Summary

## Change #2: Deploy Portal as Default Landing Page (2026-01-14)

**Date**: 2026-01-14
**Instance**: 44.248.103.166
**Issue**: Users were immediately redirected to SSH terminal after login instead of seeing a landing page

### Root Cause
The nginx root path (`/`) was configured to proxy to `ssh_terminal` (port 8080), causing users to land directly on the terminal after Cognito authentication.

### Solution
Changed root path to proxy to `deploy_portal` (port 5000) and created explicit `/terminal/` route for SSH Helper.

### Changes Made
```nginx
# Root location now routes to Deploy Portal (landing page)
location / {
    proxy_pass http://deploy_portal;  # Was: http://ssh_terminal
}

# New explicit route for SSH Helper
location /terminal/ {
    rewrite ^/terminal/(.*)$ /$1 break;
    proxy_pass http://ssh_terminal;
}

location = /terminal {
    return 301 /terminal/;
}
```

### Updated Routing (44.248.103.166)
| URL Path | Backend Service | Port | Auth Required |
|----------|----------------|------|---------------|
| `/` | Deploy Portal | 5000 | ✅ Yes |
| `/terminal/` | SSH Helper | 8080 | ✅ Yes |
| `/cloner/` | Website Cloner | 3000 | ✅ Yes |
| `/health` | Health Check | - | ❌ No |
| `/oauth2/` | OAuth2 Proxy | 4180 | ❌ No |

### User Experience Improvement
**Before**: Login → Immediately land on terminal
**After**: Login → Land on Deploy Portal dashboard → Navigate to tools from there

---

## Change #1: IP Address Update (2026-01-13)

**Date**: 2026-01-13
**Instance**: 16.148.76.153
**Issue**: EC2 reboot changed IP from 52.43.35.1 to 16.148.76.153

## Changes Made to `/etc/nginx/sites-available/auth-gateway`

### 1. Updated Server Name
```nginx
server_name 16.148.76.153;  # Was: 52.43.35.1
```

### 2. Added Deploy Portal Upstream
```nginx
upstream deploy_portal {
    server 127.0.0.1:5000;
}
```

### 3. Added Static Files Location
```nginx
# Static files for Deploy Portal (no auth required for CSS/JS)
location /deploy/static/ {
    alias /home/ubuntu/src/deploy-portal/static/;
    expires 1h;
    add_header Cache-Control "public, immutable";
}
```

### 4. Added /deploy Location Block
```nginx
# Protected: Deploy Portal - /deploy routes
location /deploy {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $auth_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $auth_cookie;

    proxy_pass http://deploy_portal;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
}
```

### 5. Changed Root Location
```nginx
# Changed FROM: proxy_pass http://ssh_terminal;
# Changed TO:   proxy_pass http://deploy_portal;
location / {
    # ... authentication headers ...
    proxy_pass http://deploy_portal;  # Now routes to Deploy Portal
    # ... rest of config ...
}
```

### 6. Added SSH Helper Location Block
```nginx
# Protected: SSH Helper (Web Terminal)
location /ssh/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $auth_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $auth_cookie;

    # Rewrite /ssh/ to / for the backend
    rewrite ^/ssh/(.*)$ /$1 break;

    proxy_pass http://ssh_terminal;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
}

# Redirect /ssh (without trailing slash) to /ssh/
location = /ssh {
    return 301 /ssh/;
}
```

### 7. Added HTTP to HTTPS Redirect
```nginx
# HTTP Server Block - Redirects all traffic to HTTPS
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name 16.148.76.153;

    # Redirect all HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

# HTTPS Server Block - Contains all application routing
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    server_name 16.148.76.153;

    # ... all location blocks ...
}
```

## Where to Commit These Changes

### ❌ DO NOT Commit System Files
**These files should NOT be added to git:**
- `/etc/nginx/sites-available/auth-gateway` (deployed config)
- `/etc/oauth2-proxy/config.cfg` (contains secrets!)

These are managed by deployment scripts and contain environment-specific values.

### ✅ Commit to Templates

**Repository**: `/home/ubuntu/src/easy-cognito-nginx-gateway-auth/`

**File to Update**: `config/nginx/auth-gateway.conf.template`

This template should reflect the production configuration pattern:
1. Include `deploy_portal` upstream definition
2. Include `/deploy/static/` location for CSS/JS
3. Include `/deploy` location block for Deploy Portal routes
4. Root `/` location should proxy to `deploy_portal` (not `ssh_terminal`)
5. Use template variables for IP addresses: `${GATEWAY_IP}`

```bash
cd /home/ubuntu/src/easy-cognito-nginx-gateway-auth
# Edit config/nginx/auth-gateway.conf.template
git add config/nginx/auth-gateway.conf.template
git commit -m "Update nginx template: root routes to deploy-portal, add /deploy routes

- Changed root location (/) to proxy to deploy_portal instead of ssh_terminal
- Added deploy_portal upstream definition
- Added /deploy location block for Deploy Portal routes
- Added /deploy/static/ location for CSS/JS files
- Use template variable for server_name

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

### ✅ Already Committed

**Repository**: `/home/ubuntu/src/`

Already committed documentation changes:
- `CLAUDE.md` (updated IP addresses)
- `DEPLOYMENT_STATUS.md` (updated IP addresses)

Commit hash: `c3124cc`

**Repository**: `/home/ubuntu/`

Already committed new documentation:
- `CLAUDE.md` (platform overview)
- `AUTHENTICATION_TEST_RESULTS.md` (test results)

Commit hash: `720f21a`

## Current Routing Configuration

| URL Path | Backend Service | Port | Auth Required |
|----------|----------------|------|---------------|
| `/` | Deploy Portal | 5000 | ✅ Yes |
| `/deploy` | Deploy Portal | 5000 | ✅ Yes |
| `/deploy/` | Deploy Portal | 5000 | ✅ Yes |
| `/deploy/static/` | Static Files | - | ❌ No |
| `/ssh/` | SSH Helper | 8080 | ✅ Yes |
| `/cloner/` | Website Cloner | 3000 | ✅ Yes |
| `/health` | Health Check | - | ❌ No |
| `/oauth2/` | OAuth2 Proxy | 4180 | ❌ No |

## Testing

```bash
# Test root redirects to Deploy Portal
curl -k -L https://16.148.76.153/

# Test /deploy redirects to Deploy Portal
curl -k -L https://16.148.76.153/deploy

# Test static files are accessible
curl -k https://16.148.76.153/deploy/static/style.css

# Test authentication flow
curl -k -I https://16.148.76.153/
# Should redirect to Cognito login
```

## Notes

- All routes require authentication except `/deploy/static/`, `/health`, and `/oauth2/`
- Authentication handled by oauth2-proxy (port 4180)
- oauth2-proxy validates AWS Cognito tokens
- User info passed to backend apps via headers: `X-User-Email`, `X-Auth-Request-User`
- Backend apps trust nginx headers (no auth code in apps)
