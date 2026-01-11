# Installation Guide

Complete step-by-step guide to install and configure the Easy Cognito Nginx Gateway Auth.

## Prerequisites

Before installation, ensure you have:

### Server Requirements

- **Operating System**: Ubuntu 20.04+ or Debian 10+ (other Linux distros may work with modifications)
- **Architecture**: x86_64 (amd64) or ARM64 (aarch64)
- **Memory**: At least 512MB RAM
- **Root Access**: sudo privileges required
- **Network**: Open ports 80 and 443 (or ability to open them)

### Software Requirements

The installation script will install these if missing:
- nginx (will be installed automatically)
- openssl (for SSL certificates)
- wget or curl (for downloading oauth2-proxy)
- systemd (for service management)

### AWS Requirements

You must have AWS Cognito configured first:
- AWS Cognito User Pool created
- App Client with client secret
- Hosted UI domain configured
- At least one test user

**See [AWS Cognito Setup Guide](AWS_SETUP.md) if you haven't set up Cognito yet.**

### Your Application

- Your web application must be running on a port (e.g., 3000, 4000, 8080)
- It should be accessible via `http://localhost:PORT`

## Installation Methods

### Method 1: Automated Installation (Recommended)

The automated installation script handles everything for you.

#### 1. Clone the Repository

```bash
cd /home/ubuntu/src
git clone https://github.com/YOUR_USERNAME/easy-cognito-nginx-gateway-auth.git
cd easy-cognito-nginx-gateway-auth
```

#### 2. Gather Required Information

You'll need these values:

```bash
DOMAIN="your-domain.com"              # Your domain or IP address
AWS_REGION="us-east-1"                # Your AWS region
COGNITO_POOL_ID="us-east-1_XXXXXX"    # From Cognito User Pool
CLIENT_ID="abcdef123456"               # From Cognito App Client
CLIENT_SECRET="secret123..."           # From Cognito App Client
APP_PORT="3000"                        # Port your app is running on
```

**How to get these values:**
- **COGNITO_POOL_ID**: Cognito Console → User Pools → Your Pool → General Settings
- **CLIENT_ID**: Your User Pool → App Integration → App Clients → Your Client
- **CLIENT_SECRET**: Shown once when creating app client, or regenerate if lost

#### 3. Run the Installation Script

```bash
sudo ./scripts/install.sh \
  --domain=your-domain.com \
  --cognito-region=us-east-1 \
  --cognito-pool-id=us-east-1_XXXXXXXXX \
  --cognito-client-id=YOUR_CLIENT_ID \
  --cognito-client-secret=YOUR_CLIENT_SECRET \
  --app-port=3000
```

**Optional Parameters:**
```bash
--app-name=myapp              # Name for your app in config (default: "app")
--nginx-port-http=80          # HTTP port (default: 80)
--nginx-port-https=443        # HTTPS port (default: 443)
--oauth2-proxy-port=4180      # oauth2-proxy port (default: 4180)
--cookie-expire=24h           # Cookie expiration (default: 24h)
```

#### 4. Verify Installation

The script will output a summary. Run the test suite to verify:

```bash
sudo ./scripts/test-auth.sh
```

You should see all tests passing:
```
✓ oauth2-proxy binary exists
✓ oauth2-proxy process is running
✓ oauth2-proxy listening on port 4180
✓ nginx is running
✓ nginx configuration is valid
✓ nginx listening on ports 80/443
✓ SSL certificates exist
✓ oauth2-proxy config exists
✓ oauth2-proxy config has required fields
✓ nginx auth-gateway config is enabled
```

#### 5. Test in Browser

Open your domain in a browser:
```
https://your-domain.com
```

You should be redirected to AWS Cognito login page. After logging in, you'll be redirected back to your application.

### Method 2: Manual Installation

For more control or custom setups, you can install manually.

#### Step 1: Install nginx

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

#### Step 2: Install oauth2-proxy

```bash
# Run the oauth2-proxy setup script
sudo ./scripts/setup-oauth2-proxy.sh
```

This will:
- Detect your architecture (amd64 or arm64)
- Download oauth2-proxy v7.5.1
- Install to `/usr/local/bin/oauth2-proxy`
- Verify installation

#### Step 3: Generate SSL Certificates

For self-signed certificates:
```bash
sudo ./scripts/setup-ssl.sh --domain=your-domain.com
```

For Let's Encrypt (production):
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

#### Step 4: Configure oauth2-proxy

Create the config directory:
```bash
sudo mkdir -p /etc/oauth2-proxy
```

Copy and customize the template:
```bash
sudo cp config/oauth2-proxy/config.cfg.template /etc/oauth2-proxy/config.cfg
```

Edit the configuration:
```bash
sudo nano /etc/oauth2-proxy/config.cfg
```

Replace these placeholders:
- `{{AWS_REGION}}` → Your AWS region (e.g., us-east-1)
- `{{COGNITO_USER_POOL_ID}}` → Your Cognito pool ID
- `{{COGNITO_CLIENT_ID}}` → Your app client ID
- `{{COGNITO_CLIENT_SECRET}}` → Your app client secret
- `{{DOMAIN}}` → Your domain
- `{{COOKIE_SECRET}}` → Generate with: `openssl rand -base64 32`

#### Step 5: Configure nginx

Copy the nginx config:
```bash
sudo cp config/nginx/auth-gateway.conf.template /etc/nginx/sites-available/auth-gateway
```

Edit the configuration:
```bash
sudo nano /etc/nginx/sites-available/auth-gateway
```

Replace these placeholders:
- `{{DOMAIN}}` → Your domain or IP
- `{{APP1_PORT}}` → Your application port
- `{{SSL_CERT_PATH}}` → Path to SSL certificate
- `{{SSL_KEY_PATH}}` → Path to SSL private key

Enable the site:
```bash
sudo ln -sf /etc/nginx/sites-available/auth-gateway /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default  # Remove default site
```

Test nginx configuration:
```bash
sudo nginx -t
```

Reload nginx:
```bash
sudo systemctl reload nginx
```

#### Step 6: Set up systemd Service

Copy the systemd service file:
```bash
sudo cp config/systemd/oauth2-proxy.service /etc/systemd/system/
```

Reload systemd and start oauth2-proxy:
```bash
sudo systemctl daemon-reload
sudo systemctl enable oauth2-proxy
sudo systemctl start oauth2-proxy
```

#### Step 7: Verify Services

Check oauth2-proxy:
```bash
sudo systemctl status oauth2-proxy
```

Check nginx:
```bash
sudo systemctl status nginx
```

View logs:
```bash
# oauth2-proxy logs
sudo journalctl -u oauth2-proxy -f

# nginx logs
sudo tail -f /var/log/nginx/error.log
```

## Post-Installation

### Update Cognito Callback URLs

Make sure your Cognito app client has the correct callback URL:

1. Go to AWS Cognito Console
2. Select your User Pool
3. Go to **App Integration** → **App Clients**
4. Select your app client
5. Under **Hosted UI**, add these to **Allowed callback URLs**:
   - `https://your-domain.com/oauth2/callback`
   - `http://localhost/oauth2/callback` (for local testing)

6. Add these to **Allowed sign-out URLs**:
   - `https://your-domain.com/oauth2/sign_out`

### Configure DNS (For Domain Names)

If using a domain name, point it to your server:

**A Record:**
```
your-domain.com → YOUR_SERVER_IP
```

### Open Firewall Ports

If using a firewall, open ports 80 and 443:

```bash
# UFW (Ubuntu)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
```

### Test End-to-End Authentication

1. **Visit your site** in a web browser:
   ```
   https://your-domain.com
   ```

2. **You should be redirected** to AWS Cognito login page

3. **Log in** with your Cognito user credentials

4. **You should be redirected back** to your application

5. **Your application receives** the `X-User-Email` header with user information

## Troubleshooting Installation

### Issue: oauth2-proxy won't start

Check logs:
```bash
sudo journalctl -u oauth2-proxy -n 50
```

Common causes:
- Invalid Cognito configuration
- Port 4180 already in use
- Config file syntax error

### Issue: nginx configuration test fails

Check what's wrong:
```bash
sudo nginx -t
```

Common causes:
- Syntax error in config
- Port already in use
- SSL certificate files not found

### Issue: Redirect loop

Check that:
- oauth2-proxy is running: `sudo systemctl status oauth2-proxy`
- Cookie domain matches your domain
- Callback URL is registered in Cognito

### Issue: SSL certificate errors

For self-signed certificates:
- Browser will show warning - click "Advanced" and accept

For production:
- Use Let's Encrypt: `sudo certbot --nginx -d your-domain.com`

### Issue: Port already in use

Check what's using the port:
```bash
sudo ss -tlnp | grep :80
sudo ss -tlnp | grep :443
sudo ss -tlnp | grep :4180
```

Stop conflicting services or use different ports.

## Upgrading

To upgrade oauth2-proxy to a newer version:

1. Edit `scripts/setup-oauth2-proxy.sh` and update `VERSION`
2. Run the setup script again:
   ```bash
   sudo ./scripts/setup-oauth2-proxy.sh
   ```
3. Restart the service:
   ```bash
   sudo systemctl restart oauth2-proxy
   ```

## Uninstalling

To completely remove the authentication gateway:

```bash
# Stop services
sudo systemctl stop oauth2-proxy
sudo systemctl stop nginx

# Disable services
sudo systemctl disable oauth2-proxy

# Remove oauth2-proxy
sudo rm /usr/local/bin/oauth2-proxy
sudo rm -rf /etc/oauth2-proxy
sudo rm /etc/systemd/system/oauth2-proxy.service

# Remove nginx config
sudo rm /etc/nginx/sites-enabled/auth-gateway
sudo rm /etc/nginx/sites-available/auth-gateway

# Remove SSL certificates (if self-signed)
sudo rm -rf /etc/nginx/ssl

# Reload systemd
sudo systemctl daemon-reload

# Optionally remove nginx
sudo apt remove nginx
```

## Next Steps

- **[Configuration Guide](CONFIGURATION.md)** - Customize the gateway for your needs
- **[Multi-App Setup](CONFIGURATION.md#multi-app)** - Protect multiple applications
- **[Production Deployment](PRODUCTION.md)** - Best practices for production
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

## Getting Help

If you encounter issues:

1. Check the [Troubleshooting Guide](TROUBLESHOOTING.md)
2. Review nginx logs: `sudo tail -50 /var/log/nginx/error.log`
3. Review oauth2-proxy logs: `sudo journalctl -u oauth2-proxy -n 50`
4. Open an issue on GitHub with logs and error messages
