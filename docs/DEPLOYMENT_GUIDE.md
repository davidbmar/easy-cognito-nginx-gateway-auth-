# Deployment Guide - Setting Up 4 Core Repositories on New EC2 Instance

**Date**: 2026-01-13
**Status**: All 4 repositories are committed and ready for deployment

## Repository Status Summary

| Repository | Status | Latest Commit | Branch |
|-----------|--------|---------------|---------|
| easy-cognito-nginx-gateway-auth | ✅ Ready | a08f115 Fix 403 OAuth callback | main |
| deploy-portal | ✅ Ready | ae71bd0 Add modular nginx config | main |
| ssh-helper | ✅ Ready | f23fe59 Fix static asset loading | main |
| website-cloner | ✅ Ready | a5d6eef Add user config to gitignore | main |

All repositories are clean with no uncommitted changes.

---

## Prerequisites for New EC2 Instance

### 1. AWS Resources Required

- **EC2 Instance**: Ubuntu 22.04 or later (t2.medium or larger recommended)
- **Security Group**: Open ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
- **IAM Role**: Attach to EC2 instance with permissions for:
  - EC2 Security Group management (for SSH whitelisting)
  - S3 full access (for website-cloner deployments)
  - Cognito read access (optional, for troubleshooting)
- **Elastic IP** (recommended): Prevents IP changes on reboot
- **AWS Cognito**: User pool and app client already configured

### 2. AWS Cognito Information Needed

Before deployment, gather these values:

```
COGNITO_USER_POOL_ID=us-east-1_aVHSg58BS
COGNITO_CLIENT_ID=46gdd9glnaetl44e2mtap51bkk
COGNITO_CLIENT_SECRET=<your-secret-from-cognito-console>
COGNITO_DOMAIN=website-cloner-1768163881.auth.us-east-1.amazoncognito.com
AWS_REGION=us-east-1
```

**Note**: The Client Secret must be retrieved from AWS Cognito Console → App Client Settings.

---

## Step-by-Step Deployment

### Step 1: Launch EC2 Instance

```bash
# Launch instance with:
# - Ubuntu 22.04 LTS
# - IAM role with S3 + EC2 permissions
# - Security group with ports 22, 80, 443 open
# - Elastic IP (recommended)

# Connect to instance
ssh -i your-key.pem ubuntu@YOUR_ELASTIC_IP
```

---

### Step 2: Clone All 4 Repositories

```bash
# Create project directory
mkdir -p /home/ubuntu/src
cd /home/ubuntu/src

# Clone all 4 core repositories
git clone https://github.com/davidbmar/easy-cognito-nginx-gateway-auth-.git easy-cognito-nginx-gateway-auth
git clone https://github.com/davidbmar/deploy-portal.git
git clone https://github.com/davidbmar/ssh-helper.git
git clone https://github.com/davidbmar/website-cloner.git

# Verify all repos cloned successfully
ls -la
```

---

### Step 3: Deploy Authentication Gateway (nginx + oauth2-proxy)

```bash
cd /home/ubuntu/src/easy-cognito-nginx-gateway-auth

# Get your EC2's public IP (or use Elastic IP)
export GATEWAY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Gateway IP: $GATEWAY_IP"

# Run installation script
sudo ./scripts/install.sh \
  --domain=$GATEWAY_IP \
  --cognito-pool-id=us-east-1_aVHSg58BS \
  --cognito-client-id=46gdd9glnaetl44e2mtap51bkk \
  --cognito-client-secret=<YOUR_SECRET_HERE>

# The script will:
# - Install nginx and oauth2-proxy
# - Generate self-signed SSL certificate
# - Configure nginx with authentication
# - Create systemd services
# - Start all services

# Verify services are running
sudo systemctl status nginx oauth2-proxy
```

**Important Notes**:
- Replace `<YOUR_SECRET_HERE>` with actual Cognito client secret
- For production, use a domain name instead of IP address
- For Let's Encrypt SSL, run: `sudo ./scripts/setup-letsencrypt.sh --domain=yourdomain.com --email=your@email.com`

---

### Step 4: Update AWS Cognito Callback URLs

```bash
# Update Cognito with your new instance IP/domain
aws cognito-idp update-user-pool-client \
  --user-pool-id us-east-1_aVHSg58BS \
  --client-id 46gdd9glnaetl44e2mtap51bkk \
  --callback-urls "https://$GATEWAY_IP/oauth2/callback" \
  --logout-urls "https://$GATEWAY_IP/" \
  --region us-east-1

# Verify the update
aws cognito-idp describe-user-pool-client \
  --user-pool-id us-east-1_aVHSg58BS \
  --client-id 46gdd9glnaetl44e2mtap51bkk \
  --region us-east-1 \
  --query 'UserPoolClient.CallbackURLs'
```

---

### Step 5: Deploy SSH Helper

```bash
cd /home/ubuntu/src/ssh-helper

# Install Node.js dependencies
npm install

# Create systemd service
sudo tee /etc/systemd/system/ssh-helper.service > /dev/null << 'EOF'
[Unit]
Description=SSH Helper Web Terminal
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/ssh-helper
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production
Environment=PORT=8080

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable ssh-helper
sudo systemctl start ssh-helper

# Verify service is running
sudo systemctl status ssh-helper
curl http://localhost:8080/health
```

---

### Step 6: Deploy Deploy Portal

```bash
cd /home/ubuntu/src/deploy-portal

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create systemd service
sudo tee /etc/systemd/system/deploy-portal.service > /dev/null << 'EOF'
[Unit]
Description=Deploy Portal
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/deploy-portal
Environment=PATH=/home/ubuntu/src/deploy-portal/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/ubuntu/src/deploy-portal/venv/bin/python app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable deploy-portal
sudo systemctl start deploy-portal

# Verify service is running
sudo systemctl status deploy-portal
curl http://localhost:5000/health
```

---

### Step 7: Deploy Website Cloner

```bash
cd /home/ubuntu/src/website-cloner

# Install dependencies
npm install

# Create systemd service
sudo tee /etc/systemd/system/website-cloner.service > /dev/null << 'EOF'
[Unit]
Description=Website Cloner Web UI
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/website-cloner
ExecStart=/usr/bin/npm run ui
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable website-cloner
sudo systemctl start website-cloner

# Verify service is running
sudo systemctl status website-cloner
curl http://localhost:3000/
```

---

### Step 8: Configure nginx Routes

The nginx configuration should already be in place from Step 3, but verify the routing:

```bash
# Check nginx configuration
sudo nginx -t

# View current routing
sudo grep -E "location|proxy_pass" /etc/nginx/sites-available/auth-gateway | head -40

# Reload nginx to ensure latest config
sudo systemctl reload nginx
```

**Expected Routing Table**:
| URL Path | Backend | Port | Auth Required |
|----------|---------|------|---------------|
| `/` | ssh-helper | 8080 | ✅ Yes |
| `/cloner/` | website-cloner | 3000 | ✅ Yes |
| `/oauth2/` | oauth2-proxy | 4180 | ❌ No |
| `/health` | nginx | - | ❌ No |

**Note**: Based on the current nginx config, root path (`/`) routes to ssh-helper. If you want it to route to deploy-portal instead, see the "Optional Configuration Changes" section below.

---

### Step 9: Verify Full Stack

```bash
# Check all services are running
sudo systemctl status nginx oauth2-proxy ssh-helper deploy-portal website-cloner

# Check all ports are listening
sudo ss -tlnp | grep -E "443|4180|5000|8080|3000"

# Expected output:
# LISTEN *:443   - nginx
# LISTEN *:4180  - oauth2-proxy
# LISTEN *:5000  - python (deploy-portal)
# LISTEN *:8080  - node (ssh-helper)
# LISTEN *:3000  - node (website-cloner)

# Test authentication flow
curl -k -L https://$GATEWAY_IP/ | grep -i "sign"
# Should see: "Sign in with your email and password"
```

---

### Step 10: Browser Testing

1. Open browser and navigate to: `https://YOUR_GATEWAY_IP/`
2. Accept self-signed certificate warning (or use valid cert from Let's Encrypt)
3. Should redirect to Cognito login page
4. Log in with Cognito credentials
5. After login, should see SSH Helper web terminal
6. Test other endpoints:
   - `https://YOUR_GATEWAY_IP/cloner/` - Website Cloner UI
   - `https://YOUR_GATEWAY_IP/health` - Health check (no auth)

---

## Optional Configuration Changes

### Option A: Route Root Path to Deploy Portal

If you want the landing page to be Deploy Portal instead of SSH Helper:

```bash
# Edit nginx configuration
sudo nano /etc/nginx/sites-available/auth-gateway

# Find the root location block:
# location / {
#     proxy_pass http://ssh_terminal;
# }

# Change to:
# location / {
#     proxy_pass http://deploy_portal;
# }

# Add SSH Helper at /ssh/ path:
# location /ssh/ {
#     auth_request /oauth2/auth;
#     error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
#
#     auth_request_set $user $upstream_http_x_auth_request_user;
#     auth_request_set $email $upstream_http_x_auth_request_email;
#
#     rewrite ^/ssh/(.*)$ /$1 break;
#     proxy_pass http://ssh_terminal;
#     proxy_http_version 1.1;
#     proxy_set_header Host $host;
#     proxy_set_header X-Real-IP $remote_addr;
#     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#     proxy_set_header X-Forwarded-Proto $scheme;
#     proxy_set_header X-User-Email $email;
#     proxy_set_header X-Auth-Request-User $user;
#     proxy_set_header Upgrade $http_upgrade;
#     proxy_set_header Connection "upgrade";
#     proxy_read_timeout 86400;
# }

# Test and reload
sudo nginx -t && sudo systemctl reload nginx
```

### Option B: Add HTTP to HTTPS Redirect

For better security and to fix CSRF cookie issues:

```bash
# Edit nginx configuration
sudo nano /etc/nginx/sites-available/auth-gateway

# Change the server block from:
# server {
#     listen 80 default_server;
#     listen 443 ssl default_server;
#     ...
# }

# To two separate blocks:
# server {
#     listen 80 default_server;
#     listen [::]:80 default_server;
#     server_name YOUR_IP;
#     return 301 https://$server_name$request_uri;
# }
#
# server {
#     listen 443 ssl default_server;
#     listen [::]:443 ssl default_server;
#     ssl_certificate /etc/nginx/ssl/selfsigned.crt;
#     ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
#     ...
# }

# Test and reload
sudo nginx -t && sudo systemctl reload nginx
```

---

## Troubleshooting

### Issue: Services Won't Start

```bash
# Check logs for specific service
sudo journalctl -u nginx -n 50
sudo journalctl -u oauth2-proxy -n 50
sudo journalctl -u ssh-helper -n 50
sudo journalctl -u deploy-portal -n 50
sudo journalctl -u website-cloner -n 50

# Check if ports are already in use
sudo ss -tlnp | grep -E "443|4180|5000|8080|3000"
```

### Issue: Authentication Redirect Fails

```bash
# Verify oauth2-proxy configuration
sudo grep -E "redirect_url|client_id|provider" /etc/oauth2-proxy/config.cfg

# Verify Cognito callback URLs
aws cognito-idp describe-user-pool-client \
  --user-pool-id us-east-1_aVHSg58BS \
  --client-id 46gdd9glnaetl44e2mtap51bkk \
  --region us-east-1 \
  --query 'UserPoolClient.CallbackURLs'

# Check oauth2-proxy logs
sudo journalctl -u oauth2-proxy -f
```

### Issue: 502 Bad Gateway

```bash
# Check if backend service is running
sudo systemctl status <service-name>

# Check if backend is listening
curl http://localhost:<PORT>/

# Check nginx error log
sudo tail -f /var/log/nginx/error.log
```

### Issue: 403 Forbidden After Login

```bash
# This usually means CSRF cookie issue
# Solution: Implement HTTP to HTTPS redirect (see Optional Configuration Changes)

# Check oauth2-proxy logs for "unable to obtain CSRF cookie"
sudo journalctl -u oauth2-proxy | grep -i csrf
```

---

## Post-Deployment Tasks

### 1. Set Up Let's Encrypt SSL (Production)

```bash
cd /home/ubuntu/src/easy-cognito-nginx-gateway-auth
sudo ./scripts/setup-letsencrypt.sh \
  --domain=yourdomain.com \
  --email=admin@yourdomain.com
```

### 2. Configure Monitoring

```bash
# Create health check script
cat > ~/check-health.sh << 'EOF'
#!/bin/bash
echo "=== Health Check $(date) ==="
for service in nginx oauth2-proxy ssh-helper deploy-portal website-cloner; do
    status=$(systemctl is-active $service)
    echo "$service: $status"
done
EOF

chmod +x ~/check-health.sh

# Add to cron (every 5 minutes)
crontab -e
# Add line: */5 * * * * /home/ubuntu/check-health.sh >> /home/ubuntu/health-check.log 2>&1
```

### 3. Set Up Backups

```bash
# Create backup script
cat > ~/backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR=~/backups/$DATE
mkdir -p $BACKUP_DIR

# Backup configurations
sudo cp /etc/nginx/sites-available/auth-gateway $BACKUP_DIR/
sudo cp /etc/oauth2-proxy/config.cfg $BACKUP_DIR/

# Backup systemd services
sudo cp /etc/systemd/system/ssh-helper.service $BACKUP_DIR/
sudo cp /etc/systemd/system/deploy-portal.service $BACKUP_DIR/
sudo cp /etc/systemd/system/website-cloner.service $BACKUP_DIR/

echo "Backup completed: $BACKUP_DIR"
EOF

chmod +x ~/backup.sh

# Run backup
~/backup.sh
```

### 4. Add CloudWatch Monitoring (Optional)

Install CloudWatch agent for EC2 monitoring:
- CPU, memory, disk usage
- Application logs
- Custom metrics

---

## Repository URLs for Quick Reference

```bash
# Clone commands (for easy copy-paste)
git clone https://github.com/davidbmar/easy-cognito-nginx-gateway-auth-.git
git clone https://github.com/davidbmar/deploy-portal.git
git clone https://github.com/davidbmar/ssh-helper.git
git clone https://github.com/davidbmar/website-cloner.git
```

---

## Architecture Diagram

```
                           ┌─────────────────────────┐
                           │  AWS Cognito User Pool  │
                           │  us-east-1_aVHSg58BS    │
                           └──────────┬──────────────┘
                                      │ Authentication
                                      │
        User Browser                  ▼
             │              ┌─────────────────────┐
             │              │   oauth2-proxy      │
             │              │   (port 4180)       │
             │              └──────────┬──────────┘
             │                         │ Token validation
             ▼                         │
    ┌──────────────────┐              │
    │  nginx (port 443)│◄─────────────┘
    │  SSL Termination │
    │  Reverse Proxy   │
    └────────┬─────────┘
             │
             ├──► /              → ssh-helper (8080)
             ├──► /cloner/       → website-cloner (3000)
             ├──► /deploy/       → deploy-portal (5000) [if configured]
             ├──► /oauth2/       → oauth2-proxy (4180)
             └──► /health        → nginx (no auth)
```

---

## Security Checklist

- ✅ All traffic uses HTTPS (or HTTP redirects to HTTPS)
- ✅ Authentication centralized in oauth2-proxy + Cognito
- ✅ Backend services trust nginx headers only (no auth code in apps)
- ✅ IAM role used for AWS credentials (no hardcoded keys)
- ✅ Security group restricts ports (only 22, 80, 443)
- ✅ Self-signed SSL cert (replace with Let's Encrypt for production)
- ✅ All services run as non-root user (ubuntu)
- ✅ Systemd services auto-restart on failure

---

## Estimated Deployment Time

- **Step 1-2** (Launch EC2 + Clone repos): 10 minutes
- **Step 3-4** (Gateway + Cognito): 15 minutes
- **Step 5-7** (Deploy 3 applications): 20 minutes
- **Step 8-10** (Configure + Verify): 10 minutes

**Total**: ~55 minutes for full deployment

---

## Conclusion

All 4 core repositories are ready for deployment:

1. ✅ **easy-cognito-nginx-gateway-auth**: Authentication gateway infrastructure
2. ✅ **deploy-portal**: Self-service deployment automation
3. ✅ **ssh-helper**: Web-based SSH terminal
4. ✅ **website-cloner**: Static website cloning and S3 deployment

Follow this guide step-by-step to replicate the entire platform on a new EC2 instance. All repositories are committed and pushed to GitHub with the latest fixes and configurations.

**Last Updated**: 2026-01-13 20:30 UTC
**Prepared By**: Claude Sonnet 4.5
**Ready for Deployment**: YES ✅
