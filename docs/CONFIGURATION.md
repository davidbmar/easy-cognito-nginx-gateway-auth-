# Configuration Guide

Comprehensive guide to configuring and customizing the Easy Cognito Nginx Gateway Auth.

## Table of Contents

- [Configuration Files](#configuration-files)
- [oauth2-proxy Configuration](#oauth2-proxy-configuration)
- [nginx Configuration](#nginx-configuration)
- [Multi-App Setup](#multi-app-setup)
- [SSL Configuration](#ssl-configuration)
- [Advanced Options](#advanced-options)
- [Security Settings](#security-settings)

## Configuration Files

The authentication gateway uses three main configuration files:

```
/etc/oauth2-proxy/config.cfg          # oauth2-proxy configuration
/etc/nginx/sites-available/auth-gateway  # nginx reverse proxy config
/etc/systemd/system/oauth2-proxy.service # systemd service
```

## oauth2-proxy Configuration

Location: `/etc/oauth2-proxy/config.cfg`

### Basic Settings

```ini
# Provider configuration
provider = "oidc"
oidc_issuer_url = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXXXXXX"

# Client credentials
client_id = "your-client-id"
client_secret = "your-client-secret"

# Redirect URL (must match Cognito callback URL)
redirect_url = "https://your-domain.com/oauth2/callback"
```

### Cookie Configuration

```ini
# Cookie settings
cookie_name = "_oauth2_proxy"
cookie_secret = "GENERATE_WITH_openssl_rand_-base64_32"
cookie_domains = ["your-domain.com"]
cookie_path = "/"
cookie_expire = "24h"
cookie_refresh = "1h"
cookie_secure = true
cookie_httponly = true
cookie_samesite = "lax"
```

**Cookie Options:**

- **cookie_expire**: How long until user must re-authenticate
  - Values: `24h`, `168h` (1 week), `720h` (30 days)
  - Default: `24h`

- **cookie_refresh**: How often to refresh the token
  - Values: `1h`, `2h`, `4h`
  - Default: `1h`

- **cookie_secure**: Require HTTPS
  - Set to `true` in production
  - Set to `false` for local HTTP testing

- **cookie_samesite**: CSRF protection
  - `lax` - Recommended (allows GET from external sites)
  - `strict` - More secure (blocks all cross-site requests)
  - `none` - Least secure (requires cookie_secure=true)

### Scope Configuration

```ini
# OAuth scopes
scope = "openid email profile"
```

Available scopes:
- `openid` - Required for OIDC
- `email` - User's email address
- `profile` - User's profile information (name, etc.)
- `phone` - User's phone number (if configured in Cognito)

### Upstream Configuration

```ini
# Upstream application
upstreams = [
    "http://127.0.0.1:3000"
]

# Pass authentication headers to app
pass_access_token = false
pass_authorization_header = false
pass_user_headers = true
set_authorization_header = false
set_xauthrequest = true
```

**Header Options:**

- **pass_user_headers**: Passes `X-Forwarded-User`, `X-Forwarded-Email`, etc.
- **pass_access_token**: Passes OAuth access token to app
- **set_xauthrequest**: Sets `X-Auth-Request-User`, `X-Auth-Request-Email`

### Logging

```ini
# Logging configuration
request_logging = true
auth_logging = true
standard_logging = true
```

Log levels:
- Logs go to: `journalctl -u oauth2-proxy`
- Or configured file: `/var/log/oauth2-proxy.log`

### Email Domain Restrictions

Restrict authentication to specific email domains:

```ini
# Only allow users from example.com
email_domains = [
    "example.com"
]

# Or allow all domains
email_domains = ["*"]
```

### Session Storage

```ini
# Session storage (default: cookie)
session_store_type = "cookie"

# For Redis session storage:
# session_store_type = "redis"
# redis_connection_url = "redis://localhost:6379"
```

**Session Storage Options:**

- **cookie** (default): Store session in encrypted cookie
  - Pros: No external dependencies
  - Cons: Cookie size limit (~4KB)

- **redis**: Store session in Redis
  - Pros: Unlimited session data, can revoke sessions
  - Cons: Requires Redis server

## nginx Configuration

Location: `/etc/nginx/sites-available/auth-gateway`

### Basic Reverse Proxy

```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    # OAuth2 proxy endpoints
    location /oauth2/ {
        proxy_pass http://127.0.0.1:4180;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Protected application
    location / {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        # Pass auth headers to app
        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User $user;
        proxy_set_header X-Email $email;

        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Custom Headers

Pass authentication information to your application:

```nginx
location / {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    # Extract user info from oauth2-proxy
    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $preferred_username $upstream_http_x_auth_request_preferred_username;
    auth_request_set $groups $upstream_http_x_auth_request_groups;

    # Pass to application
    proxy_set_header X-User $user;
    proxy_set_header X-User-Email $email;
    proxy_set_header X-User-Name $preferred_username;
    proxy_set_header X-User-Groups $groups;

    proxy_pass http://127.0.0.1:3000;
}
```

Your application can read these headers:

```javascript
// Node.js/Express example
app.get('/', (req, res) => {
    const userEmail = req.headers['x-user-email'];
    const userName = req.headers['x-user-name'];
    res.send(`Hello ${userName} (${userEmail})`);
});
```

### Public Routes (No Authentication)

Allow specific routes without authentication:

```nginx
# OAuth2 endpoints (always public)
location /oauth2/ {
    proxy_pass http://127.0.0.1:4180;
}

# Public route (no auth required)
location /public/ {
    proxy_pass http://127.0.0.1:3000;
}

# Health check (no auth required)
location /health {
    proxy_pass http://127.0.0.1:3000;
}

# All other routes require auth
location / {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
    proxy_pass http://127.0.0.1:3000;
}
```

## Multi-App Setup

Protect multiple applications behind one authentication gateway.

### Scenario: Three Applications

- **app1** at `/app1/` → runs on port 3000
- **app2** at `/app2/` → runs on port 4000
- **app3** at `/app3/` → runs on port 5000

### nginx Configuration

```nginx
upstream app1 {
    server 127.0.0.1:3000;
}

upstream app2 {
    server 127.0.0.1:4000;
}

upstream app3 {
    server 127.0.0.1:5000;
}

server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    # OAuth2 proxy
    location /oauth2/ {
        proxy_pass http://127.0.0.1:4180;
        proxy_set_header Host $host;
    }

    # App 1
    location /app1/ {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User-Email $email;

        rewrite ^/app1/(.*)$ /$1 break;
        proxy_pass http://app1;
    }

    # App 2
    location /app2/ {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User-Email $email;

        rewrite ^/app2/(.*)$ /$1 break;
        proxy_pass http://app2;
    }

    # App 3
    location /app3/ {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User-Email $email;

        rewrite ^/app3/(.*)$ /$1 break;
        proxy_pass http://app3;
    }

    # Landing page
    location = / {
        return 200 "Choose app: /app1/, /app2/, /app3/";
        add_header Content-Type text/plain;
    }
}
```

### Path Rewriting

**Important**: The `rewrite ^/app1/(.*)$ /$1 break;` line strips the `/app1/` prefix before passing to the backend.

Without rewrite:
- User visits: `https://domain.com/app1/dashboard`
- Backend receives: `GET /app1/dashboard`

With rewrite:
- User visits: `https://domain.com/app1/dashboard`
- Backend receives: `GET /dashboard`

**When to use path rewriting:**
- Your app doesn't know about the `/app1/` prefix
- Your app expects to be at root (`/`)

**When NOT to use path rewriting:**
- Your app is aware of the prefix and handles it
- You've configured your app with a `BASE_PATH` environment variable

## SSL Configuration

### Option 1: Self-Signed Certificates (Development)

Generated by `scripts/setup-ssl.sh`:

```nginx
ssl_certificate /etc/nginx/ssl/selfsigned.crt;
ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
```

Browsers will show security warnings. Click "Advanced" and accept.

### Option 2: Let's Encrypt (Production)

Free, auto-renewing SSL certificates:

```bash
# Install certbot
sudo apt install -y certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal is set up automatically
sudo certbot renew --dry-run
```

Certbot automatically updates nginx config:

```nginx
ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
include /etc/letsencrypt/options-ssl-nginx.conf;
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
```

### Option 3: Custom Certificates

If you have your own certificates:

```nginx
ssl_certificate /path/to/your/certificate.crt;
ssl_certificate_key /path/to/your/private.key;

# Optional: Certificate chain
ssl_trusted_certificate /path/to/chain.crt;
```

### SSL Best Practices

```nginx
# Modern SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers off;

# SSL session caching
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;

# HSTS (optional, enables after testing)
# add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

## Advanced Options

### WebSocket Support

If your application uses WebSockets:

```nginx
location / {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}
```

### Large File Uploads

For applications that handle large uploads:

```nginx
# Increase client body size
client_max_body_size 100M;

location /upload {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    client_max_body_size 100M;
    proxy_pass http://127.0.0.1:3000;

    # Increase timeouts for large uploads
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
}
```

### Rate Limiting

Protect against abuse:

```nginx
# Define rate limit zone (outside server block)
limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;

server {
    # Apply rate limiting
    location / {
        limit_req zone=mylimit burst=20 nodelay;

        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
        proxy_pass http://127.0.0.1:3000;
    }
}
```

### IP Whitelisting

Restrict access to specific IPs:

```nginx
location /admin/ {
    # Only allow from specific IPs
    allow 203.0.113.0/24;
    allow 198.51.100.5;
    deny all;

    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
    proxy_pass http://127.0.0.1:3000;
}
```

### Caching

Cache authenticated responses:

```nginx
# Define cache path (outside server block)
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m max_size=1g inactive=60m;

location /api/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    # Enable caching
    proxy_cache my_cache;
    proxy_cache_valid 200 5m;
    proxy_cache_key "$scheme$request_method$host$request_uri$http_authorization";

    proxy_pass http://127.0.0.1:3000;
}
```

## Security Settings

### Recommended Security Headers

```nginx
location / {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval'" always;

    proxy_pass http://127.0.0.1:3000;
}
```

### Hide nginx Version

```nginx
# In http block of /etc/nginx/nginx.conf
http {
    server_tokens off;
}
```

### Disable Unwanted HTTP Methods

```nginx
location / {
    # Only allow specific methods
    limit_except GET POST PUT DELETE {
        deny all;
    }

    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
    proxy_pass http://127.0.0.1:3000;
}
```

## Testing Configuration Changes

After making changes:

1. **Test nginx syntax:**
   ```bash
   sudo nginx -t
   ```

2. **Reload nginx** (graceful, no downtime):
   ```bash
   sudo systemctl reload nginx
   ```

3. **Restart oauth2-proxy** (if config changed):
   ```bash
   sudo systemctl restart oauth2-proxy
   ```

4. **View logs** for errors:
   ```bash
   sudo tail -f /var/log/nginx/error.log
   sudo journalctl -u oauth2-proxy -f
   ```

5. **Test in browser:**
   - Clear cookies
   - Visit site
   - Verify redirect to Cognito
   - Login and verify access

## Configuration Templates

Full configuration templates are in:
- `config/nginx/auth-gateway.conf.template` - Single app
- `config/nginx/multi-app.conf.template` - Multiple apps
- `config/oauth2-proxy/config.cfg.template` - oauth2-proxy config

## Next Steps

- **[Production Deployment](PRODUCTION.md)** - Best practices for production
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Architecture](ARCHITECTURE.md)** - How it all works
