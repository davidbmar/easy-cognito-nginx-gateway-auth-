# Basic App Example

Simple Node.js application demonstrating AWS Cognito authentication via the gateway.

## What This Example Shows

- How your application receives authenticated user information
- No authentication code needed in your application
- Accessing user email and other claims from headers

## Prerequisites

- Node.js 14+ installed
- Authentication gateway installed and configured
- nginx configured to proxy to this app

## Installation

```bash
cd examples/basic-app
npm install
```

## Running

```bash
npm start
```

The app will start on port 3001.

## Configuration

### nginx Configuration

Add this to your `/etc/nginx/sites-available/auth-gateway`:

```nginx
upstream basic_app {
    server 127.0.0.1:3001;
}

server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    # OAuth2 endpoints
    location /oauth2/ {
        proxy_pass http://127.0.0.1:4180;
        proxy_set_header Host $host;
    }

    # Protected application
    location / {
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

        # Extract user info from oauth2-proxy
        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;
        auth_request_set $groups $upstream_http_x_auth_request_groups;

        # Pass to application
        proxy_set_header X-User $user;
        proxy_set_header X-User-Email $email;
        proxy_set_header X-User-Groups $groups;

        proxy_pass http://basic_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Reload nginx:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Testing

1. **Start the application:**
   ```bash
   npm start
   ```

2. **Visit in browser:**
   ```
   https://your-domain.com
   ```

3. **You'll be redirected to Cognito login**

4. **After login, you'll see:**
   - Welcome message with your email
   - Your user information from Cognito
   - All request headers

## How It Works

### 1. No Authentication Code in App

The application has **zero authentication code**:

```javascript
app.get('/', (req, res) => {
    // User is already authenticated by nginx + oauth2-proxy
    const userEmail = req.headers['x-user-email'];
    const userName = req.headers['x-user'];

    res.render('index', { userEmail, userName });
});
```

### 2. User Information in Headers

nginx passes user information via headers:

```
X-User-Email: user@example.com
X-User: user@example.com
X-User-Groups: admins,users
```

Your app just reads these headers - no JWT parsing, no OAuth flow, nothing!

### 3. Logout Handling

Logout redirects to oauth2-proxy:

```javascript
app.get('/logout', (req, res) => {
    res.redirect('/oauth2/sign_out');
});
```

## API Endpoints

### GET /

Home page showing authenticated user information.

**Response:** HTML page with user details

### GET /api/user

JSON API returning user information.

**Response:**
```json
{
  "email": "user@example.com",
  "username": "user@example.com",
  "groups": "admins,users"
}
```

### GET /api/headers

Shows all request headers (for debugging).

**Response:**
```json
{
  "host": "your-domain.com",
  "x-user-email": "user@example.com",
  "x-user": "user@example.com",
  ...
}
```

### GET /logout

Logs out the user.

**Response:** Redirect to Cognito logout

## Key Takeaways

✅ **No authentication library needed** - No passport.js, no OAuth client, nothing

✅ **Just read headers** - User information comes in request headers

✅ **Works with any framework** - Express, Flask, Django, Rails, etc.

✅ **Secure** - nginx validates authentication before request reaches your app

✅ **Centralized** - All authentication logic in one place (gateway)

## Extending This Example

### Add Database

Store user preferences using email as identifier:

```javascript
const users = {}; // Or use real database

app.post('/api/preferences', (req, res) => {
    const email = req.headers['x-user-email'];
    users[email] = req.body;
    res.json({ success: true });
});

app.get('/api/preferences', (req, res) => {
    const email = req.headers['x-user-email'];
    res.json(users[email] || {});
});
```

### Role-Based Access Control

```javascript
function requireRole(role) {
    return (req, res, next) => {
        const groups = req.headers['x-user-groups'] || '';
        if (groups.split(',').includes(role)) {
            next();
        } else {
            res.status(403).send('Forbidden');
        }
    };
}

app.get('/admin', requireRole('admin'), (req, res) => {
    res.send('Admin page');
});
```

### Audit Logging

```javascript
app.use((req, res, next) => {
    const email = req.headers['x-user-email'];
    console.log(`${new Date().toISOString()} - ${email} - ${req.method} ${req.path}`);
    next();
});
```

## Production Considerations

- Use environment variables for configuration
- Add proper error handling
- Implement rate limiting
- Add request logging
- Use HTTPS (handled by nginx)
- Monitor application performance

## Related Examples

- **[multi-app](../multi-app/)** - Multiple apps behind one gateway
