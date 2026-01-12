# Integration Guide - Multi-Application Deployment

This guide shows how to deploy multiple applications behind the authentication gateway.

## Overview

The authentication gateway acts as a reverse proxy that:
1. Handles all authentication via AWS Cognito
2. Sets user headers (`X-User-Email`, `X-Auth-Request-User`)
3. Proxies authenticated requests to backend applications

Applications receive user information via headers and **do not** implement authentication themselves.

## Architecture

```
Internet (HTTPS)
      ↓
┌─────────────────────────────────────────────────┐
│  Gateway: 52.43.35.1 (nginx + oauth2-proxy)    │
│  - SSL/TLS termination                         │
│  - AWS Cognito authentication                  │
│  - Sets X-User-Email header                    │
└────────┬────────────────────────────────────────┘
         │
         ├─→ / → SSH Helper (port 8080)
         │        Web-based terminal
         │
         ├─→ /cloner/ → Website Cloner (port 3000)
         │              Website cloning tool
         │
         └─→ /yourapp/ → Your Application (port XXXX)
                        Add more apps here!
```

## Current Deployment (2026-01-12)

**Production Environment: https://52.43.35.1/**

| Path | Application | Backend Port | Status |
|------|-------------|--------------|--------|
| `/` | SSH Helper | 8080 | ✅ Running |
| `/cloner/` | Website Cloner | 3000 | ⏸️ Ready |
| `/oauth2/` | OAuth2 Proxy | 4180 | ✅ Running |

**Configuration Files:**
- nginx: `/etc/nginx/sites-available/auth-gateway`
- oauth2-proxy: `/etc/oauth2-proxy/config.cfg`
- ssh-helper service: `/etc/systemd/system/ssh-helper.service`

## Adding a New Application

### Step 1: Deploy Your Application

Your application should:
- ✅ Listen on a local port (e.g., 3001)
- ✅ Read user info from headers:
  ```javascript
  const userEmail = req.headers['x-user-email'] || 'anonymous';
  const username = req.headers['x-auth-request-user'] || 'anonymous';
  ```
- ❌ NOT implement authentication (gateway handles it)

### Step 2: Configure nginx

Edit `/etc/nginx/sites-available/auth-gateway`:

```nginx
# Add upstream
upstream my_app {
    server 127.0.0.1:3001;
}

# Inside server block, add location
location /myapp/ {
    # Authentication check
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    # Extract user info from oauth2-proxy
    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;

    # Pass to application
    proxy_set_header X-User $user;
    proxy_set_header X-User-Email $email;

    # Strip /myapp/ prefix before proxying
    rewrite ^/myapp/(.*)$ /$1 break;
    proxy_pass http://my_app;

    # Standard proxy headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSocket support (if needed)
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

### Step 3: Test and Reload

```bash
# Test nginx config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# Access your app
https://52.43.35.1/myapp/
```

## Example: SSH Helper Integration

### Configuration

File: `/etc/nginx/sites-available/auth-gateway`

```nginx
upstream ssh_terminal {
    server 127.0.0.1:8080;
}

server {
    listen 443 ssl;
    server_name 52.43.35.1;

    # SSL configuration
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    # OAuth2 Proxy (required for all protected locations)
    location /oauth2/ {
        proxy_pass http://127.0.0.1:4180;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Scheme $scheme;
        proxy_set_header X-Auth-Request-Redirect $request_uri;
        proxy_buffer_size 16k;
        proxy_buffers 8 64k;
        proxy_busy_buffers_size 128k;
    }

    # SSH Helper at root path
    location / {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;

        proxy_pass http://ssh_terminal;
        proxy_http_version 1.1;
        proxy_set_header X-User-Email $email;
        proxy_set_header X-Auth-Request-User $user;

        # WebSocket support for terminal
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

### Application Code (ssh-helper/server.js)

```javascript
// Simple middleware - just read headers!
app.use((req, res, next) => {
    req.user = {
        email: req.headers['x-user-email'] || 'anonymous',
        name: req.headers['x-auth-request-user'] || 'anonymous'
    };
    next();
});

// Use authenticated user info
app.get('/api/user', (req, res) => {
    res.json({
        email: req.user.email,
        name: req.user.name
    });
});
```

### Systemd Service

File: `/etc/systemd/system/ssh-helper.service`

```ini
[Unit]
Description=SSH Helper Web UI
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/ssh-helper
ExecStart=/usr/bin/node /home/ubuntu/src/ssh-helper/server.js
Environment=PORT=8080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable ssh-helper
sudo systemctl start ssh-helper
```

## Example: Website Cloner Integration

### Configuration

Add to nginx (after ssh_helper location):

```nginx
upstream website_cloner {
    server 127.0.0.1:3000;
}

location /cloner/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;

    # Strip /cloner/ prefix
    rewrite ^/cloner/(.*)$ /$1 break;

    proxy_pass http://website_cloner;
    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}

# Redirect /cloner to /cloner/
location = /cloner {
    return 301 /cloner/;
}
```

### Application Code (website-cloner/server.js)

```javascript
// Simple header-based auth
app.use((req, res, next) => {
    req.user = {
        email: req.headers['x-user-email'] || 'anonymous',
        username: req.headers['x-user'] || 'anonymous'
    };
    next();
});

// Use in routes
app.get('/', (req, res) => {
    res.render('index', {
        userEmail: req.user.email
    });
});
```

### Start Service

```bash
cd /home/ubuntu/src/website-cloner
npm install
npm run ui
# Server starts on port 3000
```

## Header Reference

The gateway sets these headers for your application:

| Header | Description | Example |
|--------|-------------|---------|
| `X-User-Email` | Authenticated user's email | `john@example.com` |
| `X-Auth-Request-User` | Username | `john` |
| `X-Real-IP` | Client's real IP address | `203.0.113.5` |
| `X-Forwarded-For` | Forwarded IP chain | `203.0.113.5, 10.0.0.1` |
| `X-Forwarded-Proto` | Original protocol | `https` |

### Reading Headers

**Node.js (Express):**
```javascript
const userEmail = req.headers['x-user-email'];
const username = req.headers['x-auth-request-user'];
```

**Python (Flask):**
```python
from flask import request
user_email = request.headers.get('X-User-Email', 'anonymous')
username = request.headers.get('X-Auth-Request-User', 'anonymous')
```

**Go:**
```go
userEmail := r.Header.Get("X-User-Email")
username := r.Header.Get("X-Auth-Request-User")
```

## Path Strategies

### Option 1: Root Path (One Application)

Best for primary application:
```nginx
location / {
    auth_request /oauth2/auth;
    proxy_pass http://my_app;
}
```

Access: `https://gateway.example.com/`

**Pros:** Clean URL, feels like dedicated domain
**Cons:** Only one app at root

### Option 2: Subdirectory Path (Multiple Applications)

Best for hosting multiple apps:
```nginx
location /app1/ {
    rewrite ^/app1/(.*)$ /$1 break;
    proxy_pass http://app1_backend;
}

location /app2/ {
    rewrite ^/app2/(.*)$ /$1 break;
    proxy_pass http://app2_backend;
}
```

Access:
- `https://gateway.example.com/app1/`
- `https://gateway.example.com/app2/`

**Pros:** Multiple apps, clear separation
**Cons:** URLs have path prefix

### Option 3: Subdomain Path (Enterprise)

Best for many applications:
```nginx
server {
    server_name app1.example.com;
    location / {
        proxy_pass http://app1_backend;
    }
}

server {
    server_name app2.example.com;
    location / {
        proxy_pass http://app2_backend;
    }
}
```

Access:
- `https://app1.example.com/`
- `https://app2.example.com/`

**Pros:** Clean URLs, scalable
**Cons:** Requires DNS setup for each subdomain

## Security Best Practices

### 1. Never Trust Client Headers

nginx MUST clear client-provided auth headers:

```nginx
location /myapp/ {
    # Clear any headers client might send
    proxy_set_header X-User-Email "";
    proxy_set_header X-Auth-Request-User "";

    # Then set from oauth2-proxy only
    auth_request_set $email $upstream_http_x_auth_request_email;
    proxy_set_header X-User-Email $email;
}
```

### 2. Protect All Sensitive Paths

Always use `auth_request`:

```nginx
location /admin/ {
    auth_request /oauth2/auth;  # ← Required!
    proxy_pass http://admin_backend;
}
```

### 3. Health Checks Without Auth

Public endpoints for monitoring:

```nginx
location /health {
    access_log off;
    return 200 "healthy\n";
    add_header Content-Type text/plain;
}
```

### 4. Rate Limiting

Prevent abuse:

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

location /api/ {
    limit_req zone=api burst=20;
    proxy_pass http://api_backend;
}
```

## Troubleshooting

### Authentication Loop

**Symptom:** Continuously redirected to Cognito

**Fix:**
```bash
# Check oauth2-proxy is running
sudo systemctl status oauth2-proxy

# Check Cognito callback URL matches
sudo cat /etc/oauth2-proxy/config.cfg | grep redirect_url
# Should be: https://your-domain.com/oauth2/callback

# Clear browser cookies
# Try incognito mode
```

### Headers Not Passed

**Symptom:** Application sees `anonymous` user

**Fix:**
```bash
# Check nginx config
sudo nginx -t

# Verify auth_request_set lines
sudo grep "auth_request_set" /etc/nginx/sites-available/auth-gateway

# Check application logs
sudo journalctl -u your-app -n 50
```

### WebSocket Connection Failed

**Symptom:** Real-time features don't work

**Fix:**
```nginx
# Ensure WebSocket headers present
location /yourapp/ {
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;  # 24 hours
}
```

### Backend Not Reachable

**Symptom:** 502 Bad Gateway

**Fix:**
```bash
# Check backend is running
netstat -tlnp | grep 3000

# Check backend logs
sudo journalctl -u your-app -n 50

# Test backend directly
curl http://localhost:3000/
```

## Monitoring

### Check All Services

```bash
# Gateway services
sudo systemctl status nginx oauth2-proxy

# Applications
sudo systemctl status ssh-helper website-cloner

# Quick health check
curl -k https://localhost/health
```

### View Logs

```bash
# nginx access log
sudo tail -f /var/log/nginx/access.log

# nginx error log
sudo tail -f /var/log/nginx/error.log

# oauth2-proxy log
sudo journalctl -u oauth2-proxy -f

# Application logs
sudo journalctl -u ssh-helper -f
```

### Monitor Connections

```bash
# Active connections
sudo netstat -an | grep ESTABLISHED | wc -l

# Connections by port
sudo netstat -tlnp | grep -E "443|4180|8080|3000"
```

## Related Documentation

- [Gateway README](../README.md)
- [SSH Helper Deployment](https://github.com/YOUR_USERNAME/ssh-helper/blob/main/docs/DEPLOYMENT.md)
- [Website Cloner Authentication](https://github.com/YOUR_USERNAME/website-cloner/blob/main/docs/AUTHENTICATION.md)
- [Three Repository Architecture](/home/ubuntu/src/THREE_REPO_ARCHITECTURE.md)
