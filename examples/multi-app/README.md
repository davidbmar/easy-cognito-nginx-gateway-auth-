# Multi-App Example

Demonstrates protecting multiple applications behind a single authentication gateway.

## Scenario

Three different applications running on different ports, all protected by one AWS Cognito authentication gateway:

- **App 1** (Dashboard) - Port 3001 - Accessible at `/app1/`
- **App 2** (Analytics) - Port 3002 - Accessible at `/app2/`
- **App 3** (Settings) - Port 3003 - Accessible at `/app3/`

## Architecture

```
User Browser
     ↓
   nginx (443)
     ↓
  ┌──┴──────────────┐
  ↓                 ↓
oauth2-proxy    /app1/ → localhost:3001
  (4180)        /app2/ → localhost:3002
                /app3/ → localhost:3003
```

## Benefits

- **Single Sign-On**: Authenticate once, access all apps
- **Centralized Management**: One configuration for all apps
- **Consistent Security**: Same authentication for all apps
- **Easy to Scale**: Add new apps without changing authentication
- **No Code Changes**: Apps don't need authentication code

## Installation

```bash
cd examples/multi-app

# Install dependencies for all apps
cd app1 && npm install && cd ..
cd app2 && npm install && cd ..
cd app3 && npm install && cd ..

# Or use the install script
chmod +x install.sh
./install.sh
```

## Running

### Start All Apps

```bash
# Terminal 1 - App 1
cd app1 && npm start

# Terminal 2 - App 2
cd app2 && npm start

# Terminal 3 - App 3
cd app3 && npm start
```

Or use the start script:
```bash
chmod +x start-all.sh
./start-all.sh
```

This starts all apps in the background. View logs:
```bash
tail -f logs/*.log
```

Stop all apps:
```bash
./stop-all.sh
```

## nginx Configuration

Add this to `/etc/nginx/sites-available/auth-gateway`:

```nginx
# Upstream definitions
upstream app1 {
    server 127.0.0.1:3001;
}

upstream app2 {
    server 127.0.0.1:3002;
}

upstream app3 {
    server 127.0.0.1:3003;
}

upstream oauth2_proxy {
    server 127.0.0.1:4180;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    # OAuth2 proxy endpoints
    location /oauth2/ {
        proxy_pass http://oauth2_proxy;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Buffer settings for OAuth flow
        proxy_buffer_size 16k;
        proxy_buffers 8 64k;
        proxy_busy_buffers_size 128k;
    }

    # Landing page
    location = / {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User-Email $email;

        return 200 "Available apps:\n  - /app1/ (Dashboard)\n  - /app2/ (Analytics)\n  - /app3/ (Settings)\n";
        add_header Content-Type text/plain;
    }

    # App 1 - Dashboard
    location /app1/ {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User $user;
        proxy_set_header X-User-Email $email;
        proxy_set_header X-App-Path /app1;

        # Strip /app1/ prefix before proxying
        rewrite ^/app1/(.*)$ /$1 break;
        proxy_pass http://app1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # App 2 - Analytics
    location /app2/ {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User $user;
        proxy_set_header X-User-Email $email;
        proxy_set_header X-App-Path /app2;

        # Strip /app2/ prefix before proxying
        rewrite ^/app2/(.*)$ /$1 break;
        proxy_pass http://app2;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # App 3 - Settings
    location /app3/ {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User $user;
        proxy_set_header X-User-Email $email;
        proxy_set_header X-App-Path /app3;

        # Strip /app3/ prefix before proxying
        rewrite ^/app3/(.*)$ /$1 break;
        proxy_pass http://app3;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP redirect to HTTPS
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}
```

Reload nginx:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Testing

1. **Start all applications:**
   ```bash
   ./start-all.sh
   ```

2. **Visit in browser:**
   ```
   https://your-domain.com/app1/
   https://your-domain.com/app2/
   https://your-domain.com/app3/
   ```

3. **You'll be prompted to login** (only once)

4. **After login, you can access all three apps** without logging in again

5. **Navigate between apps** using the navigation menu

## Path Rewriting

**Important:** The `rewrite ^/app1/(.*)$ /$1 break;` directive strips the `/app1/` prefix.

**Without rewrite:**
- User visits: `https://domain.com/app1/dashboard`
- App receives: `GET /app1/dashboard`

**With rewrite:**
- User visits: `https://domain.com/app1/dashboard`
- App receives: `GET /dashboard`

This allows apps to work without knowing they're behind a path prefix.

### When Your App Needs the Prefix

If your app is aware of the prefix and handles it internally:

```nginx
# Don't use rewrite
location /app1/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    # No rewrite - pass path as-is
    proxy_pass http://app1;
}
```

Configure your app:
```javascript
// Express example
const app = express();
app.use('/app1', routes); // App knows about /app1 prefix
```

## Adding a New App

To add a fourth app:

1. **Create the application:**
   ```bash
   mkdir app4
   cd app4
   # Set up your application on a new port (e.g., 3004)
   ```

2. **Add upstream to nginx:**
   ```nginx
   upstream app4 {
       server 127.0.0.1:3004;
   }
   ```

3. **Add location block:**
   ```nginx
   location /app4/ {
       auth_request /oauth2/auth;
       error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

       auth_request_set $email $upstream_http_x_auth_request_email;
       proxy_set_header X-User-Email $email;

       rewrite ^/app4/(.*)$ /$1 break;
       proxy_pass http://app4;
   }
   ```

4. **Reload nginx:**
   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   ```

5. **Start the app:**
   ```bash
   cd app4 && npm start
   ```

That's it! No authentication code needed in the new app.

## Session Sharing

All apps share the same authentication session because:

1. **Same cookie domain**: All apps under `your-domain.com`
2. **Same oauth2-proxy**: All auth requests go through same proxy
3. **Same Cognito session**: User authenticated once in Cognito

**Benefits:**
- User logs in once
- Session valid across all apps
- Logout affects all apps
- No duplicate authentication

## Different Apps, Different Technologies

The apps don't need to be Node.js. You can mix:

- **App 1**: Node.js + Express
- **App 2**: Python + Flask
- **App 3**: Ruby + Rails
- **App 4**: Static HTML
- **App 5**: Go + net/http

They all work the same way - just read the `X-User-Email` header!

### Python (Flask) Example

```python
from flask import Flask, request

app = Flask(__name__)

@app.route('/')
def index():
    user_email = request.headers.get('X-User-Email', 'anonymous')
    return f'Hello {user_email}!'
```

### Go Example

```go
package main

import (
    "fmt"
    "net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
    email := r.Header.Get("X-User-Email")
    fmt.Fprintf(w, "Hello %s!", email)
}

func main() {
    http.HandleFunc("/", handler)
    http.ListenAndServe(":3001", nil)
}
```

## Production Considerations

- Use process managers (PM2, systemd) to keep apps running
- Set up monitoring for each app
- Configure proper logging
- Use health checks for each app
- Consider load balancing for high traffic apps
- Set resource limits per app

## Useful Scripts

### Check if all apps are running

```bash
#!/bin/bash
for port in 3001 3002 3003; do
    if curl -s http://localhost:$port/health > /dev/null; then
        echo "✓ App on port $port is running"
    else
        echo "✗ App on port $port is NOT running"
    fi
done
```

### Restart all apps

```bash
#!/bin/bash
./stop-all.sh
sleep 2
./start-all.sh
echo "All apps restarted"
```

## Related Examples

- **[basic-app](../basic-app/)** - Simple single-app example
